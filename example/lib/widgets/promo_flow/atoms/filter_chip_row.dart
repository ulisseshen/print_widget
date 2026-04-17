import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.labels,
    this.selectedIndex = 0,
  });

  final List<String> labels;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: PromoSpacing.sm),
            _FilterChip(
              label: labels[i],
              isSelected: i == selectedIndex,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
  });

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PromoSpacing.lg,
        vertical: PromoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isSelected ? PromoColors.textPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(PromoRadius.pill),
        border: isSelected ? null : Border.all(color: PromoColors.border),
      ),
      child: Text(
        label,
        style: PromoTypography.bodySmall.copyWith(
          color: isSelected ? Colors.white : PromoColors.textPrimary,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
