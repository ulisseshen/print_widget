import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Integration test for `print_widget compare`.
///
/// Skips automatically if node + pixelmatch + pngjs aren't available — the
/// compare command shells out to Node, so we can't test it in pure Dart.
void main() {
  group('compare command', () {
    late Directory tmpDir;
    late String cliPath;

    setUpAll(() {
      cliPath =
          p.absolute(p.join(Directory.current.path, 'bin', 'print_widget.dart'));
    });

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_compare_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    /// Checks if the preconditions for running the compare test are met.
    /// Runs `node --version` and checks for pixelmatch+pngjs in node_modules.
    Future<String?> skipReason() async {
      try {
        final r = await Process.run('node', ['--version']);
        if (r.exitCode != 0) return 'node not installed';
      } on ProcessException {
        return 'node not installed';
      }

      // Check that pixelmatch + pngjs are installed in a node_modules that
      // the batch script can find. We look in the repo root's node_modules.
      final repoRoot = Directory.current.path;
      final pxm = Directory(p.join(repoRoot, 'node_modules', 'pixelmatch'));
      final pngjs = Directory(p.join(repoRoot, 'node_modules', 'pngjs'));
      if (!pxm.existsSync() || !pngjs.existsSync()) {
        return 'pixelmatch/pngjs not installed — run `npm install pixelmatch pngjs` in the repo root';
      }
      return null;
    }

    /// Creates a minimal fake project in tmpDir with a generated entry
    /// and a matching reference, so compare can run against it.
    void setupFakeProject({
      required int Function(int, int) generatedColor,
      required int Function(int, int) referenceColor,
    }) {
      // print_widget.yaml
      File(p.join(tmpDir.path, 'print_widget.yaml')).writeAsStringSync('''
config_file: print_widget/config.dart
output_dir: print_widget/output
default_device: iphone_15_pro
manifest: true
reference_dir: .reference
compare_threshold: 0.95
''');

      // Output dir structure: <entry>/crops/region.png and
      // <entry>/.reference/crops/region.png
      final entryDir =
          Directory(p.join(tmpDir.path, 'print_widget', 'output', 'hero'))
            ..createSync(recursive: true);
      Directory(p.join(entryDir.path, 'crops')).createSync();
      Directory(p.join(entryDir.path, '.reference', 'crops'))
          .createSync(recursive: true);

      // Make two 40x40 images.
      final gen = img.Image(width: 40, height: 40);
      final ref = img.Image(width: 40, height: 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final g = generatedColor(x, y);
          gen.setPixelRgb(x, y, g, g, g);
          final r = referenceColor(x, y);
          ref.setPixelRgb(x, y, r, r, r);
        }
      }

      File(p.join(entryDir.path, 'crops', 'region.png'))
          .writeAsBytesSync(img.encodePng(gen));
      File(p.join(entryDir.path, '.reference', 'crops', 'region.png'))
          .writeAsBytesSync(img.encodePng(ref));
    }

    Future<ProcessResult> runCompare(List<String> args) {
      return Process.run(
        'dart',
        ['run', cliPath, 'compare', ...args],
        workingDirectory: tmpDir.path,
      );
    }

    test('identical images produce 100% similarity → exit 0', () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }

      setupFakeProject(
        generatedColor: (x, y) => 128,
        referenceColor: (x, y) => 128,
      );

      final result = await runCompare(['--name=hero', '--json']);
      expect(
        result.exitCode,
        0,
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );

      final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['success'], true);
      final entries = decoded['entries'] as Map<String, dynamic>;
      final heroResults = entries['hero'] as List<dynamic>;
      expect(heroResults, isNotEmpty);
      final first = heroResults.first as Map<String, dynamic>;
      expect(first['similarity'], 1.0);
      expect(first['passed'], true);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('different images produce <100% similarity → exit 1', () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }

      setupFakeProject(
        generatedColor: (x, y) => 128,
        referenceColor: (x, y) => (x < 20) ? 128 : 0, // half the image is different
      );

      final result = await runCompare(['--name=hero', '--json']);
      expect(
        result.exitCode,
        1,
        reason: 'expected non-zero exit for mismatch. '
            'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );

      final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['success'], false);
      final entries = decoded['entries'] as Map<String, dynamic>;
      final first =
          (entries['hero'] as List<dynamic>).first as Map<String, dynamic>;
      expect(first['similarity'], lessThan(1.0));
      expect(first['passed'], false);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
