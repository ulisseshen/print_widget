import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

enum AlertSeverity { critical, warning, info, success }

class AlertItem extends StatelessWidget {
  const AlertItem({
    super.key,
    required this.message,
    this.severity = AlertSeverity.warning,
  });

  final String message;
  final AlertSeverity severity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PromoSpacing.lg,
        vertical: PromoSpacing.md,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(PromoRadius.md),
        border: Border(
          left: BorderSide(color: _borderColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(_icon, color: _borderColor, size: 20),
          const SizedBox(width: PromoSpacing.md),
          Expanded(
            child: Text(
              message,
              style: PromoTypography.bodyMedium.copyWith(
                color: PromoColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _borderColor => switch (severity) {
    AlertSeverity.critical => PromoColors.danger,
    AlertSeverity.warning => PromoColors.warning,
    AlertSeverity.info => PromoColors.info,
    AlertSeverity.success => PromoColors.success,
  };

  Color get _backgroundColor => switch (severity) {
    AlertSeverity.critical => PromoColors.dangerLight,
    AlertSeverity.warning => PromoColors.warningLight,
    AlertSeverity.info => PromoColors.infoLight,
    AlertSeverity.success => PromoColors.successLight,
  };

  IconData get _icon => switch (severity) {
    AlertSeverity.critical => Icons.warning_rounded,
    AlertSeverity.warning => Icons.warning_amber_rounded,
    AlertSeverity.info => Icons.info_outline_rounded,
    AlertSeverity.success => Icons.check_circle_outline_rounded,
  };
}
