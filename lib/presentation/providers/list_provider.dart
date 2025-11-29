import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/shopping_list.dart';
import '../../data/models/list_item.dart';
import '../../data/repositories/list_repository.dart';
import '../../data/services/realtime_service.dart';

/// Provider for ListRepository instance
final listRepositoryProvider = Provider<ListRepository>((ref) {
  return ListRepository();
});

/// Provider for RealtimeService instance (singleton)
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for user's shopping lists
final userListsProvider = FutureProvider<List<ShoppingList>>((ref) async {
  final repository = ref.watch(listRepositoryProvider);
  return repository.getUserLists();
});

/// Provider for a specific list by ID
final listByIdProvider = FutureProvider.family<ShoppingList, String>((
  ref,
  listId,
) async {
  final repository = ref.watch(listRepositoryProvider);
  return repository.getListById(listId);
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
  final String listId;

  StreamSubscription? _itemSubscription;
  StreamSubscription? _listSubscription;

  RealtimeListItemsNotifier(
    this._repository,
    this._realtimeService,
    this.listId,
  ) : super(RealtimeListItemsState(isLoading: true)) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Load initial items
    await loadItems();

    // Subscribe to real-time updates
    await _subscribeToRealtime();
  }

  /// Load items from the database
  Future<void> loadItems() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final items = await _repository.getListItems(listId);
      state = state.copyWith(
        items: items,
        isLoading: false,
        isRealtime: _realtimeService.isSubscribed,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Subscribe to real-time updates
  Future<void> _subscribeToRealtime() async {
    await _realtimeService.subscribeToList(listId);

    // Listen for item events
    _itemSubscription = _realtimeService.itemEvents.listen((event) {
      _handleItemEvent(event);
    });

    state = state.copyWith(isRealtime: true);
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
        break;

      case RealtimeEventType.update:
        final index = currentItems.indexWhere(
          (item) => item.itemId == event.item.itemId,
        );
        if (index != -1) {
          currentItems[index] = event.item;
        }
        break;

      case RealtimeEventType.delete:
        currentItems.removeWhere((item) => item.itemId == event.item.itemId);
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

      try {
        // Sync with server
        await _repository.toggleItemCompletion(item);
        // Real-time will update with server confirmation
      } catch (e) {
        // Revert on error
        currentItems[index] = item;
        state = state.copyWith(items: currentItems, error: e.toString());
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
    try {
      final item = await _repository.addItem(
        listId: listId,
        itemName: itemName,
        itemPrice: itemPrice,
        itemQuantity: itemQuantity,
        itemNote: itemNote,
        itemRetailer: itemRetailer,
        itemSpecialPrice: itemSpecialPrice,
        multiBuyInfo: multiBuyInfo,
      );

      // Real-time will handle adding to the list
      return item;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
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
    }

    try {
      await _repository.updateItem(updatedItem);
      return true;
    } catch (e) {
      // Revert on error
      if (originalItem != null && index != -1) {
        currentItems[index] = originalItem;
        state = state.copyWith(items: currentItems, error: e.toString());
      }
      return false;
    }
  }

  /// Delete item with optimistic update
  Future<bool> deleteItem(String itemId) async {
    // Optimistic update - remove immediately
    final currentItems = List<ListItem>.from(state.items);
    final removedItem = currentItems.firstWhere(
      (item) => item.itemId == itemId,
      orElse: () => throw Exception('Item not found'),
    );
    final removedIndex = currentItems.indexOf(removedItem);
    currentItems.removeAt(removedIndex);
    state = state.copyWith(items: currentItems);

    try {
      await _repository.deleteItem(itemId, listId);
      return true;
    } catch (e) {
      // Revert on error
      currentItems.insert(removedIndex, removedItem);
      state = state.copyWith(items: currentItems, error: e.toString());
      return false;
    }
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

/// Provider for real-time list items
final realtimeListItemsProvider =
    StateNotifierProvider.family<
      RealtimeListItemsNotifier,
      RealtimeListItemsState,
      String
    >((ref, listId) {
      final repository = ref.watch(listRepositoryProvider);
      final realtimeService = ref.watch(realtimeServiceProvider);
      return RealtimeListItemsNotifier(repository, realtimeService, listId);
    });

/// Legacy provider for items (non-realtime) - kept for backward compatibility
final listItemsProvider = FutureProvider.family<List<ListItem>, String>((
  ref,
  listId,
) async {
  final repository = ref.watch(listRepositoryProvider);
  return repository.getListItems(listId);
});

/// Notifier for list operations (create, update, delete)
class ListNotifier extends StateNotifier<AsyncValue<void>> {
  final ListRepository _listRepository;
  final Ref _ref;

  ListNotifier(this._listRepository, this._ref)
    : super(const AsyncValue.data(null));

  /// Create a new shopping list
  Future<ShoppingList?> createList({
    required String listName,
    required String storeName,
    String? listColour,
  }) async {
    state = const AsyncValue.loading();

    try {
      final list = await _listRepository.createList(
        listName: listName,
        storeName: storeName,
        listColour: listColour,
      );

      state = const AsyncValue.data(null);

      // Refresh the lists
      _ref.invalidate(userListsProvider);

      return list;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return null;
    }
  }

  /// Delete a shopping list
  Future<bool> deleteList(String listId) async {
    state = const AsyncValue.loading();

    try {
      await _listRepository.deleteList(listId);
      state = const AsyncValue.data(null);

      // Refresh the lists
      _ref.invalidate(userListsProvider);

      return true;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return false;
    }
  }

  /// Update a shopping list
  Future<bool> updateList(ShoppingList list) async {
    state = const AsyncValue.loading();

    try {
      await _listRepository.updateList(list);
      state = const AsyncValue.data(null);

      // Refresh the lists
      _ref.invalidate(userListsProvider);
      _ref.invalidate(listByIdProvider(list.shoppingListId));

      return true;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return false;
    }
  }

  /// Share list with another user
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
      return ListNotifier(repository, ref);
    });

/// Notifier for list item operations (legacy - non-realtime)
/// Kept for backward compatibility with product_list_screen add to list
class ListItemNotifier extends StateNotifier<AsyncValue<void>> {
  final ListRepository _listRepository;
  final Ref _ref;

  ListItemNotifier(this._listRepository, this._ref)
    : super(const AsyncValue.data(null));

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

  /// Update item
  Future<bool> updateItem(ListItem item) async {
    state = const AsyncValue.loading();

    try {
      await _listRepository.updateItem(item);
      state = const AsyncValue.data(null);

      // Refresh items and list
      _ref.invalidate(listItemsProvider(item.shoppingListId));
      _ref.invalidate(listByIdProvider(item.shoppingListId));
      _ref.invalidate(userListsProvider);

      return true;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return false;
    }
  }

  /// Delete item
  Future<bool> deleteItem(String itemId, String listId) async {
    state = const AsyncValue.loading();

    try {
      await _listRepository.deleteItem(itemId, listId);
      state = const AsyncValue.data(null);

      // Refresh items and list
      _ref.invalidate(listItemsProvider(listId));
      _ref.invalidate(listByIdProvider(listId));
      _ref.invalidate(userListsProvider);

      return true;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return false;
    }
  }

  /// Toggle item completion
  Future<bool> toggleItemCompletion(ListItem item) async {
    try {
      await _listRepository.toggleItemCompletion(item);

      // Refresh items
      _ref.invalidate(listItemsProvider(item.shoppingListId));

      return true;
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
      return false;
    }
  }
}

/// Provider for ListItemNotifier
final listItemNotifierProvider =
    StateNotifierProvider<ListItemNotifier, AsyncValue<void>>((ref) {
      final repository = ref.watch(listRepositoryProvider);
      return ListItemNotifier(repository, ref);
    });
