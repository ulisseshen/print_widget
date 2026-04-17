import 'package:flutter/material.dart';

class _DeltaIndicatorScaffold extends StatelessWidget {
  const _DeltaIndicatorScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '▲',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0BA284),
            height: 1.333,
          ),
        ),
        SizedBox(width: 4),
        Text(
          '+12.4%',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0BA284),
            height: 1.429,
          ),
        ),
      ],
    );
  }
}
