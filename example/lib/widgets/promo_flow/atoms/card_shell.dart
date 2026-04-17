import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class CardShell extends StatelessWidget {
  const CardShell({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.borderWidth = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? PromoSpacing.cardPadding,
      decoration: BoxDecoration(
        color: PromoColors.surface,
        borderRadius: BorderRadius.circular(PromoRadius.lg),
        border: borderWidth > 0
            ? Border.all(color: borderColor ?? PromoColors.border, width: borderWidth)
            : Border.all(color: PromoColors.borderLight, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
