import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class _IconBadgeScaffold extends StatelessWidget {
  _IconBadgeScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: YHAppSpacing.sp10,
      height: YHAppSpacing.sp10,
      decoration: BoxDecoration(
        color: context.customColors.brand30.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.string(
            '''<svg class="lucide" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/></svg>''',
            width: YHAppSpacing.sp5,
            height: YHAppSpacing.sp5,
          ),
        ],
      ),
    );
  }
}
