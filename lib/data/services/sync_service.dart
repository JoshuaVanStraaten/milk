import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/cached_list_repository.dart';
import '../local/hive_database.dart';
import '../repositories/list_repository.dart';
import '../models/shopping_list.dart';
import '../models/list_item.dart';
import 'connectivity_service.dart';

/// Service to sync offline changes when connectivity is restored
class SyncService {
  final ListRepository _remoteRepository;
  final CachedListRepository _cacheRepository;
  final ConnectivityService _connectivityService;

  StreamSubscription<ConnectivityStatus>? _connectivitySubscription;
  bool _isSyncing = false;

  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  SyncService({
    required ListRepository remoteRepository,
    required CachedListRepository cacheRepository,
    required ConnectivityService connectivityService,
  }) : _remoteRepository = remoteRepository,
       _cacheRepository = cacheRepository,
       _connectivityService = connectivityService;

  /// Initialize sync service and listen for connectivity changes
  void initialize() {
    _connectivitySubscription = _connectivityService.statusStream.listen((
      status,
    ) {
      if (status == ConnectivityStatus.online) {
        debugPrint('Back online - triggering sync');
        syncPendingChanges();
      }
    });

    // Initial sync if online and has pending changes
    if (_connectivityService.isOnline &&
        _cacheRepository.hasPendingSyncOperations()) {
      syncPendingChanges();
    }
  }

  /// Sync all pending changes to the server
  Future<SyncResult> syncPendingChanges() async {
    if (_isSyncing) {
      debugPrint('Sync already in progress');
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!_connectivityService.isOnline) {
      debugPrint('Cannot sync - device is offline');
      return SyncResult(success: false, message: 'Device is offline');
    }

    var pendingOps = _cacheRepository.getPendingSyncOperations();
    if (pendingOps.isEmpty) {
      debugPrint('No pending operations to sync');
      return SyncResult(
        success: true,
        message: 'Nothing to sync',
        syncedCount: 0,
      );
    }

    // Sort operations: lists before items, creates before updates before deletes
    // This ensures parent entities exist before children are synced
    pendingOps = _sortOperationsForSync(pendingOps);

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    // Track list ID mappings (temp ID -> server ID) for updating item references
    final listIdMappings = <String, String>{};

    debugPrint('Starting sync of ${pendingOps.length} operations');

    for (final operation in pendingOps) {
      try {
        // If this is an item operation, check if we need to update the list ID
        final processedOperation = _updateOperationListId(
          operation,
          listIdMappings,
        );

        final result = await _processOperation(processedOperation);

        // If a list was created, store the ID mapping
        if (result != null &&
            operation.entityType == 'list' &&
            operation.type == SyncOperationType.create) {
          listIdMappings[operation.entityId] = result;
          debugPrint('List ID mapping: ${operation.entityId} -> $result');
        }

        await _cacheRepository.removeFromSyncQueue(operation.id);
        successCount++;
        debugPrint(
          'Synced: ${operation.type} ${operation.entityType} ${operation.entityId}',
        );
      } catch (e) {
        failCount++;
        errors.add('${operation.entityType}/${operation.entityId}: $e');
        debugPrint('Sync failed for ${operation.entityId}: $e');

        // Increment retry count
        await _cacheRepository.incrementRetryCount(operation.id);

        // Remove if too many retries (max 5)
        if (operation.retryCount >= 5) {
          debugPrint(
            'Removing operation after 5 failed retries: ${operation.id}',
          );
          await _cacheRepository.removeFromSyncQueue(operation.id);
        }
      }
    }

    _isSyncing = false;

    if (failCount == 0) {
      _syncStatusController.add(SyncStatus.synced);
      await _cacheRepository.setLastSyncTime(DateTime.now());
    } else {
      _syncStatusController.add(SyncStatus.error);
    }

    final result = SyncResult(
      success: failCount == 0,
      message: failCount == 0
          ? 'Synced $successCount changes'
          : 'Synced $successCount, failed $failCount',
      syncedCount: successCount,
      failedCount: failCount,
      errors: errors,
    );

    debugPrint('Sync complete: ${result.message}');
    return result;
  }

  /// Sort operations so lists are synced before items
  List<SyncOperation> _sortOperationsForSync(List<SyncOperation> operations) {
    // Priority:
    // 1. List creates (need to exist before items can reference them)
    // 2. List updates
    // 3. Item creates
    // 4. Item updates
    // 5. Item deletes
    // 6. List deletes (delete items first)

    int getPriority(SyncOperation op) {
      if (op.entityType == 'list') {
        switch (op.type) {
          case SyncOperationType.create:
            return 0;
          case SyncOperationType.update:
            return 1;
          case SyncOperationType.delete:
            return 5;
        }
      } else {
        switch (op.type) {
          case SyncOperationType.create:
            return 2;
          case SyncOperationType.update:
            return 3;
          case SyncOperationType.delete:
            return 4;
        }
      }
    }

    final sorted = List<SyncOperation>.from(operations);
    sorted.sort((a, b) => getPriority(a).compareTo(getPriority(b)));
    return sorted;
  }

  /// Update item operation's list ID if we have a mapping from temp to server ID
  SyncOperation _updateOperationListId(
    SyncOperation operation,
    Map<String, String> listIdMappings,
  ) {
    if (operation.entityType != 'item' || operation.data == null) {
      return operation;
    }

    final data = Map<String, dynamic>.from(operation.data!);
    final listId = data['ShoppingList_ID'] as String?;

    if (listId != null && listIdMappings.containsKey(listId)) {
      data['ShoppingList_ID'] = listIdMappings[listId];
      debugPrint('Updated item list ID: $listId -> ${listIdMappings[listId]}');
      return SyncOperation(
        id: operation.id,
        type: operation.type,
        entityType: operation.entityType,
        entityId: operation.entityId,
        data: data,
        createdAt: operation.createdAt,
        retryCount: operation.retryCount,
      );
    }

    return operation;
  }

