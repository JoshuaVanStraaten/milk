/// Shopping list model matching the Shopping_List_Overview table
class ShoppingList {
  final String shoppingListId;
  final String userId;
  final DateTime createdAt;
  final bool completedList;
  final String listName;
  final String storeName;
  final double totalPrice;
  final String? listColour;
  final String? chatId;

  ShoppingList({
    required this.shoppingListId,
    required this.userId,
    required this.createdAt,
    required this.completedList,
    required this.listName,
    required this.storeName,
    required this.totalPrice,
    this.listColour,
    this.chatId,
  });

  /// Create from JSON (Supabase response)
  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    return ShoppingList(
      shoppingListId: json['ShoppingList_ID'] as String? ?? '',
      userId: json['id'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      completedList: json['completed_list'] as bool? ?? false,
      listName: json['list_name'] as String? ?? 'Unnamed List',
      storeName: json['store_name'] as String? ?? 'Unknown Store',
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      listColour: json['list_colour'] as String?,
      chatId: json['ChatID'] as String?,
    );
  }

  /// Convert to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      'ShoppingList_ID': shoppingListId,
      'id': userId,
      'created_at': createdAt.toIso8601String(),
      'completed_list': completedList,
      'list_name': listName,
      'store_name': storeName,
      'total_price': totalPrice,
      'list_colour': listColour,
      'ChatID':
          chatId ?? shoppingListId, // Use shoppingListId if chatId is null
    };
  }

  /// Copy with method for updates
  ShoppingList copyWith({
    String? shoppingListId,
    String? userId,
    DateTime? createdAt,
    bool? completedList,
    String? listName,
    String? storeName,
    double? totalPrice,
    String? listColour,
    String? chatId,
  }) {
    return ShoppingList(
      shoppingListId: shoppingListId ?? this.shoppingListId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      completedList: completedList ?? this.completedList,
      listName: listName ?? this.listName,
      storeName: storeName ?? this.storeName,
      totalPrice: totalPrice ?? this.totalPrice,
      listColour: listColour ?? this.listColour,
      chatId: chatId ?? this.chatId,
    );
  }

  @override
  String toString() {
    return 'ShoppingList(id: $shoppingListId, name: $listName, store: $storeName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShoppingList && other.shoppingListId == shoppingListId;
  }

  @override
  int get hashCode => shoppingListId.hashCode;
}
