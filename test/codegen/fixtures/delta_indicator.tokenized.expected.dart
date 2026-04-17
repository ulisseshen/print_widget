import 'package:flutter/material.dart';
import 'package:yh_design_system/typography/inter_text.dart';

class _DeltaIndicatorScaffold extends StatelessWidget {
  _DeltaIndicatorScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '▲',
          style: interText(
            size: 12,
            weight: 500,
            color: context.customColors.brand30,
            height: 1.333,
          ),
        ),
        SizedBox(width: YHAppSpacing.sp1),
        Text(
          '+12.4%',
          style: interText(
            size: 14,
            weight: 600,
            color: context.customColors.brand30,
            height: 1.429,
          ),
        ),
      ],
    );
  }
}
