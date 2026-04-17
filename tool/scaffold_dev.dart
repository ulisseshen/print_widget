// Dev helper: run the scaffold generator directly with a fixed timestamp so we
// can inspect output during fixture authoring. Not part of the CLI surface.
import 'dart:convert';
import 'dart:io';

import 'package:print_widget_flutter/src/codegen/scaffold_generator.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/scaffold_dev.dart <spec.json> [className]',
    );
    exit(2);
  }
  final specPath = args[0];
  final className = args.length > 1 ? args[1] : '_Scaffold';
  final spec =
      jsonDecode(File(specPath).readAsStringSync()) as Map<String, dynamic>;
  final opts = ScaffoldGeneratorOptions(
    className: className,
    specRelativePath: specPath,
    generatedAt: '2026-04-17T00:00:00.000Z',
    regenerateCommand: 'print_widget scaffold --spec=$specPath',
  );
  final result = generateScaffold(spec, opts);
  stdout.write(result.source);
  stderr.writeln(
    'hasSvg=${result.hasSvg} todoCount=${result.todoCount}',
  );
}
