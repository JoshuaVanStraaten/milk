import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/shopping_list.dart';
import '../../data/models/list_item.dart';
import '../../data/repositories/list_repository.dart';
import '../../data/services/realtime_service.dart';
import '../../data/local/cached_list_repository.dart';
import '../../data/local/hive_database.dart';
import '../../data/services/connectivity_service.dart';

const _uuid = Uuid();

/// Provider for ListRepository instance
final listRepositoryProvider = Provider<ListRepository>((ref) {
  return ListRepository();
});

/// Provider for CachedListRepository instance
final cachedListRepositoryProvider = Provider<CachedListRepository>((ref) {
  return CachedListRepository();
});

/// Provider for RealtimeService instance (singleton)
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for user's shopping lists (with caching)
final userListsProvider = FutureProvider<List<ShoppingList>>((ref) async {
  final repository = ref.watch(listRepositoryProvider);
  final cache = ref.watch(cachedListRepositoryProvider);
  // Use ref.read to avoid rebuilding when connectivity changes
  final connectivity = ref.read(connectivityServiceProvider);

  debugPrint(
    'userListsProvider: fetching lists (offline: ${connectivity.isOffline})',
  );

  // If offline, return cached data
  if (connectivity.isOffline) {
    final cached = cache.getAllLists();
    debugPrint(
      'userListsProvider: returning ${cached.length} cached lists (offline)',
    );
    return cached;
  }

  try {
    // Fetch from network
    final lists = await repository.getUserLists();
    debugPrint('userListsProvider: fetched ${lists.length} lists from network');
    // Cache the results
    await cache.saveLists(lists);
    return lists;
  } catch (e) {
    // On error, try to return cached data
    final cached = cache.getAllLists();
    if (cached.isNotEmpty) {
      debugPrint(
        'userListsProvider: network error, returning ${cached.length} cached lists',
      );
      return cached;
    }
    rethrow;
  }
});

/// Provider for a specific list by ID (with caching)
final listByIdProvider = FutureProvider.family<ShoppingList, String>((
  ref,
  listId,
) async {
  final repository = ref.watch(listRepositoryProvider);
  final cache = ref.watch(cachedListRepositoryProvider);
  // Use ref.read to avoid rebuilding when connectivity changes
  final connectivity = ref.read(connectivityServiceProvider);

  // Resolve the list ID in case it was synced (temp ID -> server ID)
  final resolvedId = cache.resolveListId(listId);
  final useResolvedId = resolvedId != listId;
  if (useResolvedId) {
    debugPrint('Resolved list ID: $listId -> $resolvedId');
  }

  // If offline, return cached data
  if (connectivity.isOffline) {
    final cached = cache.getListById(resolvedId);
    if (cached != null) {
      return cached;
    }
    throw Exception('List not available offline');
  }

  try {
    final list = await repository.getListById(resolvedId);
    // Cache the result
    await cache.saveList(list);
    return list;
  } catch (e) {
    // Check if this is a "not found" error (list was deleted)
    final errorString = e.toString();
    if (errorString.contains('PGRST116') || errorString.contains('0 rows')) {
      // List was deleted - this is expected, throw a clean error
      throw Exception('List not found');
    }

    // On other errors, try to return cached data
    final cached = cache.getListById(resolvedId);
    if (cached != null) {
      return cached;
    }
    rethrow;
  }
});

/// State class for real-time list items
class RealtimeListItemsState {
  final List<ListItem> items;
  final bool isLoading;
  final String? error;
  final bool isRealtime; // Indicates if real-time is active

  RealtimeListItemsState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.isRealtime = false,
  });

  RealtimeListItemsState copyWith({
    List<ListItem>? items,
    bool? isLoading,
    String? error,
    bool? isRealtime,
  }) {
    return RealtimeListItemsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isRealtime: isRealtime ?? this.isRealtime,
    );
  }
}

/// Notifier for real-time list items with optimistic updates
class RealtimeListItemsNotifier extends StateNotifier<RealtimeListItemsState> {
  final ListRepository _repository;
  final RealtimeService _realtimeService;
  final CachedListRepository _cache;
  final ConnectivityService _connectivity;
  final Ref _ref;
  final String listId;

