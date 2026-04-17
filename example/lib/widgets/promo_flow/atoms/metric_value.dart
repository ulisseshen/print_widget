import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

enum MetricSize { large, medium, small }

class MetricValue extends StatelessWidget {
  const MetricValue({
    super.key,
    required this.value,
    this.unit,
    this.label,
    this.size = MetricSize.large,
    this.color,
  });

  final String value;
  final String? unit;
  final String? label;
  final MetricSize size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: _valueStyle.copyWith(
                  color: color ?? PromoColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: PromoSpacing.sm),
              Text(
                unit!,
                style: PromoTypography.bodyMedium.copyWith(
                  color: PromoColors.textMuted,
                ),
              ),
            ],
          ],
        ),
        if (label != null) ...[
          const SizedBox(height: PromoSpacing.xs),
          Text(
            label!,
            style: PromoTypography.bodySmall.copyWith(
              color: PromoColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  TextStyle get _valueStyle => switch (size) {
    MetricSize.large => PromoTypography.metricLarge,
    MetricSize.medium => PromoTypography.metricMedium,
    MetricSize.small => PromoTypography.metricSmall,
  };
}
