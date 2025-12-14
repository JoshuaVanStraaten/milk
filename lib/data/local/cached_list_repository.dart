import 'package:flutter/foundation.dart';
import '../models/shopping_list.dart';
import '../models/list_item.dart';
import 'hive_database.dart';

/// Repository for local cached data using Hive
class CachedListRepository {
  // ============ Shopping Lists ============

  /// Get all cached shopping lists
  List<ShoppingList> getAllLists() {
    return HiveDatabase.shoppingListsBox.values.toList();
  }

  /// Get cached shopping lists for a user
  List<ShoppingList> getListsForUser(String userId) {
    return HiveDatabase.shoppingListsBox.values
        .where((list) => list.userId == userId)
        .toList();
  }

  /// Get a specific list by ID
  ShoppingList? getListById(String listId) {
    return HiveDatabase.shoppingListsBox.get(listId);
  }

  /// Save a shopping list to cache
  Future<void> saveList(ShoppingList list) async {
    await HiveDatabase.shoppingListsBox.put(list.shoppingListId, list);
    debugPrint('Cached list: ${list.listName}');
  }

  /// Save multiple shopping lists to cache
  Future<void> saveLists(List<ShoppingList> lists) async {
    final Map<String, ShoppingList> entries = {
      for (final list in lists) list.shoppingListId: list,
    };
    await HiveDatabase.shoppingListsBox.putAll(entries);
    debugPrint('Cached ${lists.length} lists');
  }

  /// Delete a list from cache
  Future<void> deleteList(String listId) async {
    await HiveDatabase.shoppingListsBox.delete(listId);
    // Also delete all items for this list
    await deleteItemsForList(listId);
    debugPrint('Deleted cached list: $listId');
  }

  /// Clear all cached lists
  Future<void> clearLists() async {
    await HiveDatabase.shoppingListsBox.clear();
  }

  // ============ List Items ============

  /// Get all items for a specific list
  List<ListItem> getItemsForList(String listId) {
    return HiveDatabase.listItemsBox.values
        .where((item) => item.shoppingListId == listId)
        .toList();
  }

  /// Get a specific item by ID
  ListItem? getItemById(String itemId) {
    return HiveDatabase.listItemsBox.get(itemId);
  }

  /// Save a list item to cache
  Future<void> saveItem(ListItem item) async {
    await HiveDatabase.listItemsBox.put(item.itemId, item);
    debugPrint('Cached item: ${item.itemName}');
  }

  /// Save multiple list items to cache
  Future<void> saveItems(List<ListItem> items) async {
    final Map<String, ListItem> entries = {
      for (final item in items) item.itemId: item,
    };
    await HiveDatabase.listItemsBox.putAll(entries);
    debugPrint('Cached ${items.length} items');
  }

  /// Delete an item from cache
  Future<void> deleteItem(String itemId) async {
    await HiveDatabase.listItemsBox.delete(itemId);
    debugPrint('Deleted cached item: $itemId');
  }

  /// Delete all items for a specific list
  Future<void> deleteItemsForList(String listId) async {
    final itemsToDelete = HiveDatabase.listItemsBox.values
        .where((item) => item.shoppingListId == listId)
        .map((item) => item.itemId)
        .toList();

    for (final itemId in itemsToDelete) {
      await HiveDatabase.listItemsBox.delete(itemId);
    }
    debugPrint(
      'Deleted ${itemsToDelete.length} cached items for list: $listId',
    );
  }

  /// Clear all cached items
  Future<void> clearItems() async {
    await HiveDatabase.listItemsBox.clear();
  }

  // ============ Sync Queue ============

  /// Add an operation to the sync queue
  Future<void> addToSyncQueue(SyncOperation operation) async {
    await HiveDatabase.syncQueueBox.put(operation.id, operation);
    debugPrint(
      'Added to sync queue: ${operation.type} ${operation.entityType}',
    );
  }

  /// Get all pending sync operations
  List<SyncOperation> getPendingSyncOperations() {
    return HiveDatabase.syncQueueBox.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Remove an operation from the sync queue
  Future<void> removeFromSyncQueue(String operationId) async {
    await HiveDatabase.syncQueueBox.delete(operationId);
  }

  /// Update retry count for a sync operation
  Future<void> incrementRetryCount(String operationId) async {
    final operation = HiveDatabase.syncQueueBox.get(operationId);
    if (operation != null) {
      await HiveDatabase.syncQueueBox.put(
        operationId,
        operation.copyWith(retryCount: operation.retryCount + 1),
      );
    }
  }

  /// Clear the sync queue
  Future<void> clearSyncQueue() async {
    await HiveDatabase.syncQueueBox.clear();
  }

  /// Check if there are pending sync operations
  bool hasPendingSyncOperations() {
    return HiveDatabase.syncQueueBox.isNotEmpty;
  }

  /// Get count of pending sync operations
  int getPendingSyncCount() {
    return HiveDatabase.syncQueueBox.length;
  }

  // ============ Metadata ============

  /// Get last sync timestamp
  DateTime? getLastSyncTime() {
    final timestamp = HiveDatabase.metadataBox.get('lastSyncTime');
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp as int)
        : null;
  }

  /// Set last sync timestamp
  Future<void> setLastSyncTime(DateTime time) async {
    await HiveDatabase.metadataBox.put(
      'lastSyncTime',
      time.millisecondsSinceEpoch,
    );
  }

  /// Get cached user ID
  String? getCachedUserId() {
    return HiveDatabase.metadataBox.get('userId') as String?;
  }

  /// Set cached user ID
  Future<void> setCachedUserId(String userId) async {
    await HiveDatabase.metadataBox.put('userId', userId);
  }

  // ============ List ID Mapping (for synced lists) ============

  /// Store mapping from temp ID to server ID
  Future<void> storeListIdMapping(String tempId, String serverId) async {
    await HiveDatabase.metadataBox.put('listIdMap_$tempId', serverId);
    debugPrint('Stored list ID mapping: $tempId -> $serverId');
  }

  /// Get the server ID for a temp ID (if it was synced)
  String? getMappedListId(String tempId) {
    return HiveDatabase.metadataBox.get('listIdMap_$tempId') as String?;
  }

  /// Resolve a list ID - returns the mapped server ID if exists, otherwise the original
  String resolveListId(String listId) {
    return getMappedListId(listId) ?? listId;
  }

  /// Clear all cached data
  Future<void> clearAll() async {
    await HiveDatabase.clearAll();
  }
}
