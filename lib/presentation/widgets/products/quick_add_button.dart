// lib/presentation/widgets/products/quick_add_button.dart
//
// Reusable "+" button for adding products to shopping lists.
// Used on product cards in browse screen and home deals.
// Tapping opens the add-to-list bottom sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import 'add_to_list_sheet.dart';

/// Small emerald "+" button that opens the add-to-list sheet.
///
/// Usage on a product card:
/// ```dart
/// QuickAddButton(product: liveProduct)
/// ```
class QuickAddButton extends ConsumerWidget {
  final LiveProduct product;
  final double size;

  const QuickAddButton({super.key, required this.product, this.size = 30});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _addToList(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Icon(Icons.add_rounded, size: size * 0.6, color: Colors.white),
      ),
    );
  }

  void _addToList(BuildContext context, WidgetRef ref) {
    double regularPrice = product.priceNumeric;
    double? specialPrice;
    Map<String, double>? multiBuyInfo;

    if (product.hasPromo) {
      multiBuyInfo = product.multiBuyInfo;
      if (multiBuyInfo != null) {
        specialPrice = multiBuyInfo['pricePerItem'];
      } else {
        final parsed = double.tryParse(
          product.promotionPrice.replaceAll('R', '').replaceAll(',', '').trim(),
        );
        specialPrice = parsed ?? regularPrice;
      }
    }

    showAddToListSheet(
      context,
      ref,
      productName: product.name,
      price: regularPrice,
      retailer: product.retailer,
      specialPrice: specialPrice,
      imageUrl: product.imageUrl,
      priceDisplay: product.price,
      multiBuyInfo: multiBuyInfo,
    );
  }
}
