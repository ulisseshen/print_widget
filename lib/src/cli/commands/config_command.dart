import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class ConfigCommand extends Command<void> {
  ConfigCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Set the default device (e.g. iphone_15_pro, pixel_7).',
      )
      ..addOption('output', abbr: 'o', help: 'Set the output directory.')
      ..addFlag(
        'manifest',
        help: 'Enable or disable manifest.json generation.',
        defaultsTo: null,
      )
      ..addFlag(
        'flat',
        help:
            'Save all PNGs in the output directory root (name_device.png)\n'
            'instead of name/device.png subfolders.',
        defaultsTo: null,
      );
  }

  @override
  String get name => 'config';

  @override
  String get description => 'View or change print_widget settings.';

  @override
  Future<void> run() async {
    final yamlFile = File('print_widget.yaml');
    if (!yamlFile.existsSync()) {
      stderr.writeln('No print_widget.yaml found.');
      stderr.writeln('Run "print_widget init" first.');
      exitCode = 1;
      return;
    }

    final device = argResults!['device'] as String?;
    final output = argResults!['output'] as String?;
    final manifest = argResults!.wasParsed('manifest')
        ? argResults!['manifest'] as bool
        : null;
    final flat = argResults!.wasParsed('flat')
        ? argResults!['flat'] as bool
        : null;

    // No flags → show current config
    if (device == null && output == null && manifest == null && flat == null) {
      _showConfig(yamlFile);
      return;
    }

    // Update config
    var content = yamlFile.readAsStringSync();

    if (device != null) {
      if (!_validDevices.contains(device)) {
        stderr.writeln('Unknown device: $device');
        stderr.writeln('');
        stderr.writeln('Available devices:');
        for (final d in _validDevices) {
          stdout.writeln('  $d');
        }
        exitCode = 1;
        return;
      }
      content = _replaceYamlValue(content, 'default_device', device);
      stdout.writeln('[updated] default_device: $device');
    }

    if (output != null) {
      content = _replaceYamlValue(content, 'output_dir', output);
      stdout.writeln('[updated] output_dir: $output');
    }

    if (manifest != null) {
      content = _replaceYamlValue(content, 'manifest', manifest.toString());
      stdout.writeln('[updated] manifest: $manifest');
    }

    if (flat != null) {
      content = _replaceYamlValue(content, 'flat', flat.toString());
      stdout.writeln('[updated] flat: $flat');
    }

    yamlFile.writeAsStringSync(content);
  }

  void _showConfig(File yamlFile) {
    final yamlContent = loadYaml(yamlFile.readAsStringSync()) as YamlMap;

    stdout.writeln('');
    stdout.writeln('print_widget configuration');
    stdout.writeln('=' * 40);
    stdout.writeln(
      '  config_file:    ${yamlContent['config_file'] ?? 'print_widget/config.dart'}',
    );
    stdout.writeln(
      '  output_dir:     ${yamlContent['output_dir'] ?? 'print_widget/output'}',
    );
    stdout.writeln(
      '  default_device: ${yamlContent['default_device'] ?? 'iphone_15_pro'}',
    );
    stdout.writeln('  manifest:       ${yamlContent['manifest'] ?? true}');
    stdout.writeln('  flat:           ${yamlContent['flat'] ?? false}');
    stdout.writeln('');
    stdout.writeln('To change settings:');
    stdout.writeln('  print_widget config --device=pixel_7');
    stdout.writeln('  print_widget config --output=screenshots');
    stdout.writeln('  print_widget config --no-manifest');
    stdout.writeln('  print_widget config --flat');
    stdout.writeln('  print_widget config --no-flat');
    stdout.writeln('');
    stdout.writeln('Available devices:');
    for (final d in _validDevices) {
      final marker = d == (yamlContent['default_device'] ?? 'iphone_15_pro')
          ? ' (current)'
          : '';
      stdout.writeln('  $d$marker');
    }
  }
}

String _replaceYamlValue(String content, String key, String value) {
  final pattern = RegExp('^$key:.*\$', multiLine: true);
  if (pattern.hasMatch(content)) {
    return content.replaceFirst(pattern, '$key: $value');
  }
  // Key not found, append it
  return '$content$key: $value\n';
}

const _validDevices = [
  'iphone_se',
  'iphone_14',
  'iphone_15_pro',
  'iphone_16_pro_max',
  'ipad_mini',
  'ipad_air',
  'ipad_pro_11',
  'ipad_pro_13',
  'pixel_7',
  'pixel_8_pro',
  'samsung_s24',
  'samsung_s24_ultra',
  'small',
  'medium',
  'large',
  'compact',
];
