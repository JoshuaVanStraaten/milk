import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/shopping_list.dart';
import '../models/list_item.dart';
import '../repositories/list_repository.dart';
import 'cached_list_repository.dart';
import 'hive_database.dart';
import '../services/connectivity_service.dart';

/// Offline-aware repository that combines local cache with remote Supabase
///
/// Strategy:
/// - READ: Return cached data immediately, then refresh from network
/// - WRITE (online): Write to remote, then cache locally
/// - WRITE (offline): Write to local cache, queue for sync
class OfflineListRepository {
  final ListRepository _remoteRepository;
  final CachedListRepository _cacheRepository;
  final ConnectivityService _connectivityService;

  OfflineListRepository({
    required ListRepository remoteRepository,
    required CachedListRepository cacheRepository,
    required ConnectivityService connectivityService,
  }) : _remoteRepository = remoteRepository,
       _cacheRepository = cacheRepository,
       _connectivityService = connectivityService;

  // ============ Shopping Lists ============

  /// Get user's shopping lists (cache-first, then network)
  Future<List<ShoppingList>> getUserLists() async {
    // First, return cached data
    final cachedLists = _cacheRepository.getAllLists();

    if (_connectivityService.isOnline) {
      try {
        // Fetch from network
        final remoteLists = await _remoteRepository.getUserLists();

        // Update cache
        await _cacheRepository.saveLists(remoteLists);
        await _cacheRepository.setLastSyncTime(DateTime.now());

        return remoteLists;
      } catch (e) {
        debugPrint('Failed to fetch remote lists: $e');
        // Return cached data on network error
        return cachedLists;
      }
    }

    return cachedLists;
  }

  /// Get a specific list by ID
  Future<ShoppingList> getListById(String listId) async {
    // Check cache first
    final cachedList = _cacheRepository.getListById(listId);

    if (_connectivityService.isOnline) {
      try {
        final remoteList = await _remoteRepository.getListById(listId);
        await _cacheRepository.saveList(remoteList);
        return remoteList;
      } catch (e) {
        debugPrint('Failed to fetch remote list: $e');
        if (cachedList != null) return cachedList;
        rethrow;
      }
    }

    if (cachedList != null) return cachedList;
    throw Exception('List not found in cache and device is offline');
  }

  /// Create a new shopping list
  Future<ShoppingList> createList({
    required String listName,
    required String storeName,
    String? listColour,
  }) async {
    if (_connectivityService.isOnline) {
      // Online: create remotely, then cache
      final list = await _remoteRepository.createList(
        listName: listName,
        storeName: storeName,
        listColour: listColour,
      );
      await _cacheRepository.saveList(list);
      return list;
    } else {
      // Offline: create locally with temp ID, queue for sync
      final tempId = const Uuid().v4();
      final now = DateTime.now();

      final list = ShoppingList(
        shoppingListId: tempId,
        userId: _cacheRepository.getCachedUserId() ?? '',
        createdAt: now,
        completedList: false,
        listName: listName,
        storeName: storeName,
        totalPrice: 0.0,
        listColour: listColour,
      );

      // Save to local cache
      await _cacheRepository.saveList(list);

      // Queue for sync
      await _cacheRepository.addToSyncQueue(
        SyncOperation(
          id: const Uuid().v4(),
          type: SyncOperationType.create,
          entityType: 'list',
          entityId: tempId,
          data: list.toJson(),
          createdAt: now,
        ),
      );

      return list;
    }
  }

  /// Update a shopping list
  Future<void> updateList(ShoppingList list) async {
    // Always update local cache first
    await _cacheRepository.saveList(list);

    if (_connectivityService.isOnline) {
      try {
        await _remoteRepository.updateList(list);
      } catch (e) {
        debugPrint('Failed to update remote list: $e');
        // Queue for sync on failure
        await _queueUpdate('list', list.shoppingListId, list.toJson());
      }
    } else {
      // Queue for sync when offline
      await _queueUpdate('list', list.shoppingListId, list.toJson());
    }
  }

  /// Delete a shopping list
  Future<void> deleteList(String listId) async {
    // Delete from local cache first
    await _cacheRepository.deleteList(listId);

    if (_connectivityService.isOnline) {
      try {
        await _remoteRepository.deleteList(listId);
      } catch (e) {
        debugPrint('Failed to delete remote list: $e');
        await _queueDelete('list', listId);
      }
    } else {
      await _queueDelete('list', listId);
    }
  }

  // ============ List Items ============

