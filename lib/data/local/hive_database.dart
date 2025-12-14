import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/shopping_list.dart';
import '../models/list_item.dart';
import 'adapters/shopping_list_adapter.dart';
import 'adapters/list_item_adapter.dart';

/// Box names for Hive storage
class HiveBoxes {
  static const String shoppingLists = 'shopping_lists';
  static const String listItems = 'list_items';
  static const String syncQueue = 'sync_queue';
  static const String metadata = 'metadata';
}

/// Hive database initialization and management
class HiveDatabase {
  static bool _isInitialized = false;

  /// Initialize Hive and register all adapters
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize Hive for Flutter
    await Hive.initFlutter();

    // Register type adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ShoppingListAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ListItemAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(SyncOperationAdapter());
    }

    // Open boxes
    await Future.wait([
      Hive.openBox<ShoppingList>(HiveBoxes.shoppingLists),
      Hive.openBox<ListItem>(HiveBoxes.listItems),
      Hive.openBox<SyncOperation>(HiveBoxes.syncQueue),
      Hive.openBox(HiveBoxes.metadata),
    ]);

    _isInitialized = true;
    debugPrint('Hive database initialized');
  }

  /// Get the shopping lists box
  static Box<ShoppingList> get shoppingListsBox =>
      Hive.box<ShoppingList>(HiveBoxes.shoppingLists);

  /// Get the list items box
  static Box<ListItem> get listItemsBox =>
      Hive.box<ListItem>(HiveBoxes.listItems);

  /// Get the sync queue box
  static Box<SyncOperation> get syncQueueBox =>
      Hive.box<SyncOperation>(HiveBoxes.syncQueue);

  /// Get the metadata box
  static Box get metadataBox => Hive.box(HiveBoxes.metadata);

  /// Clear all data (for logout)
  static Future<void> clearAll() async {
    await shoppingListsBox.clear();
    await listItemsBox.clear();
    await syncQueueBox.clear();
    await metadataBox.clear();
    debugPrint('Hive database cleared');
  }

  /// Close all boxes
  static Future<void> close() async {
    await Hive.close();
    _isInitialized = false;
  }
}

/// Represents a pending sync operation
enum SyncOperationType { create, update, delete }

class SyncOperation {
  final String id;
  final SyncOperationType type;
  final String entityType; // 'list' or 'item'
  final String entityId;
  final Map<String, dynamic>? data;
  final DateTime createdAt;
  final int retryCount;

  SyncOperation({
    required this.id,
    required this.type,
    required this.entityType,
    required this.entityId,
    this.data,
    required this.createdAt,
    this.retryCount = 0,
  });

  SyncOperation copyWith({
    String? id,
    SyncOperationType? type,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? data,
    DateTime? createdAt,
    int? retryCount,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

/// Hive adapter for SyncOperation
/// Type ID: 2
class SyncOperationAdapter extends TypeAdapter<SyncOperation> {
  @override
  final int typeId = 2;

  @override
  SyncOperation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return SyncOperation(
      id: fields[0] as String,
      type: SyncOperationType.values[fields[1] as int],
      entityType: fields[2] as String,
      entityId: fields[3] as String,
      data: fields[4] != null
          ? Map<String, dynamic>.from(fields[4] as Map)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[5] as int),
      retryCount: fields[6] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, SyncOperation obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type.index)
      ..writeByte(2)
      ..write(obj.entityType)
      ..writeByte(3)
      ..write(obj.entityId)
      ..writeByte(4)
      ..write(obj.data)
      ..writeByte(5)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(6)
      ..write(obj.retryCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOperationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
