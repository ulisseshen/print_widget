import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../codegen/scaffold_generator.dart';

/// `print_widget scaffold` — mechanical codegen from a `_spec.json` to a
/// Flutter widget source file with literal values.
///
/// Phase 4 of the spec pipeline. No tokens, no DS components, no AI in the
/// loop: the input is a decoded JSON tree, the output is deterministic Dart.
class ScaffoldCommand extends Command<void> {
  ScaffoldCommand() {
    argParser
      ..addOption(
        'spec',
        abbr: 's',
        help: 'Path to the `_spec.json` to compile.',
      )
      ..addOption(
        'class-name',
        help: 'StatelessWidget class name. '
            'Defaults to `_` + PascalCase of the spec file stem minus `_spec`.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output .dart path. '
            'Defaults to `<cwd>/lib/scaffolds/<slug>_scaffold.dart`.',
      )
      ..addFlag(
        'stdout',
        help: 'Print to stdout instead of writing a file.',
        negatable: false,
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite existing output file without prompting.',
        negatable: false,
      )
      ..addFlag(
        'json',
        help: 'Emit a machine-readable report to stdout.',
        negatable: false,
      );
  }

  @override
  String get name => 'scaffold';

  @override
  String get description =>
      'Mechanically compile a _spec.json into a Flutter widget (literal values, no tokens).';

  @override
  Future<void> run() async {
    final args = argResults!;
    final specPath = args['spec'] as String?;
    final classOverride = args['class-name'] as String?;
    final outputOverride = args['output'] as String?;
    final toStdout = args['stdout'] as bool;
    final force = args['force'] as bool;
    final jsonMode = args['json'] as bool;

    if (specPath == null) {
      _err('scaffold: --spec=<path> is required', jsonMode);
      exitCode = 2;
      return;
    }

    final specFile = File(specPath);
    if (!specFile.existsSync()) {
      _err('scaffold: spec not found: $specPath', jsonMode);
      exitCode = 2;
      return;
    }

    Map<String, dynamic> spec;
    try {
      final decoded = jsonDecode(specFile.readAsStringSync());
      if (decoded is! Map) {
        _err('scaffold: spec root must be a JSON object', jsonMode);
        exitCode = 2;
        return;
      }
      spec = decoded.cast<String, dynamic>();
    } catch (e) {
      _err('scaffold: invalid JSON in $specPath: $e', jsonMode);
      exitCode = 2;
      return;
    }

    final stem = _specStem(specPath);
    final className = classOverride ?? _defaultClassName(stem);
    final outputPath = outputOverride ??
        p.join(Directory.current.path, 'lib', 'scaffolds',
            '${_slug(stem)}_scaffold.dart');

    final relSpec = _relativeTo(specPath, Directory.current.path);
    final relOutput = _relativeTo(outputPath, Directory.current.path);
    final regenerate = [
      'print_widget scaffold',
      '--spec=$relSpec',
      '--class-name=$className',
      if (!toStdout) '--output=$relOutput',
    ].join(' ');

    final options = ScaffoldGeneratorOptions(
      className: className,
      specRelativePath: relSpec,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      regenerateCommand: regenerate,
    );

    final ScaffoldGeneratorResult result;
    try {
      result = generateScaffold(spec, options);
    } catch (e) {
      _err('scaffold: codegen failed: $e', jsonMode);
      exitCode = 1;
      return;
    }

    if (toStdout) {
      stdout.write(result.source);
      if (jsonMode) {
        stderr.writeln(jsonEncode({
          'className': className,
          'hasSvg': result.hasSvg,
          'todoCount': result.todoCount,
        }));
      }
      exitCode = 0;
      return;
    }

    final outFile = File(outputPath);
    if (outFile.existsSync() && !force) {
      _err(
        'scaffold: output exists — pass --force to overwrite: $outputPath',
        jsonMode,
      );
      exitCode = 1;
      return;
    }
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(result.source);

    if (jsonMode) {
      stdout.writeln(jsonEncode({
        'output': outputPath,
        'className': className,
        'hasSvg': result.hasSvg,
        'todoCount': result.todoCount,
      }));
    } else {
      stdout.writeln('✓ scaffold: wrote ${result.source.split('\n').length} '
          'lines to $outputPath');
      stdout.writeln('  class: $className');
      if (result.hasSvg) {
        stdout.writeln('  requires: flutter_svg in pubspec.yaml');
      }
      if (result.todoCount > 0) {
        stdout.writeln(
          '  ${result.todoCount} // TODO: marker(s) — review before commit.',
        );
      }
    }
  }

  void _err(String msg, bool jsonMode) {
    if (jsonMode) {
      stdout.writeln(jsonEncode({'error': msg}));
    } else {
      stderr.writeln(msg);
    }
  }
}

/// Returns the spec file's stem minus `_spec` / `.spec`, for default names.
///
/// Handles:
///   foo_spec.json   → foo
///   foo.spec.json   → foo
///   foo.json        → foo
String _specStem(String specPath) {
  final base = p.basenameWithoutExtension(specPath);
  if (base.endsWith('_spec')) return base.substring(0, base.length - 5);
  if (base.endsWith('.spec')) return base.substring(0, base.length - 5);
  return base;
}

/// Filesystem-safe slug (lowercase, snake).
String _slug(String s) {
  return s
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '')
      .toLowerCase();
}

/// Private `_PascalCase` class name derived from the spec stem.
String _defaultClassName(String stem) {
  final parts =
      stem.split(RegExp(r'[^a-zA-Z0-9]+')).where((p) => p.isNotEmpty);
  final pascal = parts
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join();
  return '_${pascal}Scaffold';
}

String _relativeTo(String target, String base) {
  try {
    final rel = p.relative(target, from: base);
    return rel.isEmpty ? target : rel;
  } catch (_) {
    return target;
  }
}