  /// Get items for a specific list
  Future<List<ListItem>> getListItems(String listId) async {
    // Check cache first
    final cachedItems = _cacheRepository.getItemsForList(listId);

    if (_connectivityService.isOnline) {
      try {
        final remoteItems = await _remoteRepository.getListItems(listId);
        await _cacheRepository.saveItems(remoteItems);
        return remoteItems;
      } catch (e) {
        debugPrint('Failed to fetch remote items: $e');
        return cachedItems;
      }
    }

    return cachedItems;
  }

  /// Add an item to a list
  Future<ListItem> addItem({
    required String listId,
    required String itemName,
    required double itemPrice,
    double itemQuantity = 1.0,
    String? itemNote,
    String? itemRetailer,
    double? itemSpecialPrice,
    Map<String, double>? multiBuyInfo,
  }) async {
    if (_connectivityService.isOnline) {
      // Online: create remotely, then cache
      final item = await _remoteRepository.addItem(
        listId: listId,
        itemName: itemName,
        itemPrice: itemPrice,
        itemQuantity: itemQuantity,
        itemNote: itemNote,
        itemRetailer: itemRetailer,
        itemSpecialPrice: itemSpecialPrice,
        multiBuyInfo: multiBuyInfo,
      );
      await _cacheRepository.saveItem(item);
      return item;
    } else {
      // Offline: create locally, queue for sync
      final tempId = const Uuid().v4();
      final now = DateTime.now();
      final totalPrice = itemQuantity * (itemSpecialPrice ?? itemPrice);

      final item = ListItem(
        itemId: tempId,
        shoppingListId: listId,
        completedItem: false,
        itemName: itemName,
        createdAt: now,
        itemQuantity: itemQuantity,
        itemPrice: itemPrice,
        itemNote: itemNote,
        itemRetailer: itemRetailer,
        itemSpecialPrice: itemSpecialPrice,
        itemTotalPrice: totalPrice,
      );

      await _cacheRepository.saveItem(item);

      await _cacheRepository.addToSyncQueue(
        SyncOperation(
          id: const Uuid().v4(),
          type: SyncOperationType.create,
          entityType: 'item',
          entityId: tempId,
          data: item.toJson(),
          createdAt: now,
        ),
      );

      // Update list total locally
      await _updateListTotalLocally(listId);

      return item;
    }
  }

  /// Update an item
  Future<void> updateItem(ListItem item) async {
    await _cacheRepository.saveItem(item);

    if (_connectivityService.isOnline) {
      try {
        await _remoteRepository.updateItem(item);
      } catch (e) {
        debugPrint('Failed to update remote item: $e');
        await _queueUpdate('item', item.itemId, item.toJson());
      }
    } else {
      await _queueUpdate('item', item.itemId, item.toJson());
    }

    await _updateListTotalLocally(item.shoppingListId);
  }

  /// Toggle item completion
  Future<void> toggleItemCompletion(ListItem item) async {
    final updatedItem = item.copyWith(completedItem: !item.completedItem);
    await updateItem(updatedItem);
  }

  /// Delete an item
  Future<void> deleteItem(String itemId, String listId) async {
    await _cacheRepository.deleteItem(itemId);

    if (_connectivityService.isOnline) {
      try {
        await _remoteRepository.deleteItem(itemId, listId);
      } catch (e) {
        debugPrint('Failed to delete remote item: $e');
        await _queueDelete('item', itemId);
      }
    } else {
      await _queueDelete('item', itemId);
    }

    await _updateListTotalLocally(listId);
  }

  // ============ Sync Helpers ============

  Future<void> _queueUpdate(
    String entityType,
    String entityId,
    Map<String, dynamic> data,
  ) async {
    await _cacheRepository.addToSyncQueue(
      SyncOperation(
        id: const Uuid().v4(),
        type: SyncOperationType.update,
        entityType: entityType,
        entityId: entityId,
        data: data,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _queueDelete(String entityType, String entityId) async {
    await _cacheRepository.addToSyncQueue(
      SyncOperation(
        id: const Uuid().v4(),
        type: SyncOperationType.delete,
        entityType: entityType,
        entityId: entityId,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _updateListTotalLocally(String listId) async {
    final items = _cacheRepository.getItemsForList(listId);
    final total = items.fold<double>(
      0,
      (sum, item) => sum + item.itemTotalPrice,
    );

    final list = _cacheRepository.getListById(listId);
    if (list != null) {
      await _cacheRepository.saveList(list.copyWith(totalPrice: total));
    }
  }

  // ============ Sync Status ============

  /// Check if there are pending changes to sync
  bool hasPendingChanges() => _cacheRepository.hasPendingSyncOperations();

  /// Get count of pending changes
  int getPendingChangesCount() => _cacheRepository.getPendingSyncCount();

  /// Get last sync time
  DateTime? getLastSyncTime() => _cacheRepository.getLastSyncTime();
}
