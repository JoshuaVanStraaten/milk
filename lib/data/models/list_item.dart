/// List item model matching Shopping_List_Item_Level table
class ListItem {
  final String itemId;
  final String shoppingListId;
  final bool completedItem;
  final String itemName;
  final DateTime createdAt;
  final double itemQuantity;
  final double itemPrice;
  final String? itemNote;
  final String? itemRetailer;
  final double? itemSpecialPrice;
  final String? chatId;
  final double itemTotalPrice;

  ListItem({
    required this.itemId,
    required this.shoppingListId,
    this.completedItem = false,
    required this.itemName,
    required this.createdAt,
    this.itemQuantity = 1.0,
    this.itemPrice = 0.0,
    this.itemNote,
    this.itemRetailer,
    this.itemSpecialPrice,
    this.chatId,
    required this.itemTotalPrice,
  });

  /// Create ListItem from Supabase JSON
  factory ListItem.fromJson(Map<String, dynamic> json) {
    return ListItem(
      itemId: json['Item_ID'] as String,
      shoppingListId: json['ShoppingList_ID'] as String,
      completedItem: json['Completed_Item'] as bool? ?? false,
      itemName: json['Item_Name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      itemQuantity: (json['Item_Quantity'] as num?)?.toDouble() ?? 1.0,
      itemPrice: (json['Item_Price'] as num?)?.toDouble() ?? 0.0,
      itemNote: json['Item_Note'] as String?,
      itemRetailer: json['item_retailer'] as String?,
      itemSpecialPrice: (json['Item_specialprice'] as num?)?.toDouble(),
      chatId: json['ChatID'] as String?,
      itemTotalPrice: (json['item_total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      'Item_ID': itemId,
      'ShoppingList_ID': shoppingListId,
      'Completed_Item': completedItem,
      'Item_Name': itemName,
      'created_at': createdAt.toIso8601String(),
      'Item_Quantity': itemQuantity,
      'Item_Price': itemPrice,
      'Item_Note': itemNote,
      'item_retailer': itemRetailer,
      'Item_specialprice': itemSpecialPrice,
      'ChatID': chatId ?? itemId, // Use itemId if chatId is null
      'item_total_price': itemTotalPrice,
    };
  }

  /// Check if item has a special price
  bool get hasSpecialPrice {
    return itemSpecialPrice != null && itemSpecialPrice! > 0;
  }

  /// Get the effective price (special if available, otherwise regular)
  double get effectivePrice {
    return hasSpecialPrice ? itemSpecialPrice! : itemPrice;
  }

  /// Create a copy with updated fields
  ListItem copyWith({
    String? itemId,
    String? shoppingListId,
    bool? completedItem,
    String? itemName,
    DateTime? createdAt,
    double? itemQuantity,
    double? itemPrice,
    String? itemNote,
    String? itemRetailer,
    double? itemSpecialPrice,
    String? chatId,
    double? itemTotalPrice,
  }) {
    return ListItem(
      itemId: itemId ?? this.itemId,
      shoppingListId: shoppingListId ?? this.shoppingListId,
      completedItem: completedItem ?? this.completedItem,
      itemName: itemName ?? this.itemName,
      createdAt: createdAt ?? this.createdAt,
      itemQuantity: itemQuantity ?? this.itemQuantity,
      itemPrice: itemPrice ?? this.itemPrice,
      itemNote: itemNote ?? this.itemNote,
      itemRetailer: itemRetailer ?? this.itemRetailer,
      itemSpecialPrice: itemSpecialPrice ?? this.itemSpecialPrice,
      chatId: chatId ?? this.chatId,
      itemTotalPrice: itemTotalPrice ?? this.itemTotalPrice,
    );
  }

  @override
  String toString() {
    return 'ListItem(name: $itemName, qty: $itemQuantity, price: R$itemTotalPrice)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ListItem && other.itemId == itemId;
  }

  @override
  int get hashCode => itemId.hashCode;
}
