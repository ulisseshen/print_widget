import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';
import 'status_badge.dart';

class DeltaIndicator extends StatelessWidget {
  const DeltaIndicator({
    super.key,
    required this.value,
    required this.isPositive,
    this.percentage,
    this.subtitle,
  });

  final String value;
  final bool isPositive;
  final String? percentage;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final color = isPositive ? PromoColors.success : PromoColors.danger;
    final prefix = isPositive ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$prefix$value',
              style: PromoTypography.titleSmall.copyWith(color: color),
            ),
            if (percentage != null) ...[
              const SizedBox(width: PromoSpacing.sm),
              StatusBadge(
                label: '$prefix$percentage',
                variant: isPositive ? BadgeVariant.positive : BadgeVariant.negative,
              ),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: PromoSpacing.xs),
          Text(
            subtitle!,
            style: PromoTypography.caption.copyWith(
              color: PromoColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
