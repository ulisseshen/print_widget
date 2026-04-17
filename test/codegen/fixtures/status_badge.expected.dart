import 'package:flutter/material.dart';

class _StatusBadgeScaffold extends StatelessWidget {
  const _StatusBadgeScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0x1F0BA284),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Ativo',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0BA284),
              height: 1.333,
            ),
          ),
        ],
      ),
    );
  }
}
