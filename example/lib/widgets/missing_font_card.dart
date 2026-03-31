import 'package:flutter/material.dart';

/// Widget that uses a font family NOT declared in pubspec or any font directory.
/// This simulates a real-world scenario where a font fails to load.
class MissingFontCard extends StatelessWidget {
  const MissingFontCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This uses a missing font',
              style: const TextStyle(
                fontFamily: 'BrandFontThatDoesNotExist',
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Should trigger a font warning',
              style: const TextStyle(
                fontFamily: 'BrandFontThatDoesNotExist',
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
