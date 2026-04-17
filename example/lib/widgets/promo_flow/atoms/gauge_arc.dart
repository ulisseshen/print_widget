import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class GaugeArc extends StatelessWidget {
  const GaugeArc({
    super.key,
    required this.percentage,
    this.size = 160,
    this.strokeWidth = 14,
    this.label,
    this.centerLabel,
    this.color,
  });

  final double percentage;
  final double size;
  final double strokeWidth;
  final String? label;
  final String? centerLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? _colorForPercentage(percentage);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size * 0.6,
          child: CustomPaint(
            painter: _GaugeArcPainter(
              percentage: percentage.clamp(0, 100),
              color: effectiveColor,
              trackColor: PromoColors.gaugeTrack,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  centerLabel ?? '${percentage.toStringAsFixed(percentage.truncateToDouble() == percentage ? 0 : 1)}%',
                  style: PromoTypography.metricMedium.copyWith(
                    color: PromoColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: PromoSpacing.sm),
          Text(
            label!,
            style: PromoTypography.bodySmall.copyWith(
              color: PromoColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  static Color _colorForPercentage(double pct) {
    if (pct >= 70) return PromoColors.gaugeGreen;
    if (pct >= 40) return PromoColors.gaugeOrange;
    return PromoColors.gaugeRed;
  }
}

class _GaugeArcPainter extends CustomPainter {
  _GaugeArcPainter({
    required this.percentage,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double percentage;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = min(size.width / 2, size.height) - strokeWidth / 2;
    const startAngle = pi;
    const sweepFull = pi;
    final sweepValue = sweepFull * (percentage / 100);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, startAngle, sweepFull, false, trackPaint);
    if (percentage > 0) {
      canvas.drawArc(rect, startAngle, sweepValue, false, valuePaint);
    }
  }

  @override
  bool shouldRepaint(_GaugeArcPainter oldDelegate) =>
      oldDelegate.percentage != percentage || oldDelegate.color != color;
}
