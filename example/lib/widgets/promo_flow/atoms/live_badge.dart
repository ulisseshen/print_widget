import 'package:flutter/material.dart';
import '../theme/promo_colors.dart';
import '../theme/promo_spacing.dart';

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PromoSpacing.sm + 2,
        vertical: PromoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: PromoColors.primary,
        borderRadius: BorderRadius.circular(PromoRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: PromoSpacing.xs + 1),
          Text(
            'AO VIVO',
            style: PromoTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
