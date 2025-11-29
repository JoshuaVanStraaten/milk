import 'dart:async';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../models/list_item.dart';
import '../models/shopping_list.dart';

/// Enum for real-time event types
enum RealtimeEventType { insert, update, delete }

/// Model for real-time item events
class RealtimeItemEvent {
  final RealtimeEventType type;
  final ListItem item;
  final ListItem? oldItem; // For updates, contains the previous state

  RealtimeItemEvent({required this.type, required this.item, this.oldItem});
}

/// Model for real-time list events
class RealtimeListEvent {
  final RealtimeEventType type;
  final ShoppingList list;

  RealtimeListEvent({required this.type, required this.list});
}

/// Service for handling Supabase Realtime subscriptions
/// Manages subscriptions to shopping lists and items for real-time collaboration
class RealtimeService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final Logger _logger = Logger();

  // Active subscriptions
  RealtimeChannel? _itemsChannel;
  RealtimeChannel? _listChannel;

  // Stream controllers for broadcasting events
  final _itemEventsController = StreamController<RealtimeItemEvent>.broadcast();
  final _listEventsController = StreamController<RealtimeListEvent>.broadcast();

  // Current subscription state
  String? _currentListId;
  bool _isSubscribed = false;

  /// Stream of real-time item events
  Stream<RealtimeItemEvent> get itemEvents => _itemEventsController.stream;

  /// Stream of real-time list events
  Stream<RealtimeListEvent> get listEvents => _listEventsController.stream;

  /// Check if currently subscribed to a list
  bool get isSubscribed => _isSubscribed;

  /// Get the current subscribed list ID
  String? get currentListId => _currentListId;

  /// Subscribe to real-time updates for a specific shopping list
  /// This will receive updates for both list changes and item changes
  Future<void> subscribeToList(String listId) async {
    // Unsubscribe from any existing subscription first
    await unsubscribe();

    _currentListId = listId;
    _logger.i('🔔 Subscribing to real-time updates for list: $listId');

    try {
      // Subscribe to item changes for this list
      _itemsChannel = _supabase
          .channel('items-$listId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'Shopping_List_Item_Level',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'ShoppingList_ID',
              value: listId,
            ),
            callback: _handleItemChange,
          )
          .subscribe((status, error) {
            _logger.d('Items channel status: $status');
            if (error != null) {
              _logger.e('Items channel error: $error');
            }
          });

      // Subscribe to list changes (for total price updates, etc.)
      _listChannel = _supabase
          .channel('list-$listId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'Shopping_List_Overview',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'ShoppingList_ID',
              value: listId,
            ),
            callback: _handleListChange,
          )
          .subscribe((status, error) {
            _logger.d('List channel status: $status');
            if (error != null) {
              _logger.e('List channel error: $error');
            }
          });

      _isSubscribed = true;
      _logger.i('✅ Successfully subscribed to real-time updates');
    } catch (e, stackTrace) {
      _logger.e(
        'Error subscribing to real-time updates',
        error: e,
        stackTrace: stackTrace,
      );
      _isSubscribed = false;
    }
  }

  /// Handle incoming item changes from Supabase Realtime
  void _handleItemChange(PostgresChangePayload payload) {
    _logger.d('📨 Received item change: ${payload.eventType}');
    _logger.d('New data: ${payload.newRecord}');
    _logger.d('Old data: ${payload.oldRecord}');

    try {
      RealtimeEventType eventType;
      ListItem item;
      ListItem? oldItem;

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          eventType = RealtimeEventType.insert;
          item = ListItem.fromJson(payload.newRecord);
          break;

        case PostgresChangeEvent.update:
          eventType = RealtimeEventType.update;
          item = ListItem.fromJson(payload.newRecord);
          // Old record might not have all fields, so wrap in try-catch
          try {
            if (payload.oldRecord.isNotEmpty) {
              oldItem = ListItem.fromJson(payload.oldRecord);
            }
          } catch (e) {
            _logger.w('Could not parse old record: $e');
          }
          break;

        case PostgresChangeEvent.delete:
          eventType = RealtimeEventType.delete;
          // For deletes, we only have the old record
          item = ListItem.fromJson(payload.oldRecord);
          break;

        default:
          _logger.w('Unknown event type: ${payload.eventType}');
          return;
      }

      final event = RealtimeItemEvent(
        type: eventType,
        item: item,
        oldItem: oldItem,
      );

      _itemEventsController.add(event);
      _logger.i(
        '✅ Broadcasted item event: ${eventType.name} - ${item.itemName}',
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error processing item change',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle incoming list changes from Supabase Realtime
  void _handleListChange(PostgresChangePayload payload) {
    _logger.d('📨 Received list change: ${payload.eventType}');

    try {
      if (payload.eventType == PostgresChangeEvent.update) {
        final list = ShoppingList.fromJson(payload.newRecord);

        final event = RealtimeListEvent(
          type: RealtimeEventType.update,
          list: list,
        );

        _listEventsController.add(event);
        _logger.i('✅ Broadcasted list event: update - ${list.listName}');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error processing list change',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Unsubscribe from all real-time updates
  Future<void> unsubscribe() async {
    if (!_isSubscribed) return;

    _logger.i('🔕 Unsubscribing from real-time updates');

    try {
      if (_itemsChannel != null) {
        await _supabase.removeChannel(_itemsChannel!);
        _itemsChannel = null;
      }

      if (_listChannel != null) {
        await _supabase.removeChannel(_listChannel!);
        _listChannel = null;
      }

      _isSubscribed = false;
      _currentListId = null;
      _logger.i('✅ Successfully unsubscribed');
    } catch (e, stackTrace) {
      _logger.e(
        'Error unsubscribing from real-time updates',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    unsubscribe();
    _itemEventsController.close();
    _listEventsController.close();
    _logger.i('RealtimeService disposed');
  }
}
