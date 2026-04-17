import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class MetricPair extends StatelessWidget {
  const MetricPair({
    super.key,
    required this.items,
  });

  final List<MetricPairItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: PromoSpacing.md),
          Expanded(child: _MetricBox(item: items[i])),
        ],
      ],
    );
  }
}

class MetricPairItem {
  const MetricPairItem({
    required this.label,
    required this.value,
    this.delta,
    this.deltaPositive,
  });

  final String label;
  final String value;
  final String? delta;
  final bool? deltaPositive;
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.item});

  final MetricPairItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PromoSpacing.md),
      decoration: BoxDecoration(
        color: PromoColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(PromoRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.label,
            style: PromoTypography.caption.copyWith(
              color: PromoColors.textMuted,
            ),
          ),
          const SizedBox(height: PromoSpacing.xs),
          Row(
            children: [
              Flexible(
                child: Text(
                  item.value,
                  style: PromoTypography.metricSmall.copyWith(
                    color: PromoColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.delta != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PromoSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: item.deltaPositive == true
                        ? PromoColors.successLight
                        : PromoColors.dangerLight,
                    borderRadius: BorderRadius.circular(PromoRadius.pill),
                  ),
                  child: Text(
                    item.delta!,
                    style: PromoTypography.caption.copyWith(
                      color: item.deltaPositive == true
                          ? PromoColors.success
                          : PromoColors.danger,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
