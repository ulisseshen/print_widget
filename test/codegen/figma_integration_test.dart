import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// End-to-end tests for `print_widget figma-spec`: invokes the CLI via
/// `Process.run` against synthetic Figma MCP fixtures and compares the
/// emitted spec envelope with the expected JSON.
///
/// Also verifies the figma-spec → scaffold chain: the emitted spec must be
/// consumable by the existing scaffold generator with no TODO markers on
/// the three canary fixtures.
void main() {
  group('print_widget figma-spec — integration', () {
    late Directory tmpDir;
    late String cliPath;
    late String fixturesDir;

    setUpAll(() {
      cliPath = p.absolute(
        p.join(Directory.current.path, 'bin', 'print_widget.dart'),
      );
      fixturesDir = p.absolute(
        p.join(Directory.current.path, 'test', 'codegen', 'figma_fixtures'),
      );
    });

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_figma_spec_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    Future<ProcessResult> runFigmaSpec(List<String> args) {
      return Process.run(
        'dart',
        ['run', cliPath, 'figma-spec', ...args],
        workingDirectory: tmpDir.path,
      );
    }

    Future<ProcessResult> runScaffold(List<String> args) {
      return Process.run(
        'dart',
        ['run', cliPath, 'scaffold', ...args],
        workingDirectory: tmpDir.path,
      );
    }

    for (final fixture in const ['flex_card', 'icon_row', 'absolute_badge']) {
      test('$fixture: CLI stdout matches expected_spec.json', () async {
        final mcp = p.join(fixturesDir, '$fixture.mcp.json');
        final expectedPath = p.join(fixturesDir, '$fixture.expected_spec.json');
        final r = await runFigmaSpec([
          '--input=$mcp',
          '--stdout',
        ]);
        expect(r.exitCode, 0,
            reason: 'stderr: ${r.stderr}\nstdout: ${r.stdout}');
        final actual = jsonDecode(r.stdout as String);
        final expected = jsonDecode(File(expectedPath).readAsStringSync());
        expect(actual, equals(expected),
            reason: 'spec mismatch for $fixture');
      });
    }

    test('--output writes a file with trailing newline', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final outPath = p.join(tmpDir.path, 'out', 'kpi_card_spec.json');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--output=$outPath',
      ]);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final out = File(outPath);
      expect(out.existsSync(), isTrue);
      final content = out.readAsStringSync();
      expect(content, endsWith('\n'));
      final decoded = jsonDecode(content);
      expect(decoded[r'$version'], '1.0');
      expect(decoded['source']['extractor'], 'figma_to_spec');
    });

    test('crop.file is derived from --output basename', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final outPath = p.join(tmpDir.path, 'out', '01-card_spec.json');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--output=$outPath',
      ]);
      expect(r.exitCode, 0);
      final decoded = jsonDecode(File(outPath).readAsStringSync());
      expect(decoded['crop']['file'], '01-card.png');
    });

    test('--source-url propagates into source.url', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--stdout',
        '--source-url=https://www.figma.com/design/xyz',
      ]);
      expect(r.exitCode, 0);
      final decoded = jsonDecode(r.stdout as String);
      expect(decoded['source']['url'], 'https://www.figma.com/design/xyz');
    });

    test('--state-name overrides default root name', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--stdout',
        '--state-name=kpi_card',
      ]);
      expect(r.exitCode, 0);
      final decoded = jsonDecode(r.stdout as String);
      expect(decoded['source']['state'], 'kpi_card');
    });

    test('refuses to overwrite without --force', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final outPath = p.join(tmpDir.path, 'existing.json');
      File(outPath).writeAsStringSync('// pre-existing\n');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--output=$outPath',
      ]);
      expect(r.exitCode, isNot(0));
      expect(
        File(outPath).readAsStringSync(),
        '// pre-existing\n',
        reason: 'should not overwrite without --force',
      );
    });

    test('--force overwrites existing output', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final outPath = p.join(tmpDir.path, 'existing.json');
      File(outPath).writeAsStringSync('// pre-existing\n');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--output=$outPath',
        '--force',
      ]);
      expect(r.exitCode, 0);
      expect(
        File(outPath).readAsStringSync(),
        isNot(contains('pre-existing')),
      );
    });

    test('--json emits machine-readable result on success', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final outPath = p.join(tmpDir.path, 'out.json');
      final r = await runFigmaSpec([
        '--input=$mcp',
        '--output=$outPath',
        '--json',
      ]);
      expect(r.exitCode, 0);
      final decoded = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(decoded['extractor'], 'figma_to_spec');
      expect(decoded['output'], outPath);
      expect(decoded['nodes'], isA<int>());
      expect(decoded['nodes'], greaterThan(1));
    });

    test('requires --input', () async {
      final r = await runFigmaSpec([]);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('--input'));
    });

    test('requires --output or --stdout', () async {
      final mcp = p.join(fixturesDir, 'flex_card.mcp.json');
      final r = await runFigmaSpec(['--input=$mcp']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('--output'));
    });

    test('rejects missing input file', () async {
      final r = await runFigmaSpec([
        '--input=/nonexistent/nope.json',
        '--stdout',
      ]);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('not found'));
    });

    test('rejects malformed JSON input', () async {
      final bad = File(p.join(tmpDir.path, 'bad.json'));
      bad.writeAsStringSync('{not valid json');
      final r = await runFigmaSpec(['--input=${bad.path}', '--stdout']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('invalid JSON'));
    });

    test('rejects non-object JSON root', () async {
      final bad = File(p.join(tmpDir.path, 'arr.json'));
      bad.writeAsStringSync('[]');
      final r = await runFigmaSpec(['--input=${bad.path}', '--stdout']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('object'));
    });

    test('rejects JSON that does not contain a Figma node', () async {
      final bad = File(p.join(tmpDir.path, 'junk.json'));
      bad.writeAsStringSync('{"foo": "bar"}');
      final r = await runFigmaSpec(['--input=${bad.path}', '--stdout']);
      expect(r.exitCode, isNot(0));
    });

    // ----- figma-spec → scaffold chain (consumability gate) -------------

    for (final fixture in const ['flex_card', 'icon_row', 'absolute_badge']) {
      test(
          '$fixture: figma-spec output is scaffold-compatible (no TODO)',
          () async {
        final mcp = p.join(fixturesDir, '$fixture.mcp.json');
        final specPath = p.join(tmpDir.path, '${fixture}_spec.json');

        // Step 1: figma-spec → file
        final spec = await runFigmaSpec([
          '--input=$mcp',
          '--output=$specPath',
        ]);
        expect(spec.exitCode, 0, reason: 'figma-spec: ${spec.stderr}');

        // Step 2: scaffold --stdout
        final scaf = await runScaffold([
          '--spec=$specPath',
          '--stdout',
        ]);
        expect(scaf.exitCode, 0, reason: 'scaffold: ${scaf.stderr}');
        final source = scaf.stdout as String;
        expect(source, isNot(contains('// TODO:')),
            reason: 'scaffold emitted TODOs for $fixture:\n$source');
      });
    }
  });
}
