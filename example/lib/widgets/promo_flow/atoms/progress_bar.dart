import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.progress,
    this.height = 8,
    this.color,
    this.trackColor,
    this.borderRadius,
    this.label,
    this.trailingLabel,
  });

  final double progress;
  final double height;
  final Color? color;
  final Color? trackColor;
  final double? borderRadius;
  final String? label;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? _colorForProgress(progress);
    final radius = borderRadius ?? height / 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || trailingLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: PromoSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: PromoTypography.bodySmall.copyWith(
                      color: PromoColors.textSecondary,
                    ),
                  ),
                if (trailingLabel != null)
                  Text(
                    trailingLabel!,
                    style: PromoTypography.bodySmall.copyWith(
                      color: PromoColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Container(color: trackColor ?? PromoColors.gaugeTrack),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: effectiveColor,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Color _colorForProgress(double p) {
    if (p >= 0.7) return PromoColors.gaugeGreen;
    if (p >= 0.4) return PromoColors.gaugeOrange;
    return PromoColors.gaugeRed;
  }
}
