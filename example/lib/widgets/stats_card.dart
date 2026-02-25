import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';

class StatsCard extends StatelessWidget with Printable {
  const StatsCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = Colors.blue,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  String get printName => 'stats_card';

  @override
  PrintType get printType => PrintType.widget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
