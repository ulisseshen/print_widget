import 'package:flutter/material.dart';

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 20,
    this.backgroundOpacity = 0.12,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final double backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundOpacity),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
