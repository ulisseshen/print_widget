import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Integration test for `print_widget snapshot`.
///
/// Pure Dart — no Node dependencies. Creates a fake project in a temp
/// directory, exercises the CLI, and asserts the resulting file layout.
void main() {
  group('snapshot command', () {
    late Directory tmpDir;
    late String cliPath;

    setUpAll(() {
      cliPath =
          p.absolute(p.join(Directory.current.path, 'bin', 'print_widget.dart'));
    });

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_snapshot_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    /// Seed a fake project with one entry that has:
    ///  - <entry>/<device>.png         (full-page)
    ///  - <entry>/crops/header.png
    ///  - <entry>/crops/footer.png
    ///  - <entry>/crops/header_diff.png  (should NOT be promoted)
    void seedEntry(String entry, String device) {
      File(p.join(tmpDir.path, 'print_widget.yaml')).writeAsStringSync('''
config_file: print_widget/config.dart
output_dir: print_widget/output
default_device: $device
reference_dir: .reference
''');

      final entryDir =
          Directory(p.join(tmpDir.path, 'print_widget', 'output', entry))
            ..createSync(recursive: true);
      File(p.join(entryDir.path, '$device.png')).writeAsBytesSync([1, 2, 3]);

      final cropsDir = Directory(p.join(entryDir.path, 'crops'))
        ..createSync();
      File(p.join(cropsDir.path, 'header.png')).writeAsBytesSync([4, 5]);
      File(p.join(cropsDir.path, 'footer.png')).writeAsBytesSync([6, 7]);
      File(p.join(cropsDir.path, 'header_diff.png')).writeAsBytesSync([8, 9]);
    }

    Future<ProcessResult> runSnapshot(List<String> args) {
      return Process.run(
        'dart',
        ['run', cliPath, 'snapshot', ...args],
        workingDirectory: tmpDir.path,
      );
    }

    test('promotes full-page PNG + crop PNGs and writes _origin.json',
        () async {
      seedEntry('kpi_card', 'iphone_15_pro');

      final r = await runSnapshot(['--name=kpi_card']);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}\nstdout: ${r.stdout}');

      final refDir = p.join(tmpDir.path, 'print_widget', 'output', 'kpi_card',
          '.reference');
      expect(File(p.join(refDir, 'iphone_15_pro.png')).existsSync(), isTrue);
      expect(File(p.join(refDir, 'crops', 'header.png')).existsSync(), isTrue);
      expect(File(p.join(refDir, 'crops', 'footer.png')).existsSync(), isTrue);

      // Diff PNGs must not be promoted.
      expect(
        File(p.join(refDir, 'crops', 'header_diff.png')).existsSync(),
        isFalse,
        reason: '_diff.png crops should be excluded from snapshot',
      );

      // _origin.json records the flutter origin + promoted files.
      final origin = File(p.join(refDir, '_origin.json'));
      expect(origin.existsSync(), isTrue);
      final data = jsonDecode(origin.readAsStringSync()) as Map<String, dynamic>;
      expect(data['origin'], 'flutter');
      expect(data['device'], 'iphone_15_pro');
      expect(data['files'], containsAll(<String>[
        'iphone_15_pro.png',
        'crops/header.png',
        'crops/footer.png',
      ]));
    });

    test('refuses to overwrite existing reference without --force', () async {
      seedEntry('kpi_card', 'iphone_15_pro');

      // Pre-seed a reference with different content.
      final refDir = Directory(p.join(tmpDir.path, 'print_widget', 'output',
          'kpi_card', '.reference'))
        ..createSync(recursive: true);
      final refFull = File(p.join(refDir.path, 'iphone_15_pro.png'))
        ..writeAsBytesSync([99, 99]);

      final r = await runSnapshot(['--name=kpi_card']);

      // No full-page promotion happened; bytes are still the pre-seeded ones.
      expect(refFull.readAsBytesSync(), equals([99, 99]));
      // Crops still got promoted since there was no prior reference for them.
      expect(
        File(p.join(refDir.path, 'crops', 'header.png')).existsSync(),
        isTrue,
      );
      // Exit code is 0 because SOME files were promoted (the crops).
      expect(r.exitCode, 0);
    });

    test('--force overwrites existing reference', () async {
      seedEntry('kpi_card', 'iphone_15_pro');

      final refDir = Directory(p.join(tmpDir.path, 'print_widget', 'output',
          'kpi_card', '.reference'))
        ..createSync(recursive: true);
      final refFull = File(p.join(refDir.path, 'iphone_15_pro.png'))
        ..writeAsBytesSync([99, 99]);

      final r = await runSnapshot(['--name=kpi_card', '--force']);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      expect(refFull.readAsBytesSync(), equals([1, 2, 3]));
    });

    test('--all snapshots every entry directory', () async {
      seedEntry('kpi_card', 'iphone_15_pro');
      seedEntry('hero_banner', 'iphone_15_pro');

      final r = await runSnapshot(['--all']);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');

      for (final entry in ['kpi_card', 'hero_banner']) {
        final ref = p.join(tmpDir.path, 'print_widget', 'output', entry,
            '.reference', 'iphone_15_pro.png');
        expect(File(ref).existsSync(), isTrue,
            reason: 'missing snapshot for $entry');
      }
    });

    test('requires --name or --all', () async {
      seedEntry('kpi_card', 'iphone_15_pro');
      final r = await runSnapshot([]);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('--name'));
    });

    test('--device overrides yaml default_device', () async {
      seedEntry('kpi_card', 'iphone_15_pro');
      // Seed a second device PNG.
      File(p.join(tmpDir.path, 'print_widget', 'output', 'kpi_card',
              'pixel_7.png'))
          .writeAsBytesSync([10, 20]);

      final r = await runSnapshot(['--name=kpi_card', '--device=pixel_7']);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');

      final refDir = p.join(tmpDir.path, 'print_widget', 'output', 'kpi_card',
          '.reference');
      expect(File(p.join(refDir, 'pixel_7.png')).existsSync(), isTrue);
      // iphone full-page should NOT have been promoted under --device=pixel_7.
      expect(File(p.join(refDir, 'iphone_15_pro.png')).existsSync(), isFalse);
    });

    test('--json emits structured report', () async {
      seedEntry('kpi_card', 'iphone_15_pro');

      final r = await runSnapshot(['--name=kpi_card', '--json']);
      expect(r.exitCode, 0);
      final data = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(data['entries'], isA<List>());
      final entries = data['entries'] as List;
      expect(entries, hasLength(1));
      final entry = entries.first as Map<String, dynamic>;
      expect(entry['entry'], 'kpi_card');
      expect(entry['promoted'], greaterThan(0));
    });
  });
}
