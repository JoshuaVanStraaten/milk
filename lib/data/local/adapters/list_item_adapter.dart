import 'package:hive/hive.dart';
import './../../models/list_item.dart';

/// Hive type adapter for ListItem
/// Type ID: 1
class ListItemAdapter extends TypeAdapter<ListItem> {
  @override
  final int typeId = 1;

  @override
  ListItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    return ListItem(
      itemId: fields[0] as String,
      shoppingListId: fields[1] as String,
      completedItem: fields[2] as bool,
      itemName: fields[3] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[4] as int),
      itemQuantity: fields[5] as double,
      itemPrice: fields[6] as double,
      itemNote: fields[7] as String?,
      itemRetailer: fields[8] as String?,
      itemSpecialPrice: fields[9] as double?,
      chatId: fields[10] as String?,
      itemTotalPrice: fields[11] as double,
    );
  }

  @override
  void write(BinaryWriter writer, ListItem obj) {
    writer
      ..writeByte(12) // Number of fields
      ..writeByte(0)
      ..write(obj.itemId)
      ..writeByte(1)
      ..write(obj.shoppingListId)
      ..writeByte(2)
      ..write(obj.completedItem)
      ..writeByte(3)
      ..write(obj.itemName)
      ..writeByte(4)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(5)
      ..write(obj.itemQuantity)
      ..writeByte(6)
      ..write(obj.itemPrice)
      ..writeByte(7)
      ..write(obj.itemNote)
      ..writeByte(8)
      ..write(obj.itemRetailer)
      ..writeByte(9)
      ..write(obj.itemSpecialPrice)
      ..writeByte(10)
      ..write(obj.chatId)
      ..writeByte(11)
      ..write(obj.itemTotalPrice);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
