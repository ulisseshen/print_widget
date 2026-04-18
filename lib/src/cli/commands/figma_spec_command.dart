import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../codegen/figma_to_spec.dart';

/// `print_widget figma-spec` — normalizes a Figma MCP `get_design_context`
/// response JSON file into a spec v1 envelope (the same shape that
/// `extract.mjs` emits from browser DOM). Downstream `scaffold` and
/// `tokenize` commands consume the output identically, regardless of source.
///
/// Phase 7 of the spec pipeline. MVP: pure-data normalization only — no live
/// Figma REST calls, no SVG synthesis from vector paths.
class FigmaSpecCommand extends Command<void> {
  FigmaSpecCommand() {
    argParser
      ..addOption(
        'input',
        abbr: 'i',
        help: 'Path to a JSON file containing the Figma MCP response '
            '(get_design_context output).',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Destination path for the emitted _spec.json. '
            'Required unless --stdout is given.',
      )
      ..addOption(
        'source-url',
        help: 'Optional Figma URL recorded under source.url in the envelope.',
      )
      ..addOption(
        'state-name',
        help: 'Optional label copied into source.state. Defaults to the '
            "root node's name.",
      )
      ..addFlag(
        'stdout',
        help: 'Print the spec JSON to stdout instead of writing a file.',
        negatable: false,
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite --output if it already exists.',
        negatable: false,
      )
      ..addFlag(
        'json',
        help: 'Emit a machine-readable summary on stdout (node count, '
            'source state, output path).',
        negatable: false,
      );
  }

  @override
  String get name => 'figma-spec';

  @override
  String get description =>
      'Normalize a Figma MCP response into a spec v1 envelope (Phase 7).';

  @override
  Future<void> run() async {
    final args = argResults!;
    final inputPath = args['input'] as String?;
    final outputPath = args['output'] as String?;
    final toStdout = args['stdout'] as bool;
    final force = args['force'] as bool;
    final jsonMode = args['json'] as bool;
    final sourceUrl = args['source-url'] as String?;
    final stateName = args['state-name'] as String?;

    if (inputPath == null) {
      _err('figma-spec: --input=<path> is required', jsonMode);
      exitCode = 2;
      return;
    }
    if (!toStdout && outputPath == null) {
      _err(
        'figma-spec: provide --output=<path> or --stdout',
        jsonMode,
      );
      exitCode = 2;
      return;
    }

    final inFile = File(inputPath);
    if (!inFile.existsSync()) {
      _err('figma-spec: input not found: $inputPath', jsonMode);
      exitCode = 2;
      return;
    }

    Map<String, dynamic> mcp;
    try {
      final decoded = jsonDecode(inFile.readAsStringSync());
      if (decoded is! Map) {
        _err(
          'figma-spec: input JSON root must be an object (got ${decoded.runtimeType})',
          jsonMode,
        );
        exitCode = 2;
        return;
      }
      mcp = decoded.cast<String, dynamic>();
    } catch (e) {
      _err('figma-spec: invalid JSON in $inputPath: $e', jsonMode);
      exitCode = 2;
      return;
    }

    // Default crop.file to the output basename (with .png), falling back to
    // the root node name slug.
    String? cropFile;
    if (outputPath != null) {
      final base = outputPath.split(Platform.pathSeparator).last;
      cropFile = _deriveCropFile(base);
    }

    Map<String, dynamic> spec;
    try {
      spec = figmaToSpec(
        mcp,
        options: FigmaToSpecOptions(
          sourceUrl: sourceUrl,
          stateName: stateName,
          cropFileName: cropFile,
        ),
      );
    } catch (e) {
      _err('figma-spec: normalization failed: $e', jsonMode);
      exitCode = 1;
      return;
    }

    const encoder = JsonEncoder.withIndent('  ');
    final payload = '${encoder.convert(spec)}\n';

    if (toStdout) {
      stdout.write(payload);
      if (jsonMode) {
        stderr.writeln(jsonEncode(_summary(spec, null)));
      }
      exitCode = 0;
      return;
    }

    final outFile = File(outputPath!);
    if (outFile.existsSync() && !force) {
      _err(
        'figma-spec: output exists — pass --force to overwrite: $outputPath',
        jsonMode,
      );
      exitCode = 1;
      return;
    }
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(payload);

    if (jsonMode) {
      stdout.writeln(jsonEncode(_summary(spec, outputPath)));
    } else {
      stdout.writeln(
        '✓ figma-spec: wrote ${payload.split('\n').length} lines to $outputPath',
      );
      final source = spec['source'] as Map?;
      if (source != null) {
        stdout.writeln('  state: ${source['state'] ?? '-'}');
      }
      stdout.writeln('  nodes: ${_countNodes(spec['root'])}');
    }
  }

  /// Given an output basename like `01-card_spec.json`, returns `01-card.png`
  /// (matching the convention extract.mjs uses). Falls back to replacing the
  /// extension with `.png` when the pattern doesn't match.
  String _deriveCropFile(String outBasename) {
    final stem = outBasename.replaceAll(RegExp(r'\.json$'), '');
    final trimmed = stem.endsWith('_spec')
        ? stem.substring(0, stem.length - '_spec'.length)
        : stem.endsWith('.spec')
            ? stem.substring(0, stem.length - '.spec'.length)
            : stem;
    return '$trimmed.png';
  }

  Map<String, dynamic> _summary(Map<String, dynamic> spec, String? out) {
    final source = (spec['source'] as Map?)?.cast<String, dynamic>();
    return <String, dynamic>{
      if (out != null) 'output': out,
      'state': source?['state'],
      'extractor': source?['extractor'],
      'nodes': _countNodes(spec['root']),
    };
  }

  int _countNodes(Object? root) {
    if (root is! Map) return 0;
    var n = 1;
    final kids = root['children'];
    if (kids is List) {
      for (final c in kids) {
        n += _countNodes(c);
      }
    }
    return n;
  }

  void _err(String msg, bool jsonMode) {
    if (jsonMode) {
      stdout.writeln(jsonEncode({'error': msg}));
    } else {
      stderr.writeln(msg);
    }
  }
}