  /// Process an operation and return the server ID if a list was created
  Future<String?> _processOperation(SyncOperation operation) async {
    switch (operation.entityType) {
      case 'list':
        return await _processListOperation(operation);
      case 'item':
        await _processItemOperation(operation);
        return null;
      default:
        throw Exception('Unknown entity type: ${operation.entityType}');
    }
  }

  Future<String?> _processListOperation(SyncOperation operation) async {
    switch (operation.type) {
      case SyncOperationType.create:
        if (operation.data != null) {
          final list = ShoppingList.fromJson(operation.data!);
          debugPrint(
            'Syncing list create: ${list.listName} (temp ID: ${operation.entityId})',
          );
          // Create on server - will get a new ID
          final created = await _remoteRepository.createList(
            listName: list.listName,
            storeName: list.storeName,
            listColour: list.listColour,
          );
          debugPrint(
            'List created on server with ID: ${created.shoppingListId}',
          );
          // Update local cache with server ID
          await _cacheRepository.deleteList(operation.entityId); // Remove temp
          await _cacheRepository.saveList(created);
          // Store the ID mapping so UI can resolve old IDs
          await _cacheRepository.storeListIdMapping(
            operation.entityId,
            created.shoppingListId,
          );
          // Update any items that reference the old ID in cache
          await _updateItemsListId(operation.entityId, created.shoppingListId);
          // Return the new server ID for item reference updates
          return created.shoppingListId;
        }
        return null;

      case SyncOperationType.update:
        if (operation.data != null) {
          final list = ShoppingList.fromJson(operation.data!);
          await _remoteRepository.updateList(list);
        }
        return null;

      case SyncOperationType.delete:
        await _remoteRepository.deleteList(operation.entityId);
        return null;
    }
  }

  Future<void> _processItemOperation(SyncOperation operation) async {
    switch (operation.type) {
      case SyncOperationType.create:
        if (operation.data != null) {
          final item = ListItem.fromJson(operation.data!);
          debugPrint(
            'Syncing item create: ${item.itemName} for list ${item.shoppingListId}',
          );

          // Check if the list exists in cache (should have been synced already)
          final listExists =
              _cacheRepository.getListById(item.shoppingListId) != null;
          if (!listExists) {
            debugPrint(
              '⚠️ Skipping orphan item - list ${item.shoppingListId} does not exist',
            );
            // Remove the orphan item from cache too
            await _cacheRepository.deleteItem(operation.entityId);
            return; // Skip this operation
          }

          // Create on server (server will generate new ID)
          final created = await _remoteRepository.addItem(
            listId: item.shoppingListId,
            itemName: item.itemName,
            itemPrice: item.itemPrice,
            itemQuantity: item.itemQuantity,
            itemNote: item.itemNote,
            itemRetailer: item.itemRetailer,
            itemSpecialPrice: item.itemSpecialPrice,
          );
          debugPrint('Item created on server with ID: ${created.itemId}');
          // Update local cache: remove temp item, save server item
          await _cacheRepository.deleteItem(operation.entityId);
          await _cacheRepository.saveItem(created);
        }
        break;

      case SyncOperationType.update:
        if (operation.data != null) {
          final item = ListItem.fromJson(operation.data!);
          debugPrint('Syncing item update: ${item.itemId}');
          await _remoteRepository.updateItem(item);
        }
        break;

      case SyncOperationType.delete:
        // We need the listId for delete, try to get from data or cached item
        final listId = operation.data?['ShoppingList_ID'] as String? ?? '';
        debugPrint(
          'Syncing item delete: ${operation.entityId} from list $listId',
        );
        if (listId.isNotEmpty) {
          await _remoteRepository.deleteItem(operation.entityId, listId);
        }
        break;
    }
  }

  Future<void> _updateItemsListId(String oldListId, String newListId) async {
    final items = _cacheRepository.getItemsForList(oldListId);
    for (final item in items) {
      final updated = item.copyWith(shoppingListId: newListId);
      await _cacheRepository.saveItem(updated);
    }
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
}

/// Sync status enum
enum SyncStatus { idle, syncing, synced, error }

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int failedCount;
  final List<String> errors;

  SyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
    this.failedCount = 0,
    this.errors = const [],
  });
}

/// Provider for SyncService
final syncServiceProvider = Provider<SyncService>((ref) {
  final remoteRepo = ref.watch(_syncListRepositoryProvider);
  final cacheRepo = CachedListRepository();
  final connectivity = ref.watch(connectivityServiceProvider);

  final service = SyncService(
    remoteRepository: remoteRepo,
    cacheRepository: cacheRepo,
    connectivityService: connectivity,
  );

  // Initialize the service to start listening for connectivity changes
  service.initialize();

  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for sync status stream
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service.syncStatusStream;
});

/// Provider for pending sync count
final pendingSyncCountProvider = Provider<int>((ref) {
  final cacheRepo = CachedListRepository();
  return cacheRepo.getPendingSyncCount();
});

/// Provider for ListRepository (used by sync service)
/// Note: This is also defined in list_provider.dart - use that one for UI components
final _syncListRepositoryProvider = Provider<ListRepository>((ref) {
  return ListRepository();
});
