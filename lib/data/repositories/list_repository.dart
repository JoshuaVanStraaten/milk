import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/supabase_config.dart';
import '../models/shopping_list.dart';
import '../models/list_item.dart';

/// Repository for shopping list operations
/// Handles all list and item CRUD operations
class ListRepository {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  /// Create a new shopping list
  Future<ShoppingList> createList({
    required String listName,
    required String storeName,
    String? listColour,
  }) async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      _logger.i('Creating shopping list: $listName');

      final listId = _uuid.v4();
      final chatId = _uuid.v4();

      final list = ShoppingList(
        shoppingListId: listId,
        userId: userId,
        createdAt: DateTime.now(),
        listName: listName,
        storeName: storeName,
        listColour: listColour,
        totalPrice: 0.0,
        completedList: false,
        chatId: chatId,
      );

      await _supabase.from('Shopping_List_Overview').insert(list.toJson());

      _logger.i('✅ Shopping list created: ${list.shoppingListId}');

      return list;
    } catch (e, stackTrace) {
      _logger.e(
        'Error creating shopping list',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to create shopping list: $e');
    }
  }

  /// Get all shopping lists for current user (owned + shared)
  Future<List<ShoppingList>> getUserLists() async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      _logger.d('Fetching lists for user: $userId');

      // Get owned lists
      final ownedResponse = await _supabase
          .from('Shopping_List_Overview')
          .select()
          .eq('id', userId)
          .order('created_at', ascending: false);

      final ownedLists = (ownedResponse as List)
          .map((json) => ShoppingList.fromJson(json))
          .toList();

      // Get shared lists
      final sharedResponse = await _supabase
          .from('Shared_lists')
          .select('ShoppingList_ID')
          .eq('Shared_With', userId);

      final sharedListIds = (sharedResponse as List)
          .map((json) => json['ShoppingList_ID'] as String)
          .toList();

      // Fetch full details for shared lists
      final List<ShoppingList> sharedLists = [];
      for (final listId in sharedListIds) {
        try {
          final list = await getListById(listId);
          sharedLists.add(list);
        } catch (e) {
          _logger.w('Could not fetch shared list $listId: $e');
        }
      }

      // Combine and sort by created_at
      final allLists = [...ownedLists, ...sharedLists];
      allLists.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _logger.i(
        '✅ Fetched ${allLists.length} lists (${ownedLists.length} owned, ${sharedLists.length} shared)',
      );

      return allLists;
    } catch (e, stackTrace) {
      _logger.e('Error fetching user lists', error: e, stackTrace: stackTrace);
      throw Exception('Failed to fetch lists: $e');
    }
  }

  /// Get a specific list by ID
  Future<ShoppingList> getListById(String listId) async {
    try {
      _logger.d('Fetching list: $listId');

      final response = await _supabase
          .from('Shopping_List_Overview')
          .select()
          .eq('ShoppingList_ID', listId)
          .single();

      final list = ShoppingList.fromJson(response);

      _logger.i('✅ Fetched list: ${list.listName}');

      return list;
    } catch (e, stackTrace) {
      _logger.e('Error fetching list by ID', error: e, stackTrace: stackTrace);
      throw Exception('Failed to fetch list: $e');
    }
  }

  /// Update a shopping list
  Future<void> updateList(ShoppingList list) async {
    try {
      _logger.i('Updating list: ${list.shoppingListId}');

      await _supabase
          .from('Shopping_List_Overview')
          .update(list.toJson())
          .eq('ShoppingList_ID', list.shoppingListId);

      _logger.i('✅ List updated');
    } catch (e, stackTrace) {
      _logger.e('Error updating list', error: e, stackTrace: stackTrace);
      throw Exception('Failed to update list: $e');
    }
  }

  /// Delete a shopping list and all its items
  Future<void> deleteList(String listId) async {
    try {
      _logger.i('Deleting list: $listId');

      // Delete all items first
      await _supabase
          .from('Shopping_List_Item_Level')
          .delete()
          .eq('ShoppingList_ID', listId);

      // Delete shared list entries
      await _supabase
          .from('Shared_lists')
          .delete()
          .eq('ShoppingList_ID', listId);

      // Delete the list
      await _supabase
          .from('Shopping_List_Overview')
          .delete()
          .eq('ShoppingList_ID', listId);

      _logger.i('✅ List deleted');
    } catch (e, stackTrace) {
      _logger.e('Error deleting list', error: e, stackTrace: stackTrace);
      throw Exception('Failed to delete list: $e');
    }
  }

  /// Get all items for a specific list
  Future<List<ListItem>> getListItems(String listId) async {
    try {
      _logger.d('Fetching items for list: $listId');

      final response = await _supabase
          .from('Shopping_List_Item_Level')
          .select()
          .eq('ShoppingList_ID', listId)
          .order('created_at', ascending: true);

      final items = (response as List)
          .map((json) => ListItem.fromJson(json))
          .toList();

      _logger.i('✅ Fetched ${items.length} items');

      return items;
    } catch (e, stackTrace) {
      _logger.e('Error fetching list items', error: e, stackTrace: stackTrace);
      throw Exception('Failed to fetch items: $e');
    }
  }

  /// Add item to list
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
    try {
      _logger.i('Adding item to list: $itemName');

      // Calculate total price based on multi-buy logic if applicable
      double totalPrice;

      if (multiBuyInfo != null && itemSpecialPrice != null) {
        // Multi-buy promo: calculate sets + leftovers
        final dealQuantity = multiBuyInfo['quantity']!.toInt();
        final dealPrice = multiBuyInfo['totalPrice']!;

        final completeSets = (itemQuantity / dealQuantity).floor();
        final leftoverItems = itemQuantity % dealQuantity;

        totalPrice = (completeSets * dealPrice) + (leftoverItems * itemPrice);

        _logger.d(
          'Multi-buy calculation: $completeSets sets × R$dealPrice + $leftoverItems × R$itemPrice = R$totalPrice',
        );
      } else if (itemSpecialPrice != null) {
        // Simple promo: use special price for all items
        totalPrice = itemSpecialPrice * itemQuantity;
      } else {
        // No promo: use regular price
        totalPrice = itemPrice * itemQuantity;
      }

      final item = ListItem(
        itemId: _uuid.v4(),
        shoppingListId: listId,
        itemName: itemName,
        createdAt: DateTime.now(),
        itemQuantity: itemQuantity,
        itemPrice: itemPrice,
        itemNote: itemNote,
        itemRetailer: itemRetailer,
        itemSpecialPrice: itemSpecialPrice,
        itemTotalPrice: totalPrice,
        completedItem: false,
      );

      await _supabase.from('Shopping_List_Item_Level').insert(item.toJson());

      // Update list total
      await _updateListTotal(listId);

      _logger.i('✅ Item added: ${item.itemId}');

      return item;
    } catch (e, stackTrace) {
      _logger.e('Error adding item', error: e, stackTrace: stackTrace);
      throw Exception('Failed to add item: $e');
    }
  }

  /// Update an item
  Future<void> updateItem(ListItem item) async {
    try {
      _logger.i('Updating item: ${item.itemId}');

      await _supabase
          .from('Shopping_List_Item_Level')
          .update(item.toJson())
          .eq('Item_ID', item.itemId);

      // Update list total
      await _updateListTotal(item.shoppingListId);

      _logger.i('✅ Item updated');
    } catch (e, stackTrace) {
      _logger.e('Error updating item', error: e, stackTrace: stackTrace);
      throw Exception('Failed to update item: $e');
    }
  }

  /// Delete an item
  Future<void> deleteItem(String itemId, String listId) async {
    try {
      _logger.i('Deleting item: $itemId');

      await _supabase
          .from('Shopping_List_Item_Level')
          .delete()
          .eq('Item_ID', itemId);

      // Update list total
      await _updateListTotal(listId);

      _logger.i('✅ Item deleted');
    } catch (e, stackTrace) {
      _logger.e('Error deleting item', error: e, stackTrace: stackTrace);
      throw Exception('Failed to delete item: $e');
    }
  }

  /// Toggle item completion status
  Future<void> toggleItemCompletion(ListItem item) async {
    try {
      _logger.d('Toggling item completion: ${item.itemId}');

      await _supabase
          .from('Shopping_List_Item_Level')
          .update({'Completed_Item': !item.completedItem})
          .eq('Item_ID', item.itemId);

      _logger.d('✅ Item completion toggled');
    } catch (e, stackTrace) {
      _logger.e(
        'Error toggling item completion',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to toggle item: $e');
    }
  }

  /// Private method to update list total
  Future<void> _updateListTotal(String listId) async {
    try {
      // Get all items for the list
      final items = await getListItems(listId);

      // Calculate total
      final total = items.fold<double>(
        0.0,
        (sum, item) => sum + item.itemTotalPrice,
      );

      // Update list
      await _supabase
          .from('Shopping_List_Overview')
          .update({'total_price': total})
          .eq('ShoppingList_ID', listId);

      _logger.d('✅ List total updated: R$total');
    } catch (e, stackTrace) {
      _logger.e('Error updating list total', error: e, stackTrace: stackTrace);
    }
  }

  /// Share list with another user by email
  Future<void> shareList({
    required String listId,
    required String shareWithEmail,
  }) async {
    try {
      final currentUserId = SupabaseConfig.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Normalize email to lowercase and trim whitespace
      final normalizedEmail = shareWithEmail.toLowerCase().trim();

      _logger.i('Sharing list $listId with $normalizedEmail');

      // Get the list details
      final list = await getListById(listId);

      // Find user by email - using ilike for case-insensitive matching
      _logger.d('Looking up user with email: $normalizedEmail');

      final userResponse = await _supabase
          .from('user_profiles')
          .select('id, email_address')
          .ilike('email_address', normalizedEmail)
          .maybeSingle();

      _logger.d('User lookup response: $userResponse');

      if (userResponse == null) {
        // Let's also try to see what users exist (for debugging)
        _logger.w('User not found. Attempting debug query...');

        // Try a broader search to see if any users exist
        final allUsersResponse = await _supabase
            .from('user_profiles')
            .select('id, email_address')
            .limit(5);

        _logger.d('Sample users in database: $allUsersResponse');

        throw Exception(
          'No user found with email: $normalizedEmail. '
          'Make sure the user has signed up and their profile exists.',
        );
      }

      final sharedWithUserId = userResponse['id'] as String;
      final foundEmail = userResponse['email_address'] as String;

      _logger.i('Found user: $sharedWithUserId (email: $foundEmail)');

      // Check if trying to share with yourself
      if (sharedWithUserId == currentUserId) {
        throw Exception('You cannot share a list with yourself');
      }

      // Check if already shared
      final existingShare = await _supabase
          .from('Shared_lists')
          .select()
          .eq('ShoppingList_ID', listId)
          .eq('Shared_With', sharedWithUserId)
          .maybeSingle();

      if (existingShare != null) {
        throw Exception('List is already shared with this user');
      }

      // Insert into Shared_lists
      final shareId = _uuid.v4();

      await _supabase.from('Shared_lists').insert({
        'id': shareId,
        'ShoppingList_ID': listId,
        'Shared_With': sharedWithUserId,
        'list_name': list.listName,
        'store_name': list.storeName,
        'total_price': list.totalPrice,
        'Shared_Mail': foundEmail,
        'OwnerID': currentUserId,
        'ChatID': list.chatId ?? _uuid.v4(),
      });

      _logger.i('✅ List shared successfully with $foundEmail');
    } catch (e, stackTrace) {
      _logger.e('Error sharing list', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get all users who have access to a list
  Future<List<String>> getSharedUsers(String listId) async {
    try {
      final response = await _supabase
          .from('Shared_lists')
          .select('Shared_Mail')
          .eq('ShoppingList_ID', listId);

      return (response as List)
          .map((json) => json['Shared_Mail'] as String)
          .toList();
    } catch (e, stackTrace) {
      _logger.e('Error getting shared users', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Check if current user owns the list
  Future<bool> isListOwner(String listId) async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from('Shopping_List_Overview')
          .select('id')
          .eq('ShoppingList_ID', listId)
          .eq('id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      _logger.e('Error checking list ownership: $e');
      return false;
    }
  }

  /// Remove sharing for a user
  Future<void> unshareList({
    required String listId,
    required String sharedWithEmail,
  }) async {
    try {
      _logger.i('Removing share for $sharedWithEmail from list $listId');

      await _supabase
          .from('Shared_lists')
          .delete()
          .eq('ShoppingList_ID', listId)
          .eq('Shared_Mail', sharedWithEmail);

      _logger.i('✅ Share removed successfully');
    } catch (e, stackTrace) {
      _logger.e('Error removing share', error: e, stackTrace: stackTrace);
      throw Exception('Failed to remove share: $e');
    }
  }

  /// Get current authenticated user
  User? getCurrentUser() {
    return SupabaseConfig.currentUser;
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return getCurrentUser() != null;
  }
}
