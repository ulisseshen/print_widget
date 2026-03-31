import 'package:flutter/material.dart';

/// Widget that uses BrandFont from the brand_fonts dependency package.
/// This proves that print_widget auto-detects fonts from dependency packages.
class BrandFontCard extends StatelessWidget {
  const BrandFontCard({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'BrandFont',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'BrandFont',
                fontSize: 16,
                color: Colors.indigo.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
