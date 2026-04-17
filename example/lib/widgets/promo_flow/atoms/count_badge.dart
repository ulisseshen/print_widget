import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.color,
    this.size = 22,
  });

  final int count;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: const EdgeInsets.symmetric(horizontal: PromoSpacing.xs + 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? PromoColors.danger,
        borderRadius: BorderRadius.circular(PromoRadius.pill),
      ),
      child: Text(
        '$count',
        style: PromoTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
