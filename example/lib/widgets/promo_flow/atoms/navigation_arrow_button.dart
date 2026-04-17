import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';

class NavigationArrowButton extends StatelessWidget {
  const NavigationArrowButton({
    super.key,
    this.onTap,
    this.size = 36,
  });

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: PromoColors.border),
      ),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 18,
        color: PromoColors.textSecondary,
      ),
    );
  }
}
