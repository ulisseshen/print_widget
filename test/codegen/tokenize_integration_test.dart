import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// End-to-end tests: invoke `print_widget tokenize` via `Process.run`
/// against the scaffold fixtures and assert the dart-formatted output matches
/// the `.tokenized.expected.dart` golden files.
void main() {
  group('print_widget tokenize — integration', () {
    late Directory tmpDir;
    late String cliPath;
    late String fixturesDir;
    late String themePath;

    setUpAll(() {
      cliPath = p.absolute(
        p.join(Directory.current.path, 'bin', 'print_widget.dart'),
      );
      fixturesDir = p.absolute(
        p.join(Directory.current.path, 'test', 'codegen', 'fixtures'),
      );
      themePath = p.join(fixturesDir, 'theme-ref.test.json');
    });

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_tokenize_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    Future<ProcessResult> runTokenize(List<String> args) {
      return Process.run(
        'dart',
        ['run', cliPath, 'tokenize', ...args],
        workingDirectory: tmpDir.path,
      );
    }

    /// Runs tokenize then `dart format` on the output and returns the
    /// formatted source minus the tokenize header (so we compare apples to
    /// apples with the `.tokenized.expected.dart` golden which has no header).
    Future<String> renderFormatted(String fixtureName) async {
      final input = p.join(fixturesDir, '$fixtureName.expected.dart');
      final r = await runTokenize([
        '--input=$input',
        '--theme=$themePath',
        '--stdout',
      ]);
      expect(r.exitCode, 0,
          reason: 'stderr: ${r.stderr}\nstdout: ${r.stdout}');
      final raw = r.stdout as String;

      // Write to scratch, dart format.
      final scratch = File(p.join(tmpDir.path, '$fixtureName.dart'));
      scratch.writeAsStringSync(raw);
      final fmt = await Process.run('dart', ['format', scratch.path]);
      expect(fmt.exitCode, 0, reason: 'dart format failed: ${fmt.stderr}');
      final formatted = scratch.readAsStringSync();
      return _stripHeader(formatted);
    }

    for (final name in [
      'icon_badge',
      'delta_indicator',
      'status_badge',
    ]) {
      test('$name scaffold → tokenized.expected.dart', () async {
        final actual = await renderFormatted(name);
        final expected = File(
          p.join(fixturesDir, '$name.tokenized.expected.dart'),
        ).readAsStringSync();
        expect(
          actual.trim(),
          equals(expected.trim()),
          reason: 'Tokenized output for $name does not match '
              'test/codegen/fixtures/$name.tokenized.expected.dart.\n'
              'Update the fixture if the change is intentional.',
        );
      });
    }

    test('--output writes file and creates parent dirs', () async {
      final input = p.join(fixturesDir, 'delta_indicator.expected.dart');
      final outPath = p.join(tmpDir.path, 'lib', 'gen', 'delta.dart');
      final r = await runTokenize([
        '--input=$input',
        '--theme=$themePath',
        '--output=$outPath',
      ]);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final out = File(outPath);
      expect(out.existsSync(), isTrue);
      final content = out.readAsStringSync();
      expect(content, contains('// Tokenized by print_widget tokenize'));
      expect(content, contains('interText('));
    });

    test('refuses to overwrite without --force', () async {
      final input = p.join(fixturesDir, 'icon_badge.expected.dart');
      final outPath = p.join(tmpDir.path, 'existing.dart');
      File(outPath).writeAsStringSync('// pre-existing\n');
      final r = await runTokenize([
        '--input=$input',
        '--theme=$themePath',
        '--output=$outPath',
      ]);
      expect(r.exitCode, isNot(0));
      expect(File(outPath).readAsStringSync(), '// pre-existing\n');
    });

    test('--force overwrites existing output', () async {
      final input = p.join(fixturesDir, 'icon_badge.expected.dart');
      final outPath = p.join(tmpDir.path, 'existing.dart');
      File(outPath).writeAsStringSync('// pre-existing\n');
      final r = await runTokenize([
        '--input=$input',
        '--theme=$themePath',
        '--output=$outPath',
        '--force',
      ]);
      expect(r.exitCode, 0);
      expect(File(outPath).readAsStringSync(), isNot(contains('pre-existing')));
    });

    test('--json emits machine-readable report', () async {
      final input = p.join(fixturesDir, 'status_badge.expected.dart');
      final outPath = p.join(tmpDir.path, 'out.dart');
      final r = await runTokenize([
        '--input=$input',
        '--theme=$themePath',
        '--output=$outPath',
        '--json',
      ]);
      expect(r.exitCode, 0);
      final decoded = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(decoded['output'], outPath);
      expect(decoded['counts'], isA<Map>());
      expect((decoded['counts'] as Map)['color'], 2);
      expect((decoded['counts'] as Map)['radius'], 1);
      expect((decoded['counts'] as Map)['typography'], 1);
      // status_badge's `horizontal: 10` can't map → expect at least 1 forced.
      expect((decoded['forced'] as List), isNotEmpty);
    });

    test('--strategy=near accepts fuzzy match within tolerance', () async {
      // A scaffold that uses a near-but-not-exact brand30 color.
      final nearScaffold = File(p.join(tmpDir.path, 'near.dart'));
      nearScaffold.writeAsStringSync('''
import 'package:flutter/material.dart';

class _Near extends StatelessWidget {
  const _Near({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(color: Color(0xFF0DA485));
  }
}
''');
      final r = await runTokenize([
        '--input=${nearScaffold.path}',
        '--theme=$themePath',
        '--strategy=near',
        '--tolerance=5',
        '--stdout',
      ]);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      expect(r.stdout as String, contains('context.customColors.brand30'));
    });

    test('refuses already-tokenized input', () async {
      final input = p.join(fixturesDir, 'icon_badge.expected.dart');
      final outPath = p.join(tmpDir.path, 'first.dart');
      final r1 = await runTokenize([
        '--input=$input',
        '--theme=$themePath',
        '--output=$outPath',
      ]);
      expect(r1.exitCode, 0);
      // Run tokenize again on the already-tokenized output.
      final r2 = await runTokenize([
        '--input=$outPath',
        '--theme=$themePath',
        '--stdout',
      ]);
      expect(r2.exitCode, isNot(0));
      expect(r2.stderr.toString(), contains('already contains tokenized'));
    });

    test('requires --input', () async {
      final r = await runTokenize(['--theme=$themePath']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('--input'));
    });

    test('requires --theme', () async {
      final input = p.join(fixturesDir, 'icon_badge.expected.dart');
      final r = await runTokenize(['--input=$input']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('--theme'));
    });

    test('rejects malformed theme JSON', () async {
      final bad = File(p.join(tmpDir.path, 'bad.json'));
      bad.writeAsStringSync('{not valid');
      final input = p.join(fixturesDir, 'icon_badge.expected.dart');
      final r = await runTokenize([
        '--input=$input',
        '--theme=${bad.path}',
        '--stdout',
      ]);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('invalid JSON'));
    });
  });
}

/// Strips the leading tokenize header (the block of comment lines at the top
/// plus the blank separator line) so fixtures can ignore it.
String _stripHeader(String source) {
  final lines = source.split('\n');
  var i = 0;
  while (i < lines.length && lines[i].startsWith('//')) {
    i++;
  }
  // Skip the blank separator line.
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  return lines.sublist(i).join('\n');
}
