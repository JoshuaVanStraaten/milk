import 'package:hive/hive.dart';
import './../../models/shopping_list.dart';

/// Hive type adapter for ShoppingList
/// Type ID: 0
class ShoppingListAdapter extends TypeAdapter<ShoppingList> {
  @override
  final int typeId = 0;

  @override
  ShoppingList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return ShoppingList(
      shoppingListId: fields[0] as String,
      userId: fields[1] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[2] as int),
      completedList: fields[3] as bool,
      listName: fields[4] as String,
      storeName: fields[5] as String,
      totalPrice: fields[6] as double,
      listColour: fields[7] as String?,
      chatId: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ShoppingList obj) {
    writer
      ..writeByte(9) // Number of fields
      ..writeByte(0)
      ..write(obj.shoppingListId)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(3)
      ..write(obj.completedList)
      ..writeByte(4)
      ..write(obj.listName)
      ..writeByte(5)
      ..write(obj.storeName)
      ..writeByte(6)
      ..write(obj.totalPrice)
      ..writeByte(7)
      ..write(obj.listColour)
      ..writeByte(8)
      ..write(obj.chatId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShoppingListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