  StreamSubscription? _itemSubscription;
  StreamSubscription? _listSubscription;

  RealtimeListItemsNotifier(
    this._repository,
    this._realtimeService,
    this._cache,
    this._connectivity,
    this._ref,
    this.listId,
  ) : super(RealtimeListItemsState(isLoading: true)) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Load initial items
    await loadItems();

    // Subscribe to real-time updates if online
    if (_connectivity.isOnline) {
      await _subscribeToRealtime();
    }
  }

  /// Load items from the database (or cache if offline)
  Future<void> loadItems() async {
    state = state.copyWith(isLoading: true, error: null);

    // Resolve the listId in case it was synced
    final resolvedListId = _cache.resolveListId(listId);

    try {
      List<ListItem> items;

      if (_connectivity.isOffline) {
        // Load from cache when offline
        items = _cache.getItemsForList(resolvedListId);
      } else {
        // Load from network
        items = await _repository.getListItems(resolvedListId);
        // Cache the items
        await _cache.saveItems(items);
      }

      state = state.copyWith(
        items: items,
        isLoading: false,
        isRealtime: _realtimeService.isSubscribed,
      );
    } catch (e) {
      // Try cache on error
      final cached = _cache.getItemsForList(resolvedListId);
      if (cached.isNotEmpty) {
        state = state.copyWith(
          items: cached,
          isLoading: false,
          error: 'Using cached data',
        );
      } else {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  /// Subscribe to real-time updates
  Future<void> _subscribeToRealtime() async {
    // Resolve the listId in case it was synced
    final resolvedListId = _cache.resolveListId(listId);

    try {
      await _realtimeService.subscribeToList(resolvedListId);

      // Listen for item events
      _itemSubscription = _realtimeService.itemEvents.listen((event) {
        _handleItemEvent(event);
      });

      state = state.copyWith(isRealtime: true);
    } catch (e) {
      // Realtime subscription failed - continue without it
      // This is non-fatal, app will work with cached data
      state = state.copyWith(isRealtime: false);
    }
  }

  /// Handle incoming real-time item events
  void _handleItemEvent(RealtimeItemEvent event) {
    final currentItems = List<ListItem>.from(state.items);

    switch (event.type) {
      case RealtimeEventType.insert:
        // Check if item already exists (prevent duplicates from optimistic updates)
        final existingIndex = currentItems.indexWhere(
          (item) => item.itemId == event.item.itemId,
        );
        if (existingIndex == -1) {
          currentItems.add(event.item);
        } else {
          // Update existing item with server data
          currentItems[existingIndex] = event.item;
        }
        // Update cache
        _cache.saveItem(event.item);
        break;

      case RealtimeEventType.update:
        final index = currentItems.indexWhere(
          (item) => item.itemId == event.item.itemId,
        );
        if (index != -1) {
          currentItems[index] = event.item;
        }
        // Update cache
        _cache.saveItem(event.item);
        break;

      case RealtimeEventType.delete:
        currentItems.removeWhere((item) => item.itemId == event.item.itemId);
        // Update cache
        _cache.deleteItem(event.item.itemId);
        break;
    }

    state = state.copyWith(items: currentItems);
  }

  /// Toggle item completion with optimistic update
  Future<void> toggleItemCompletion(ListItem item) async {
    // Optimistic update - toggle immediately in UI
    final currentItems = List<ListItem>.from(state.items);
    final index = currentItems.indexWhere((i) => i.itemId == item.itemId);

    if (index != -1) {
      final updatedItem = item.copyWith(completedItem: !item.completedItem);
      currentItems[index] = updatedItem;
      state = state.copyWith(items: currentItems);

      // Update cache immediately
      await _cache.saveItem(updatedItem);

      if (_connectivity.isOnline) {
        try {
          // Sync with server
          await _repository.toggleItemCompletion(item);
          // Real-time will update with server confirmation
        } catch (e) {
          // Revert on error
          currentItems[index] = item;
          state = state.copyWith(items: currentItems, error: e.toString());
          await _cache.saveItem(item);
        }
      } else {
        // Queue for sync when offline
        await _cache.addToSyncQueue(
          SyncOperation(
            id: _uuid.v4(),
            type: SyncOperationType.update,
            entityType: 'item',
            entityId: updatedItem.itemId,
            data: updatedItem.toJson(),
            createdAt: DateTime.now(),
          ),
        );
      }
    }
  }

  /// Add item with optimistic update
  Future<ListItem?> addItem({
    required String itemName,
    required double itemPrice,
    double itemQuantity = 1.0,
    String? itemNote,
    String? itemRetailer,
    double? itemSpecialPrice,
    Map<String, double>? multiBuyInfo,
  }) async {
    // Resolve the listId in case it was synced (temp ID -> server ID)
    final resolvedListId = _cache.resolveListId(listId);
    if (resolvedListId != listId) {
      debugPrint('addItem: Resolved list ID: $listId -> $resolvedListId');
    }

    if (_connectivity.isOnline) {
      try {
        final item = await _repository.addItem(
          listId: resolvedListId, // Use resolved ID
          itemName: itemName,
          itemPrice: itemPrice,
          itemQuantity: itemQuantity,
          itemNote: itemNote,
          itemRetailer: itemRetailer,
          itemSpecialPrice: itemSpecialPrice,
          multiBuyInfo: multiBuyInfo,
        );

        // Cache the new item
        await _cache.saveItem(item);

        // Add to current state immediately (don't wait for realtime)
        final currentItems = List<ListItem>.from(state.items);
        // Check if item already exists (from realtime)
        if (!currentItems.any((i) => i.itemId == item.itemId)) {
          currentItems.add(item);
          state = state.copyWith(items: currentItems);
        }

        // Invalidate list providers to refresh total
        _ref.invalidate(listByIdProvider(listId));
        _ref.invalidate(listByIdProvider(resolvedListId));
        _ref.invalidate(userListsProvider);

        return item;
      } catch (e) {
        state = state.copyWith(error: e.toString());
        return null;
      }
    } else {
      // Offline: create locally and queue for sync
      try {
        final tempId = _uuid.v4();
        final now = DateTime.now();

        // Calculate total price
        double totalPrice;
        if (multiBuyInfo != null && itemSpecialPrice != null) {
          final dealQuantity = multiBuyInfo['quantity']!.toInt();
          final dealPrice = multiBuyInfo['totalPrice']!;
          final completeSets = (itemQuantity / dealQuantity).floor();
          final leftoverItems = itemQuantity % dealQuantity;
          totalPrice = (completeSets * dealPrice) + (leftoverItems * itemPrice);
        } else if (itemSpecialPrice != null) {
          totalPrice = itemSpecialPrice * itemQuantity;
        } else {
          totalPrice = itemPrice * itemQuantity;
        }

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

        // Save to cache
        await _cache.saveItem(item);

        // Add to current state (optimistic)
        final currentItems = List<ListItem>.from(state.items);
        currentItems.add(item);
        state = state.copyWith(items: currentItems);

        // Update list total locally
        await _updateListTotalLocally();

        // Queue for sync
        await _cache.addToSyncQueue(
          SyncOperation(
            id: _uuid.v4(),
            type: SyncOperationType.create,
            entityType: 'item',
            entityId: tempId,
            data: item.toJson(),
            createdAt: now,
          ),
        );

        return item;
      } catch (e) {
        state = state.copyWith(error: e.toString());
        return null;
      }
    }
  }

  /// Update list total locally from cached items
  Future<void> _updateListTotalLocally() async {
    // Resolve the listId in case it was synced
    final resolvedListId = _cache.resolveListId(listId);

    final items = _cache.getItemsForList(resolvedListId);
    final total = items.fold<double>(
      0,
      (sum, item) => sum + item.itemTotalPrice,
    );

    final list = _cache.getListById(resolvedListId);
    if (list != null) {
      await _cache.saveList(list.copyWith(totalPrice: total));
      // Invalidate the list provider so UI updates
      _ref.invalidate(listByIdProvider(listId));
      _ref.invalidate(listByIdProvider(resolvedListId));
      _ref.invalidate(userListsProvider);
    }
  }

  /// Update item with optimistic update
  Future<bool> updateItem(ListItem updatedItem) async {
    // Optimistic update
    final currentItems = List<ListItem>.from(state.items);
    final index = currentItems.indexWhere(
      (i) => i.itemId == updatedItem.itemId,
    );
    final originalItem = index != -1 ? currentItems[index] : null;

    if (index != -1) {
      currentItems[index] = updatedItem;
      state = state.copyWith(items: currentItems);
      await _cache.saveItem(updatedItem);
    }

    if (_connectivity.isOnline) {
      try {
        await _repository.updateItem(updatedItem);
        return true;
      } catch (e) {
        // Revert on error
        if (originalItem != null && index != -1) {
          currentItems[index] = originalItem;
          state = state.copyWith(items: currentItems, error: e.toString());
          await _cache.saveItem(originalItem);
        }
        return false;
      }
    } else {
      // Queue for sync when offline
      await _cache.addToSyncQueue(
        SyncOperation(
          id: _uuid.v4(),
          type: SyncOperationType.update,
          entityType: 'item',
          entityId: updatedItem.itemId,
          data: updatedItem.toJson(),
          createdAt: DateTime.now(),
        ),
      );
    }

    return true;
  }

  /// Delete item with optimistic update
  Future<bool> deleteItem(String itemId) async {
    // Resolve the listId in case it was synced
    final resolvedListId = _cache.resolveListId(listId);
    if (resolvedListId != listId) {
      debugPrint('deleteItem: Resolved list ID: $listId -> $resolvedListId');
    }

    // Optimistic update - remove immediately
    final currentItems = List<ListItem>.from(state.items);
    final removedItem = currentItems.firstWhere(
      (item) => item.itemId == itemId,
      orElse: () => throw Exception('Item not found'),
    );
    final removedIndex = currentItems.indexOf(removedItem);
    currentItems.removeAt(removedIndex);
    state = state.copyWith(items: currentItems);
    await _cache.deleteItem(itemId);

    if (_connectivity.isOnline) {
      try {
        await _repository.deleteItem(itemId, resolvedListId);
        return true;
      } catch (e) {
        // Revert on error
        currentItems.insert(removedIndex, removedItem);
        state = state.copyWith(items: currentItems, error: e.toString());
        await _cache.saveItem(removedItem);
        return false;
      }
    } else {
      // Update list total locally
      await _updateListTotalLocally();

      // Queue for sync when offline
      await _cache.addToSyncQueue(
        SyncOperation(
          id: _uuid.v4(),
          type: SyncOperationType.delete,
          entityType: 'item',
          entityId: itemId,
          data: {'ShoppingList_ID': resolvedListId},
          createdAt: DateTime.now(),
        ),
      );
    }

    return true;
  }

  /// Refresh items from server
  Future<void> refresh() async {
    await loadItems();
  }

  @override
  void dispose() {
    _itemSubscription?.cancel();
    _listSubscription?.cancel();
    _realtimeService.unsubscribe();
    super.dispose();
  }
}

/// Provider for real-time list items (with caching)
final realtimeListItemsProvider =
    StateNotifierProvider.family<
      RealtimeListItemsNotifier,
      RealtimeListItemsState,
      String
    >((ref, listId) {
      final repository = ref.watch(listRepositoryProvider);
      final realtimeService = ref.watch(realtimeServiceProvider);
      final cache = ref.watch(cachedListRepositoryProvider);
      // Use ref.read to avoid rebuilding when connectivity changes
      final connectivity = ref.read(connectivityServiceProvider);

      // Resolve the list ID in case it was synced (temp ID -> server ID)
      final resolvedId = cache.resolveListId(listId);
      if (resolvedId != listId) {
        debugPrint(
          'RealtimeListItemsProvider: Resolved list ID: $listId -> $resolvedId',
        );
      }

      return RealtimeListItemsNotifier(
        repository,
        realtimeService,
        cache,
        connectivity,
        ref,
        resolvedId, // Use resolved ID
      );
    });

/// Legacy provider for items (non-realtime) - kept for backward compatibility
final listItemsProvider = FutureProvider.family<List<ListItem>, String>((
  ref,
  listId,
) async {
  final repository = ref.watch(listRepositoryProvider);
  final cache = ref.watch(cachedListRepositoryProvider);
  // Use ref.read to avoid rebuilding when connectivity changes
  final connectivity = ref.read(connectivityServiceProvider);

  if (connectivity.isOffline) {
    return cache.getItemsForList(listId);
  }

  try {
    final items = await repository.getListItems(listId);
    await cache.saveItems(items);
    return items;
  } catch (e) {
    final cached = cache.getItemsForList(listId);
    if (cached.isNotEmpty) return cached;
    rethrow;
  }
});

/// Notifier for list operations (create, update, delete)
class ListNotifier extends StateNotifier<AsyncValue<void>> {
  final ListRepository _listRepository;
  final CachedListRepository _cache;
  final ConnectivityService _connectivity;
  final Ref _ref;

  ListNotifier(this._listRepository, this._cache, this._connectivity, this._ref)
    : super(const AsyncValue.data(null));

  /// Create a new shopping list
  Future<ShoppingList?> createList({
    required String listName,
    required String storeName,
    String? listColour,
  }) async {
    state = const AsyncValue.loading();

    // Check if online
    if (_connectivity.isOnline) {
      try {
        final list = await _listRepository.createList(
          listName: listName,
          storeName: storeName,
          listColour: listColour,
        );

        state = const AsyncValue.data(null);

        // Cache the new list
        await _cache.saveList(list);

        // Refresh the lists
        _ref.invalidate(userListsProvider);

        return list;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        return null;
      }
    } else {
      // Offline: create locally and queue for sync
      try {
        final tempId = _uuid.v4();
        final now = DateTime.now();

        final list = ShoppingList(
          shoppingListId: tempId,
          userId: _cache.getCachedUserId() ?? '',
          createdAt: now,
          completedList: false,
          listName: listName,
          storeName: storeName,
          totalPrice: 0.0,
          listColour: listColour,
        );

        // Save to local cache
        await _cache.saveList(list);

        // Queue for sync
        await _cache.addToSyncQueue(
          SyncOperation(
            id: _uuid.v4(),
            type: SyncOperationType.create,
            entityType: 'list',
            entityId: tempId,
            data: list.toJson(),
            createdAt: now,
          ),
        );

        state = const AsyncValue.data(null);
        _ref.invalidate(userListsProvider);

        return list;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        return null;
      }
    }
  }

  /// Delete a shopping list
  Future<bool> deleteList(String listId) async {
    state = const AsyncValue.loading();

    // Resolve the listId in case it was synced
    final resolvedListId = _cache.resolveListId(listId);
    if (resolvedListId != listId) {
      debugPrint('deleteList: Resolved list ID: $listId -> $resolvedListId');
    }

    // Always delete from cache first (optimistic)
    await _cache.deleteList(resolvedListId);
    // Also try deleting the original ID in case mapping exists
    if (resolvedListId != listId) {
      await _cache.deleteList(listId);
    }

    if (_connectivity.isOnline) {
      try {
        await _listRepository.deleteList(resolvedListId);
        state = const AsyncValue.data(null);
        // Invalidate after successful delete
        _ref.invalidate(userListsProvider);
        _ref.invalidate(listByIdProvider(listId));
        _ref.invalidate(listByIdProvider(resolvedListId));
        return true;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        // Queue for sync on failure
        await _cache.addToSyncQueue(
          SyncOperation(
            id: _uuid.v4(),
            type: SyncOperationType.delete,
            entityType: 'list',
            entityId: resolvedListId,
            createdAt: DateTime.now(),
          ),
        );
        _ref.invalidate(userListsProvider);
        return false;
      }
    } else {
      // Queue for sync when offline
      await _cache.addToSyncQueue(
        SyncOperation(
          id: _uuid.v4(),
          type: SyncOperationType.delete,
          entityType: 'list',
          entityId: resolvedListId,
          createdAt: DateTime.now(),
        ),
      );
      state = const AsyncValue.data(null);
      // Invalidate after queueing
      _ref.invalidate(userListsProvider);
      _ref.invalidate(listByIdProvider(listId));
      _ref.invalidate(listByIdProvider(resolvedListId));
      return true;
    }
  }

  /// Update a shopping list
  Future<bool> updateList(ShoppingList list) async {
    state = const AsyncValue.loading();

    // Always update cache first (optimistic)
    await _cache.saveList(list);
    _ref.invalidate(userListsProvider);
    _ref.invalidate(listByIdProvider(list.shoppingListId));

    if (_connectivity.isOnline) {
      try {
        await _listRepository.updateList(list);
        state = const AsyncValue.data(null);
        return true;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        // Queue for sync on failure
        await _cache.addToSyncQueue(
          SyncOperation(
            id: _uuid.v4(),
            type: SyncOperationType.update,
            entityType: 'list',
            entityId: list.shoppingListId,
            data: list.toJson(),
            createdAt: DateTime.now(),
          ),
        );
        return false;
      }
    } else {
      // Queue for sync when offline
      await _cache.addToSyncQueue(
        SyncOperation(
          id: _uuid.v4(),
          type: SyncOperationType.update,
          entityType: 'list',
          entityId: list.shoppingListId,
          data: list.toJson(),
          createdAt: DateTime.now(),
        ),
      );
      state = const AsyncValue.data(null);
      return true;
    }
  }

  /// Share list with another user (requires online)
  Future<bool> shareList({
    required String listId,
    required String shareWithEmail,
  }) async {
    state = const AsyncValue.loading();

    try {
      await _listRepository.shareList(
        listId: listId,
        shareWithEmail: shareWithEmail,
      );

      state = const AsyncValue.data(null);

      return true;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return false;
    }
  }
}

/// Provider for ListNotifier
final listNotifierProvider =
    StateNotifierProvider<ListNotifier, AsyncValue<void>>((ref) {
      final repository = ref.watch(listRepositoryProvider);
      final cache = ref.watch(cachedListRepositoryProvider);
      final connectivity = ref.read(connectivityServiceProvider);
      return ListNotifier(repository, cache, connectivity, ref);
    });

/// Notifier for list item operations (legacy - non-realtime)
/// Kept for backward compatibility with product_list_screen add to list
class ListItemNotifier extends StateNotifier<AsyncValue<void>> {
  final ListRepository _listRepository;
  final CachedListRepository _cache;
  final ConnectivityService _connectivity;
  final Ref _ref;

  ListItemNotifier(
    this._listRepository,
    this._cache,
    this._connectivity,
    this._ref,
  ) : super(const AsyncValue.data(null));

  /// Add item to list
  Future<ListItem?> addItem({
    required String listId,
    required String itemName,
    required double itemPrice,
    double itemQuantity = 1.0,
    String? itemNote,
    String? itemRetailer,
    double? itemSpecialPrice,
    Map<String, double>? multiBuyInfo,
  }) async {
    state = const AsyncValue.loading();

    if (_connectivity.isOnline) {
      try {
        final item = await _listRepository.addItem(
          listId: listId,
          itemName: itemName,
          itemPrice: itemPrice,
          itemQuantity: itemQuantity,
          itemNote: itemNote,
          itemRetailer: itemRetailer,
          itemSpecialPrice: itemSpecialPrice,
          multiBuyInfo: multiBuyInfo,
        );

        state = const AsyncValue.data(null);

        // Cache the item
        await _cache.saveItem(item);

        // Refresh items and list
        _ref.invalidate(listItemsProvider(listId));
        _ref.invalidate(listByIdProvider(listId));
        _ref.invalidate(userListsProvider);

        return item;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        return null;
      }
    } else {
      // Offline: create locally and queue for sync
      try {
        final tempId = _uuid.v4();
        final now = DateTime.now();

        // Calculate total price
        double totalPrice;
        if (multiBuyInfo != null && itemSpecialPrice != null) {
          final dealQuantity = multiBuyInfo['quantity']!.toInt();
          final dealPrice = multiBuyInfo['totalPrice']!;
          final completeSets = (itemQuantity / dealQuantity).floor();
          final leftoverItems = itemQuantity % dealQuantity;
          totalPrice = (completeSets * dealPrice) + (leftoverItems * itemPrice);
        } else if (itemSpecialPrice != null) {
          totalPrice = itemSpecialPrice * itemQuantity;
        } else {
          totalPrice = itemPrice * itemQuantity;
        }

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

        // Save to cache
        await _cache.saveItem(item);

        // Queue for sync
        await _cache.addToSyncQueue(
          SyncOperation(
            id: _uuid.v4(),
            type: SyncOperationType.create,
            entityType: 'item',
            entityId: tempId,
            data: item.toJson(),
            createdAt: now,
          ),
        );

        // Update list total locally
        await _updateListTotalLocally(listId);

        state = const AsyncValue.data(null);

        // Refresh items and list
        _ref.invalidate(listItemsProvider(listId));
        _ref.invalidate(listByIdProvider(listId));
        _ref.invalidate(userListsProvider);

        return item;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        return null;
      }
    }
  }

  /// Update item
  Future<bool> updateItem(ListItem item) async {
    state = const AsyncValue.loading();

    // Always update cache first (optimistic)
    await _cache.saveItem(item);
    _ref.invalidate(listItemsProvider(item.shoppingListId));
    _ref.invalidate(listByIdProvider(item.shoppingListId));
    _ref.invalidate(userListsProvider);

    if (_connectivity.isOnline) {
      try {
        await _listRepository.updateItem(item);
        state = const AsyncValue.data(null);
        return true;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        // Queue for sync on failure
        await _queueItemUpdate(item);
        return false;
      }
    } else {
      await _queueItemUpdate(item);
      state = const AsyncValue.data(null);
      return true;
    }
  }

  /// Delete item
  Future<bool> deleteItem(String itemId, String listId) async {
    state = const AsyncValue.loading();

    // Get item data before deleting (for sync queue)
    // Always delete from cache first (optimistic)
    await _cache.deleteItem(itemId);
    await _updateListTotalLocally(listId);

    _ref.invalidate(listItemsProvider(listId));
    _ref.invalidate(listByIdProvider(listId));
    _ref.invalidate(userListsProvider);

    if (_connectivity.isOnline) {
      try {
        await _listRepository.deleteItem(itemId, listId);
        state = const AsyncValue.data(null);
        return true;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        await _queueItemDelete(itemId, listId);
        return false;
      }
    } else {
      await _queueItemDelete(itemId, listId);
      state = const AsyncValue.data(null);
      return true;
    }
  }

  /// Toggle item completion
  Future<bool> toggleItemCompletion(ListItem item) async {
    final updatedItem = item.copyWith(completedItem: !item.completedItem);

    // Update cache immediately (optimistic)
    await _cache.saveItem(updatedItem);
    _ref.invalidate(listItemsProvider(item.shoppingListId));

    if (_connectivity.isOnline) {
      try {
        await _listRepository.toggleItemCompletion(item);
        return true;
      } catch (e, stackTrace) {
        state = AsyncValue.error(e, stackTrace);
        await _queueItemUpdate(updatedItem);
        return false;
      }
    } else {
      await _queueItemUpdate(updatedItem);
      return true;
    }
  }

  Future<void> _queueItemUpdate(ListItem item) async {
    await _cache.addToSyncQueue(
      SyncOperation(
        id: _uuid.v4(),
        type: SyncOperationType.update,
        entityType: 'item',
        entityId: item.itemId,
        data: item.toJson(),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _queueItemDelete(String itemId, String listId) async {
    await _cache.addToSyncQueue(
      SyncOperation(
        id: _uuid.v4(),
        type: SyncOperationType.delete,
        entityType: 'item',
        entityId: itemId,
        data: {'ShoppingList_ID': listId},
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _updateListTotalLocally(String listId) async {
    final items = _cache.getItemsForList(listId);
    final total = items.fold<double>(
      0,
      (sum, item) => sum + item.itemTotalPrice,
    );

    final list = _cache.getListById(listId);
    if (list != null) {
      await _cache.saveList(list.copyWith(totalPrice: total));
    }
  }
}

/// Provider for ListItemNotifier
final listItemNotifierProvider =
    StateNotifierProvider<ListItemNotifier, AsyncValue<void>>((ref) {
      final repository = ref.watch(listRepositoryProvider);
      final cache = ref.watch(cachedListRepositoryProvider);
      final connectivity = ref.read(connectivityServiceProvider);
      return ListItemNotifier(repository, cache, connectivity, ref);
    });
