import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Validates per-entry threshold resolution in `print_widget compare`.
///
/// Priority (first match wins):
///   1. CLI `--threshold=<n>`                → "cli override"
///   2. `thresholds.<entry>` in yaml         → "per-entry config"
///   3. _origin.json says "flutter"          → "default (flutter reference)"
///   4. _origin.json says "browser" OR file  → "cross-engine (...)"
///      is missing (conservative fallback)
void main() {
  group('compare threshold resolution', () {
    late Directory tmpDir;
    late String cliPath;

    setUpAll(() {
      cliPath =
          p.absolute(p.join(Directory.current.path, 'bin', 'print_widget.dart'));
    });

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_threshold_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    Future<String?> skipReason() async {
      try {
        final r = await Process.run('node', ['--version']);
        if (r.exitCode != 0) return 'node not installed';
      } on ProcessException {
        return 'node not installed';
      }
      final repoRoot = Directory.current.path;
      if (!Directory(p.join(repoRoot, 'node_modules', 'pixelmatch'))
              .existsSync() ||
          !Directory(p.join(repoRoot, 'node_modules', 'pngjs')).existsSync()) {
        return 'pixelmatch/pngjs not installed — run `npm install pixelmatch pngjs`';
      }
      return null;
    }

    /// Seeds a project with an identical gen/ref pair — compare will always
    /// report 100% similarity, so the only thing that changes the pass/fail
    /// decision is the threshold. Threshold source is visible in JSON output.
    void seedProject({
      required String yaml,
      required Map<String, dynamic>? originJson,
    }) {
      File(p.join(tmpDir.path, 'print_widget.yaml')).writeAsStringSync(yaml);
      final entryDir = Directory(p.join(
          tmpDir.path, 'print_widget', 'output', 'hero'))
        ..createSync(recursive: true);
      final refCropsDir = Directory(p.join(entryDir.path, '.reference', 'crops'))
        ..createSync(recursive: true);
      final genCropsDir = Directory(p.join(entryDir.path, 'crops'))
        ..createSync();

      // 10x10 flat-gray image used for both sides.
      final image = img.Image(width: 10, height: 10);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          image.setPixelRgba(x, y, 100, 100, 100, 255);
        }
      }
      final bytes = img.encodePng(image);
      File(p.join(genCropsDir.path, 'hero.png')).writeAsBytesSync(bytes);
      File(p.join(refCropsDir.path, 'hero.png')).writeAsBytesSync(bytes);

      if (originJson != null) {
        File(p.join(entryDir.path, '.reference', '_origin.json'))
            .writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(originJson));
      }
    }

    Future<Map<String, dynamic>> runCompareJson(List<String> args) async {
      final r = await Process.run(
        'dart',
        ['run', cliPath, 'compare', '--json', ...args],
        workingDirectory: tmpDir.path,
      );
      expect(
        r.exitCode,
        anyOf(0, 1),
        reason: 'compare crashed.\nstdout: ${r.stdout}\nstderr: ${r.stderr}',
      );
      return jsonDecode(r.stdout as String) as Map<String, dynamic>;
    }

    test('flutter-origin reference uses compare_threshold (default)', () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      seedProject(
        yaml: '''
output_dir: print_widget/output
default_device: iphone_15_pro
reference_dir: .reference
compare_threshold: 0.95
cross_engine_threshold: 0.88
''',
        originJson: {'origin': 'flutter', 'device': 'iphone_15_pro'},
      );

      final out = await runCompareJson(['--name=hero']);
      final hero = (out['entries'] as Map<String, dynamic>)['hero']
          as Map<String, dynamic>;
      expect(hero['threshold'], 0.95);
      expect(hero['thresholdSource'], contains('flutter'));
    });

    test('browser-origin reference uses cross_engine_threshold', () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      seedProject(
        yaml: '''
output_dir: print_widget/output
default_device: iphone_15_pro
reference_dir: .reference
compare_threshold: 0.95
cross_engine_threshold: 0.88
''',
        originJson: {'origin': 'browser', 'url': 'https://example.com/'},
      );

      final out = await runCompareJson(['--name=hero']);
      final hero = (out['entries'] as Map<String, dynamic>)['hero']
          as Map<String, dynamic>;
      expect(hero['threshold'], 0.88);
      expect(hero['thresholdSource'], contains('browser'));
    });

    test('missing _origin.json falls back to cross-engine (conservative)',
        () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      seedProject(
        yaml: '''
output_dir: print_widget/output
default_device: iphone_15_pro
reference_dir: .reference
compare_threshold: 0.95
cross_engine_threshold: 0.88
''',
        originJson: null,
      );

      final out = await runCompareJson(['--name=hero']);
      final hero = (out['entries'] as Map<String, dynamic>)['hero']
          as Map<String, dynamic>;
      expect(hero['threshold'], 0.88);
      expect(hero['thresholdSource'], contains('no _origin.json'));
    });

    test('per-entry thresholds: override beats origin-based', () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      seedProject(
        yaml: '''
output_dir: print_widget/output
default_device: iphone_15_pro
reference_dir: .reference
compare_threshold: 0.95
cross_engine_threshold: 0.88
thresholds:
  hero: 0.80
''',
        originJson: {'origin': 'browser'},
      );

      final out = await runCompareJson(['--name=hero']);
      final hero = (out['entries'] as Map<String, dynamic>)['hero']
          as Map<String, dynamic>;
      expect(hero['threshold'], 0.80);
      expect(hero['thresholdSource'], 'per-entry config');
    });

    test('CLI --threshold overrides everything', () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      seedProject(
        yaml: '''
output_dir: print_widget/output
default_device: iphone_15_pro
reference_dir: .reference
compare_threshold: 0.95
cross_engine_threshold: 0.88
thresholds:
  hero: 0.80
''',
        originJson: {'origin': 'browser'},
      );

      final out = await runCompareJson(['--name=hero', '--threshold=0.50']);
      final hero = (out['entries'] as Map<String, dynamic>)['hero']
          as Map<String, dynamic>;
      expect(hero['threshold'], 0.50);
      expect(hero['thresholdSource'], 'cli override');
    });

    test('malformed _origin.json degrades to cross-engine gracefully',
        () async {
      final reason = await skipReason();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      seedProject(
        yaml: '''
output_dir: print_widget/output
default_device: iphone_15_pro
reference_dir: .reference
compare_threshold: 0.95
cross_engine_threshold: 0.88
''',
        originJson: null,
      );
      // Overwrite the placeholder null with malformed JSON.
      File(p.join(tmpDir.path, 'print_widget', 'output', 'hero',
              '.reference', '_origin.json'))
          .writeAsStringSync('not json at all');

      final out = await runCompareJson(['--name=hero']);
      final hero = (out['entries'] as Map<String, dynamic>)['hero']
          as Map<String, dynamic>;
      expect(hero['threshold'], 0.88);
      expect(hero['thresholdSource'], contains('no _origin.json'));
    });
  });
}
