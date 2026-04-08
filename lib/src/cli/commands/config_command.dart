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
        help: 'Save all PNGs in the output directory root (name_device.png)\n'
            'instead of name/device.png subfolders.',
        defaultsTo: null,
      )
      ..addOption(
        'reference-dir',
        help: 'Subdirectory (relative to each entry directory) where reference\n'
            'images live. Used by "print_widget compare". Default: .reference',
      )
      ..addOption(
        'compare-threshold',
        help: 'Minimum per-region similarity (0.0–1.0) for "print_widget compare"\n'
            'to exit 0. Default: 0.95',
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
    final flat =
        argResults!.wasParsed('flat') ? argResults!['flat'] as bool : null;
    final referenceDir = argResults!['reference-dir'] as String?;
    final compareThresholdRaw = argResults!['compare-threshold'] as String?;

    // No flags → show current config
    if (device == null &&
        output == null &&
        manifest == null &&
        flat == null &&
        referenceDir == null &&
        compareThresholdRaw == null) {
      _showConfig(yamlFile);
      return;
    }

    // Update config
    var content = yamlFile.readAsStringSync();

    if (device != null) {
      // Accept preset names or custom sizes: "1440x900" or "my_name:1440x900"
      if (!_validDevices.contains(device) && !_isCustomDeviceSpec(device)) {
        stderr.writeln('Unknown device: $device');
        stderr.writeln('');
        stderr.writeln('Available presets:');
        for (final d in _validDevices) {
          stdout.writeln('  $d');
        }
        stderr.writeln('');
        stderr.writeln('Custom sizes:');
        stderr.writeln('  --device 1440x900');
        stderr.writeln('  --device my_device:1440x900');
        stderr.writeln('  --device my_device:1440x900@2');
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

    if (referenceDir != null) {
      content = _replaceYamlValue(content, 'reference_dir', referenceDir);
      stdout.writeln('[updated] reference_dir: $referenceDir');
    }

    if (compareThresholdRaw != null) {
      final parsed = double.tryParse(compareThresholdRaw);
      if (parsed == null || parsed < 0.0 || parsed > 1.0) {
        stderr.writeln(
          'Invalid --compare-threshold: $compareThresholdRaw (must be 0.0–1.0)',
        );
        exitCode = 1;
        return;
      }
      content =
          _replaceYamlValue(content, 'compare_threshold', parsed.toString());
      stdout.writeln('[updated] compare_threshold: $parsed');
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
    stdout.writeln('  manifest:          ${yamlContent['manifest'] ?? true}');
    stdout.writeln('  flat:              ${yamlContent['flat'] ?? false}');
    stdout.writeln(
      '  reference_dir:     ${yamlContent['reference_dir'] ?? '.reference'}',
    );
    stdout.writeln(
      '  compare_threshold: ${yamlContent['compare_threshold'] ?? 0.95}',
    );
    stdout.writeln('');
    stdout.writeln('To change settings:');
    stdout.writeln('  print_widget config --device=pixel_7');
    stdout.writeln('  print_widget config --output=screenshots');
    stdout.writeln('  print_widget config --no-manifest');
    stdout.writeln('  print_widget config --flat');
    stdout.writeln('  print_widget config --no-flat');
    stdout.writeln('  print_widget config --reference-dir=.reference');
    stdout.writeln('  print_widget config --compare-threshold=0.95');
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

/// Matches custom device specs: "1440x900", "name:1440x900", "name:1440x900@2".
bool _isCustomDeviceSpec(String value) =>
    RegExp(r'^(\w+:)?\d+x\d+(@[\d.]+)?$').hasMatch(value);

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
  'web_1366',
  'web_1440',
  'web_1920',
  'desktop_1440p',
  'small',
  'medium',
  'large',
  'compact',
];
