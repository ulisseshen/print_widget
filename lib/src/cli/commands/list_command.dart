import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class ListCommand extends Command<void> {
  ListCommand() {
    argParser.addOption(
      'config',
      abbr: 'c',
      help: 'Path to print_widget.yaml config file.',
      defaultsTo: 'print_widget.yaml',
    );
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      'Show configured widgets and generation settings.';

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;

    final yamlFile = File(configPath);
    if (!yamlFile.existsSync()) {
      stderr.writeln(
        'Config file not found: $configPath\n'
        'Run "print_widget init" first.',
      );
      exitCode = 1;
      return;
    }

    final yamlContent = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
    final dartConfigFile = yamlContent['config_file'] as String? ??
        'test/prints/print_config.dart';
    final outputDir =
        yamlContent['output_dir'] as String? ?? 'test/prints/output';
    final defaultDevice =
        yamlContent['default_device'] as String? ?? 'iphone_15_pro';
    final manifestEnabled = yamlContent['manifest'] as bool? ?? true;

    stdout.writeln('print_widget configuration');
    stdout.writeln('=' * 40);
    stdout.writeln('  Config file:    $dartConfigFile');
    stdout.writeln('  Output dir:     $outputDir');
    stdout.writeln('  Default device: $defaultDevice');
    stdout.writeln('  Manifest:       $manifestEnabled');
    stdout.writeln('');

    // Try to parse the Dart config file for basic info
    final configFile = File(dartConfigFile);
    if (!configFile.existsSync()) {
      stderr.writeln('Dart config file not found: $dartConfigFile');
      stderr.writeln('Run "print_widget init" to create it.');
      return;
    }

    final dartContent = configFile.readAsStringSync();
    final entries = _parseEntries(dartContent);

    if (entries.isEmpty) {
      stdout.writeln('No print entries detected in $dartConfigFile.');
      stdout.writeln('');
      stdout.writeln('Add entries to your printList:');
      stdout.writeln("  page('login_page', const LoginPage()),");
      stdout.writeln("  widget('product_card', ProductCard()),");
    } else {
      stdout.writeln('Detected print entries:');
      stdout.writeln('─' * 40);
      for (final entry in entries) {
        stdout.writeln('  ${entry.type.padRight(8)} ${entry.name}');
      }
      stdout.writeln('');
      stdout.writeln('${entries.length} entry(ies) found.');
    }

    stdout.writeln('');
    stdout.writeln(
      'Note: This shows a static parse of the config file.\n'
      'The actual list is determined at runtime by the printList variable.',
    );
  }
}

/// Lightweight regex-based parser to extract page() and widget() calls
/// from the Dart config file. This does not execute the code, so it only
/// catches entries written as literal function calls.
List<_ParsedEntry> _parseEntries(String dartContent) {
  final entries = <_ParsedEntry>[];

  // Match page('name', ...) or widget('name', ...)
  final pattern = RegExp(
    r'''\b(page|widget)\s*\(\s*['"]([^'"]+)['"]''',
  );

  for (final match in pattern.allMatches(dartContent)) {
    entries.add(_ParsedEntry(
      type: match.group(1)!,
      name: match.group(2)!,
    ));
  }

  return entries;
}

class _ParsedEntry {
  const _ParsedEntry({required this.type, required this.name});
  final String type;
  final String name;
}
