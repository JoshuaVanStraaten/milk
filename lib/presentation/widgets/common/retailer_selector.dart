// lib/presentation/widgets/common/retailer_selector.dart

import 'package:flutter/material.dart';
import '../../../core/constants/retailers.dart';

/// Horizontal scrolling chip bar for switching between retailers.
///
/// Displays a [FilterChip] for each retailer with its brand color.
/// The selected retailer gets a filled background; unselected ones
/// show a lighter tint with the retailer icon.
class RetailerSelector extends StatelessWidget {
  final String selectedRetailer;
  final ValueChanged<String> onSelected;

  const RetailerSelector({
    super.key,
    required this.selectedRetailer,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: Retailers.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final config = Retailers.all.values.elementAt(index);
          final isSelected = config.name == selectedRetailer;

          return FilterChip(
            selected: isSelected,
            label: Text(
              config.name,
              style: TextStyle(
                color: isSelected ? Colors.white : config.color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            avatar: isSelected
                ? null
                : CircleAvatar(
                    backgroundColor: config.colorLight,
                    radius: 12,
                    child: Icon(config.icon, size: 14, color: config.color),
                  ),
            backgroundColor: config.colorLight,
            selectedColor: config.color,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            side: BorderSide.none,
            onSelected: (_) => onSelected(config.name),
          );
        },
      ),
    );
  }
}
