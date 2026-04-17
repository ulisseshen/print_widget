import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

enum BadgeVariant { positive, negative, neutral, info }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.variant = BadgeVariant.neutral,
  });

  const StatusBadge.positive(this.label, {super.key}) : variant = BadgeVariant.positive;
  const StatusBadge.negative(this.label, {super.key}) : variant = BadgeVariant.negative;
  const StatusBadge.neutral(this.label, {super.key}) : variant = BadgeVariant.neutral;

  final String label;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PromoSpacing.sm + 2,
        vertical: PromoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(PromoRadius.pill),
      ),
      child: Text(
        label,
        style: PromoTypography.bodySmall.copyWith(
          color: _textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color get _backgroundColor => switch (variant) {
    BadgeVariant.positive => PromoColors.successLight,
    BadgeVariant.negative => PromoColors.dangerLight,
    BadgeVariant.neutral => PromoColors.surfaceMuted,
    BadgeVariant.info => PromoColors.primaryLight,
  };

  Color get _textColor => switch (variant) {
    BadgeVariant.positive => PromoColors.success,
    BadgeVariant.negative => PromoColors.danger,
    BadgeVariant.neutral => PromoColors.textSecondary,
    BadgeVariant.info => PromoColors.primary,
  };
}
