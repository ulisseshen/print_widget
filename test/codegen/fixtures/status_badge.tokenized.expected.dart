import 'package:flutter/material.dart';
import 'package:yh_design_system/typography/inter_text.dart';

class _StatusBadgeScaffold extends StatelessWidget {
  _StatusBadgeScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      // FORCE: no token match for 10 in spacing.scale
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: YHAppSpacing.sp1),
      decoration: BoxDecoration(
        color: context.customColors.brand30.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(YHAppCornerRadiusV2.rfull),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Ativo',
            style: interText(
              size: 12,
              weight: 500,
              color: context.customColors.brand30,
              height: 1.333,
            ),
          ),
        ],
      ),
    );
  }
}
