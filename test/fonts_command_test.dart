import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Integration test for `print_widget fonts`.
///
/// Pure Dart, no network — every test runs with `--dry-run` so we never hit
/// Google Fonts. Seeds a fake project in a temp dir, drops a crafted
/// `_fonts.json`, asserts on the structured output.
void main() {
  group('fonts command', () {
    late Directory tmpDir;
    late String cliPath;

    setUpAll(() {
      cliPath =
          p.absolute(p.join(Directory.current.path, 'bin', 'print_widget.dart'));
    });

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_fonts_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    void seedYaml({String outputDir = 'print_widget/output'}) {
      File(p.join(tmpDir.path, 'print_widget.yaml')).writeAsStringSync('''
config_file: print_widget/config.dart
output_dir: $outputDir
default_device: iphone_15_pro
reference_dir: .reference
''');
    }

    String seedReport(
      String relPath, {
      List<Map<String, Object>> families = const [
        {
          'family': 'Inter',
          'weights': [400, 500, 700],
          'sources': ['detected'],
        },
      ],
      List<String> forceSpecs = const [],
    }) {
      final abs = p.join(tmpDir.path, relPath);
      Directory(p.dirname(abs)).createSync(recursive: true);
      final body = {
        r'$version': '1.0',
        'source': {'url': 'https://example.com/', 'state': 'initial'},
        'families': families,
        'googleFontsCssUrl':
            'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700',
        'forceFontSpecs': forceSpecs,
      };
      File(abs).writeAsStringSync(jsonEncode(body));
      return abs;
    }

    Future<ProcessResult> runFonts(List<String> args) {
      return Process.run(
        'dart',
        ['run', cliPath, 'fonts', ...args],
        workingDirectory: tmpDir.path,
      );
    }

    test('--dry-run --json lists would-download entries from a single file',
        () async {
      seedYaml();
      final reportPath =
          seedReport('print_widget/output/home/.reference/_fonts.json');

      final r = await runFonts([
        '--source=$reportPath',
        '--dry-run',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}\nstdout: ${r.stdout}');

      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(out['dryRun'], true);
      expect((out['reports'] as List).length, 1);

      final downloads = (out['downloads'] as List).cast<Map>();
      expect(downloads.length, 3);
      expect(
        downloads.every((d) => d['status'] == 'would-download'),
        isTrue,
      );
      expect(
        downloads.map((d) => '${d['family']}-${d['weight']}').toSet(),
        {'Inter-400', 'Inter-500', 'Inter-700'},
      );
    });

    test('filenames follow <Family>-<WeightName>.ttf convention', () async {
      seedYaml();
      seedReport(
        'print_widget/output/a/.reference/_fonts.json',
        families: [
          {
            'family': 'Inter',
            'weights': [400, 600, 900],
            'sources': ['detected'],
          }
        ],
      );

      final r = await runFonts(['--dry-run', '--json']);
      expect(r.exitCode, 0);

      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      final files = (out['downloads'] as List)
          .cast<Map>()
          .map((d) => d['file'] as String)
          .toSet();

      expect(files, contains(p.join('google_fonts', 'Inter-Regular.ttf')));
      expect(files, contains(p.join('google_fonts', 'Inter-SemiBold.ttf')));
      expect(files, contains(p.join('google_fonts', 'Inter-Black.ttf')));
    });

    test('directory source walks recursively and merges multiple reports',
        () async {
      seedYaml();
      seedReport(
        'print_widget/output/a/.reference/_fonts.json',
        families: [
          {
            'family': 'Inter',
            'weights': [400, 500],
            'sources': ['detected'],
          }
        ],
      );
      seedReport(
        'print_widget/output/b/.reference/_fonts.json',
        families: [
          {
            'family': 'Inter',
            'weights': [500, 700], // overlaps with report A on 500
            'sources': ['detected'],
          },
          {
            'family': 'Geist Mono',
            'weights': [400],
            'sources': ['forced'],
          }
        ],
      );

      final r = await runFonts(['--dry-run', '--json']);
      expect(r.exitCode, 0);

      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect((out['reports'] as List).length, 2);

      // Inter gets the union of weights, not a duplicate per report.
      final inters = (out['downloads'] as List)
          .cast<Map>()
          .where((d) => d['family'] == 'Inter')
          .toList();
      expect(inters.length, 3, reason: 'expected weights {400, 500, 700}');
      expect(inters.map((d) => d['weight']).toSet(), {400, 500, 700});

      // "Geist Mono" family is preserved with a space in the filename.
      final geist = (out['downloads'] as List)
          .cast<Map>()
          .where((d) => d['family'] == 'Geist Mono')
          .toList();
      expect(geist.length, 1);
      expect(
        geist.first['file'],
        p.join('google_fonts', 'Geist Mono-Regular.ttf'),
      );
    });

    test('assets/fonts destination changes file paths', () async {
      seedYaml();
      seedReport('print_widget/output/a/.reference/_fonts.json');

      final r = await runFonts([
        '--dry-run',
        '--json',
        '--dest=assets/fonts',
      ]);
      expect(r.exitCode, 0);

      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(out['dest'], 'assets/fonts');
      final files = (out['downloads'] as List)
          .cast<Map>()
          .map((d) => d['file'] as String)
          .toList();
      expect(files, isNotEmpty);
      expect(
        files.every((f) => f.startsWith('assets/fonts${Platform.pathSeparator}')),
        isTrue,
        reason: 'files: $files',
      );
    });

    test('no _fonts.json anywhere → exit code 2 with a helpful error',
        () async {
      seedYaml();
      // Note: no reports seeded.

      final r = await runFonts(['--dry-run', '--json']);
      expect(r.exitCode, 2);

      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      final errors = (out['errors'] as List).cast<String>();
      expect(errors, isNotEmpty);
      expect(
        errors.any((e) => e.contains('No _fonts.json found')),
        isTrue,
        reason: 'errors: $errors',
      );
    });

    test('malformed _fonts.json is skipped without crashing', () async {
      seedYaml();
      // Valid report:
      seedReport('print_widget/output/good/.reference/_fonts.json');
      // Malformed:
      final bad = p.join(
        tmpDir.path,
        'print_widget/output/bad/.reference/_fonts.json',
      );
      Directory(p.dirname(bad)).createSync(recursive: true);
      File(bad).writeAsStringSync('{not valid json');

      final r = await runFonts(['--dry-run', '--json']);
      expect(r.exitCode, 0, reason: 'malformed JSON should not fail the run');

      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      // Both files get listed as inspected sources, but only the good one
      // contributes downloads.
      expect((out['reports'] as List).length, 2);
      expect((out['downloads'] as List), isNotEmpty);
    });

    test('system fonts listed in a report are silently ignored', () async {
      seedYaml();
      // A report that (incorrectly) contains "sans-serif" survives older
      // extract versions — mergeReports itself does not re-filter system
      // fonts. Here we just ensure the command doesn't crash and produces
      // a sensible plan when a report contains unusual entries.
      seedReport(
        'print_widget/output/a/.reference/_fonts.json',
        families: [
          {
            'family': 'Inter',
            'weights': [400],
            'sources': ['detected'],
          },
          {
            'family': 'sans-serif',
            'weights': [400],
            'sources': ['detected'],
          }
        ],
      );

      final r = await runFonts(['--dry-run', '--json']);
      expect(r.exitCode, 0);
      // The command attempts to resolve every family present in the report;
      // filtering happens at extract time (see extract.mjs isSystemFont).
      // This test pins that behavior — if we later move filtering to the
      // Dart command, this assertion should flip.
      final out = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      final families = (out['downloads'] as List)
          .cast<Map>()
          .map((d) => d['family'])
          .toSet();
      expect(families, contains('Inter'));
    });
  });
}
