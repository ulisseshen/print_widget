import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../codegen/tokenizer.dart';

/// `print_widget tokenize` — transforms a Phase 4 scaffold (literal values) +
/// a theme-ref.json into a production widget source referencing design-system
/// tokens. Phase 5 of the spec pipeline.
class TokenizeCommand extends Command<void> {
  TokenizeCommand() {
    argParser
      ..addOption('input',
          abbr: 'i', help: 'Path to the scaffold .dart file to tokenize.')
      ..addOption('theme',
          abbr: 't',
          help: 'Path to the theme-ref.json that drives the substitutions.')
      ..addOption('output',
          abbr: 'o',
          help: 'Destination .dart path. Defaults to input with '
              '`_scaffold.dart` replaced by `.dart`, or alongside if stem '
              'does not end with `_scaffold`.')
      ..addOption('strategy',
          allowed: ['exact', 'near'],
          defaultsTo: 'exact',
          help: 'Color match strategy. `near` enables ΔE fuzzy match.')
      ..addOption('tolerance',
          defaultsTo: '2.0',
          help: 'ΔE tolerance used when --strategy=near.')
      ..addFlag('stdout',
          help: 'Print to stdout instead of writing a file.',
          negatable: false)
      ..addFlag('force',
          abbr: 'f',
          help: 'Overwrite --output if it already exists.',
          negatable: false)
      ..addFlag('json',
          help: 'Emit a machine-readable report on stdout.',
          negatable: false);
  }

  @override
  String get name => 'tokenize';

  @override
  String get description =>
      'Swap raw literals in a scaffold for design-system tokens using theme-ref.json.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final inputPath = args['input'] as String?;
    final themePath = args['theme'] as String?;
    final outputOverride = args['output'] as String?;
    final strategyStr = args['strategy'] as String;
    final toleranceStr = args['tolerance'] as String;
    final toStdout = args['stdout'] as bool;
    final force = args['force'] as bool;
    final jsonMode = args['json'] as bool;

    if (inputPath == null) {
      _err('tokenize: --input=<scaffold.dart> is required', jsonMode);
      exitCode = 2;
      return;
    }
    if (themePath == null) {
      _err('tokenize: --theme=<theme-ref.json> is required', jsonMode);
      exitCode = 2;
      return;
    }

    final inFile = File(inputPath);
    if (!inFile.existsSync()) {
      _err('tokenize: input not found: $inputPath', jsonMode);
      exitCode = 2;
      return;
    }
    final themeFile = File(themePath);
    if (!themeFile.existsSync()) {
      _err('tokenize: theme not found: $themePath', jsonMode);
      exitCode = 2;
      return;
    }

    Map<String, dynamic> theme;
    try {
      final decoded = jsonDecode(themeFile.readAsStringSync());
      if (decoded is! Map) {
        _err('tokenize: theme root must be a JSON object', jsonMode);
        exitCode = 2;
        return;
      }
      theme = decoded.cast<String, dynamic>();
    } catch (e) {
      _err('tokenize: invalid JSON in $themePath: $e', jsonMode);
      exitCode = 2;
      return;
    }

    final tolerance = double.tryParse(toleranceStr);
    if (tolerance == null || tolerance < 0) {
      _err('tokenize: --tolerance must be a non-negative number', jsonMode);
      exitCode = 2;
      return;
    }

    final strategy =
        strategyStr == 'near' ? TokenStrategy.near : TokenStrategy.exact;

    final relInput = _relativeTo(inputPath, Directory.current.path);
    final options = TokenizerOptions(
      theme: theme,
      strategy: strategy,
      tolerance: tolerance,
      scaffoldRelativePath: relInput,
    );

    final TokenizerResult result;
    try {
      result = tokenize(inFile.readAsStringSync(), options);
    } catch (e) {
      _err('tokenize: codegen failed: $e', jsonMode);
      exitCode = 1;
      return;
    }

    if (result.alreadyTokenized) {
      _err(
        'tokenize: input already contains tokenized references '
        '(context.customColors / YHAppSpacing / interText). '
        'Refusing to double-tokenize. Edit the scaffold, not the production widget.',
        jsonMode,
      );
      exitCode = 1;
      return;
    }

    final outputPath = outputOverride ?? _defaultOutputPath(inputPath);

    if (toStdout) {
      stdout.write(result.source);
      if (jsonMode) {
        stderr.writeln(jsonEncode(_report(result, outputPath)));
      }
      exitCode = 0;
      return;
    }

    final outFile = File(outputPath);
    if (outFile.existsSync() && !force) {
      _err(
        'tokenize: output exists — pass --force to overwrite: $outputPath',
        jsonMode,
      );
      exitCode = 1;
      return;
    }
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(result.source);

    if (jsonMode) {
      stdout.writeln(jsonEncode(_report(result, outputPath)));
    } else {
      final counts = _countByKind(result.substitutions);
      stdout.writeln('✓ tokenize: wrote ${result.source.split('\n').length} '
          'lines to $outputPath');
      stdout.writeln(
        '  substitutions: ${counts['color']} colors, '
        '${counts['spacing']} spacing, '
        '${counts['radius']} radius, '
        '${counts['typography']} typography',
      );
      if (result.forced.isNotEmpty) {
        stdout.writeln('  forced: ${result.forced.length} literal(s) — '
            'see // FORCE: comments in the output');
      }
    }
  }

  Map<String, dynamic> _report(TokenizerResult r, String outputPath) => {
        'output': outputPath,
        'substitutions': r.substitutions.map((s) => s.toJson()).toList(),
        'forced': r.forced.map((f) => f.toJson()).toList(),
        'counts': _countByKind(r.substitutions),
      };

  Map<String, int> _countByKind(List<Substitution> subs) {
    final c = {'color': 0, 'spacing': 0, 'radius': 0, 'typography': 0};
    for (final s in subs) {
      c[s.kind] = (c[s.kind] ?? 0) + 1;
    }
    return c;
  }

  void _err(String msg, bool jsonMode) {
    if (jsonMode) {
      stdout.writeln(jsonEncode({'error': msg}));
    } else {
      stderr.writeln(msg);
    }
  }
}

String _defaultOutputPath(String inputPath) {
  final dir = p.dirname(inputPath);
  final stem = p.basenameWithoutExtension(inputPath);
  final ext = p.extension(inputPath);
  if (stem.endsWith('_scaffold')) {
    final base = stem.substring(0, stem.length - '_scaffold'.length);
    return p.join(dir, '$base$ext');
  }
  return p.join(dir, '${stem}_tokenized$ext');
}

String _relativeTo(String target, String base) {
  try {
    final rel = p.relative(target, from: base);
    return rel.isEmpty ? target : rel;
  } catch (_) {
    return target;
  }
}
