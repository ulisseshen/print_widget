import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ensures CLI source files do not import Flutter packages at the top level.
///
/// The CLI binary must run with plain `dart`, not `flutter`. If any CLI file
/// imports Flutter types outside of string templates, `dart pub global run`
/// will fail with "Type 'Size' not found" or similar dart:ui errors.
void main() {
  test('CLI files have no top-level Flutter imports', () {
    // Find the project root by looking for pubspec.yaml
    var root = Directory.current;
    while (!File('${root.path}/pubspec.yaml').existsSync()) {
      root = root.parent;
    }
    final cliDir = Directory('${root.path}/lib/src/cli');
    final dartFiles = cliDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final violations = <String>[];

    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      final lines = content.split('\n');

      var inStringLiteral = false;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();

        // Track multi-line string literals (''' or """)
        final tripleQuoteCount = "'''".allMatches(line).length +
            '"""'.allMatches(line).length;
        if (tripleQuoteCount.isOdd) {
          inStringLiteral = !inStringLiteral;
        }

        if (inStringLiteral) continue;

        // Check for Flutter imports outside string literals
        if (line.startsWith('import ') &&
            (line.contains('package:flutter/') ||
                line.contains('package:flutter_test/') ||
                line.contains('dart:ui'))) {
          violations.add('${file.path}:${i + 1}: $line');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'CLI files must not import Flutter packages at the top level.\n'
          'The CLI runs with plain dart, not flutter.\n'
          'Violations:\n${violations.join('\n')}',
    );
  });
}
