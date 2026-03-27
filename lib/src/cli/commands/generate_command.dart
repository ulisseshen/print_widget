import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class GenerateCommand extends Command<void> {
  GenerateCommand() {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Generate a specific widget by name.',
      )
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Override the device frame (e.g. iphone_15_pro, pixel_7).',
      )
      ..addFlag(
        'all-devices',
        help: 'Generate screenshots for all popular devices.',
        negatable: false,
      )
      ..addFlag(
        'delete-old',
        help:
            'Delete all existing screenshots in the output directory before generating.',
        negatable: false,
      )
      ..addFlag(
        'flat',
        help:
            'Save all PNGs in the output directory root with name_device.png naming\n'
            'instead of name/device.png subfolders.',
        defaultsTo: null,
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to print_widget.yaml config file.',
        defaultsTo: 'print_widget.yaml',
      );
  }

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generate widget screenshots by running Flutter golden tests.';

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
    final filterName = argResults!['name'] as String?;
    final deviceOverride = argResults!['device'] as String?;
    final allDevices = argResults!['all-devices'] as bool;
    final deleteOld = argResults!['delete-old'] as bool;
    final flatFlag = argResults!.wasParsed('flat')
        ? argResults!['flat'] as bool
        : null;

    // 1. Read print_widget.yaml
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
    final dartConfigFile =
        yamlContent['config_file'] as String? ?? 'print_widget/config.dart';
    final outputDir =
        yamlContent['output_dir'] as String? ?? 'print_widget/output';
    final defaultDevice =
        yamlContent['default_device'] as String? ?? 'iphone_15_pro';
    final manifestEnabled = yamlContent['manifest'] as bool? ?? true;
    final flat = flatFlag ?? (yamlContent['flat'] as bool? ?? false);

    // Verify the Dart config file exists
    if (!File(dartConfigFile).existsSync()) {
      stderr.writeln(
        'Dart config file not found: $dartConfigFile\n'
        'Run "print_widget init" to create a template.',
      );
      exitCode = 1;
      return;
    }

    // Delete old screenshots if requested
    if (deleteOld) {
      final outDir = Directory(outputDir);
      if (outDir.existsSync()) {
        final entries = outDir.listSync();
        for (final entry in entries) {
          if (entry is Directory) {
            entry.deleteSync(recursive: true);
          } else if (entry is File) {
            entry.deleteSync();
          }
        }
        stdout.writeln('print_widget: Deleted old screenshots from $outputDir');
      }
    }

    // Ensure output dir exists
    Directory(outputDir).createSync(recursive: true);

    // 2. Generate temporary test file
    final tempDir = Directory('.dart_tool/print_widget');
    tempDir.createSync(recursive: true);

    final tempTestFile = File('${tempDir.path}/print_test.dart');

    final effectiveDevice = deviceOverride ?? defaultDevice;

    tempTestFile.writeAsStringSync(
      _generateTestContent(
        dartConfigFile: dartConfigFile,
        outputDir: outputDir,
        device: effectiveDevice,
        filterName: filterName,
        allDevices: allDevices,
        flat: flat,
      ),
    );

    stdout.writeln('print_widget: Generating screenshots...');
    stdout.writeln('  Config: $dartConfigFile');
    stdout.writeln('  Output: $outputDir');
    if (filterName != null) {
      stdout.writeln('  Filter: $filterName');
    }
    if (allDevices) {
      stdout.writeln('  Devices: all popular');
    } else {
      stdout.writeln('  Device: $effectiveDevice');
    }
    if (flat) {
      stdout.writeln('  Layout: flat (name_device.png)');
    }
    stdout.writeln('');

    // 3. Run flutter test --update-goldens
    final result = await Process.run('flutter', [
      'test',
      '--update-goldens',
      tempTestFile.path,
    ], runInShell: true);

    if (result.stdout.toString().isNotEmpty) {
      stdout.write(result.stdout);
    }

    if (result.exitCode != 0) {
      stderr.writeln('Flutter test failed (exit code ${result.exitCode}):');
      if (result.stderr.toString().isNotEmpty) {
        stderr.write(result.stderr);
      }
      exitCode = result.exitCode;
      return;
    }

    // 4. Generate manifest.json if enabled
    if (manifestEnabled) {
      _generateManifest(outputDir, flat: flat);
    }

    // 5. Summary
    stdout.writeln('');
    stdout.writeln('Screenshots generated successfully!');
    stdout.writeln('  Output directory: $outputDir');
    if (manifestEnabled) {
      stdout.writeln('  Manifest: $outputDir/manifest.json');
    }
  }
}

String _generateTestContent({
  required String dartConfigFile,
  required String outputDir,
  required String device,
  String? filterName,
  bool allDevices = false,
  bool flat = false,
}) {
  // Convert relative config path to a package-style import.
  // The config file is relative to the project root, and the test file
  // is at .dart_tool/print_widget/print_test.dart, so we need to go up
  // two directories.
  final configImport = '../../$dartConfigFile';

  return '''
// AUTO-GENERATED by print_widget CLI. Do not edit.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';

import '$configImport';

void main() {
  setUpAll(() async {
    await loadPrintWidgetFonts();
  });

  group('print_widget generate', () {
    testWidgets('generate screenshots', (tester) async {
      final session = printSession;
      final entries = printList;

      for (final entry in entries) {
        ${filterName != null ? "if (entry.name != '$filterName') continue;" : ''}

        final devices = entry.devices ??
            ${allDevices ? 'DeviceFrame.popular' : "[_resolveDevice('$device') ?? session.defaultDevice ?? DeviceFrame.iPhone15Pro]"};

        // Build render targets: (stateName?, widget)
        final targets = <(String?, Widget)>[];
        if (entry.states != null && entry.states!.isNotEmpty) {
          for (final s in entry.states!) {
            targets.add((s.name, s.widget));
          }
        } else {
          targets.add((null, entry.widget));
        }

        for (final (stateName, targetWidget) in targets) {
          for (final deviceFrame in devices) {
            // Configure surface
            await tester.binding.setSurfaceSize(deviceFrame.size);
            tester.view.physicalSize = deviceFrame.size * deviceFrame.pixelRatio;
            tester.view.devicePixelRatio = deviceFrame.pixelRatio;

            // Wrap with app wrapper from session
            final wrapped = session.appWrapper(targetWidget);

            await tester.pumpWidget(wrapped);
            await tester.pumpAndSettle();

            // Precache images so they render in golden files
            final imageWidgets = find.byType(Image);
            if (imageWidgets.evaluate().isNotEmpty) {
              await tester.runAsync(() async {
                for (final element in imageWidgets.evaluate()) {
                  final Image img = element.widget as Image;
                  await precacheImage(img.image, element);
                }
              });
              await tester.pumpAndSettle();
            }

            ${_goldenPathCode(outputDir, flat)}

            await expectLater(
              find.byWidgetPredicate((w) => w == wrapped),
              matchesGoldenFile(goldenPath),
            );

            // Reset surface
            await tester.binding.setSurfaceSize(null);
          }
        }
      }
    });
  });
}

DeviceFrame? _resolveDevice(String name) {
  const devices = <String, DeviceFrame>{
    'iphone_se': DeviceFrame.iPhoneSE,
    'iphone_14': DeviceFrame.iPhone14,
    'iphone_15_pro': DeviceFrame.iPhone15Pro,
    'iphone_16_pro_max': DeviceFrame.iPhone16ProMax,
    'ipad_mini': DeviceFrame.iPadMini,
    'ipad_air': DeviceFrame.iPadAir,
    'ipad_pro_11': DeviceFrame.iPadPro11,
    'ipad_pro_13': DeviceFrame.iPadPro13,
    'pixel_7': DeviceFrame.pixel7,
    'pixel_8_pro': DeviceFrame.pixel8Pro,
    'samsung_s24': DeviceFrame.samsungS24,
    'samsung_s24_ultra': DeviceFrame.samsungS24Ultra,
    'small': DeviceFrame.small,
    'medium': DeviceFrame.medium,
    'large': DeviceFrame.large,
    'compact': DeviceFrame.compact,
  };
  return devices[name];
}
''';
}

String _goldenPathCode(String outputDir, bool flat) {
  final base = '../../$outputDir';

  if (flat) {
    return '''final String goldenPath;
            if (stateName != null) {
              switch (session.stateOutputMode) {
                case StateOutputMode.prefix:
                  goldenPath = '$base/\${entry.name}_\${stateName}_\${deviceFrame.name}.png';
                case StateOutputMode.suffix:
                  goldenPath = '$base/\${entry.name}_\${deviceFrame.name}_\$stateName.png';
                case StateOutputMode.folder:
                  goldenPath = '$base/\${entry.name}_\${stateName}_\${deviceFrame.name}.png';
              }
            } else {
              goldenPath = '$base/\${entry.name}_\${deviceFrame.name}.png';
            }''';
  }

  return '''final String goldenPath;
            if (stateName != null) {
              switch (session.stateOutputMode) {
                case StateOutputMode.prefix:
                  goldenPath = '$base/\${entry.name}/\${stateName}_\${deviceFrame.name}.png';
                case StateOutputMode.suffix:
                  goldenPath = '$base/\${entry.name}/\${deviceFrame.name}_\$stateName.png';
                case StateOutputMode.folder:
                  goldenPath = '$base/\${entry.name}/\$stateName/\${deviceFrame.name}.png';
              }
            } else {
              goldenPath = '$base/\${entry.name}/\${deviceFrame.name}.png';
            }''';
}

void _generateManifest(String outputDir, {bool flat = false}) {
  final outDir = Directory(outputDir);
  if (!outDir.existsSync()) return;

  final screenshots = <Map<String, dynamic>>[];

  if (flat) {
    // Flat mode: PNGs are directly in outputDir with name_device.png naming
    for (final file in outDir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.png')) continue;

      final fileName = file.uri.pathSegments.last;
      final baseName = fileName.replaceAll('.png', '');

      // Parse name_device from filename by matching known device suffixes.
      // Simple lastIndexOf('_') fails because device names contain underscores
      // (e.g., login_page_iphone_15_pro → must split as login_page + iphone_15_pro).
      final match = _matchDeviceSuffix(baseName);
      if (match == null) continue;

      final entryName = match.$1;
      final deviceName = match.$2;

      screenshots.add({
        'name': entryName,
        'file': fileName,
        'device': deviceName,
      });
    }
  } else {
    // Folder mode: PNGs are in outputDir/<name>/<device>.png subdirectories
    for (final widgetDir in outDir.listSync().whereType<Directory>()) {
      final widgetName = widgetDir.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;

      for (final file in widgetDir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.png')) continue;

        final fileName = file.uri.pathSegments.last;
        final deviceName = fileName.replaceAll('.png', '');

        screenshots.add({
          'name': widgetName,
          'file': '$widgetName/$fileName',
          'device': deviceName,
        });
      }
    }
  }

  final manifest = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'outputDir': outputDir,
    'screenshots': screenshots,
  };

  final manifestFile = File('$outputDir/manifest.json');
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
}

/// Known device names from DeviceFrame presets, sorted longest-first
/// so that 'iphone_15_pro' matches before 'iphone_15'.
final _knownDevices = [
  'iphone_16_pro_max',
  'samsung_s24_ultra',
  'iphone_15_pro',
  'pixel_8_pro',
  'samsung_s24',
  'ipad_pro_13',
  'ipad_pro_11',
  'iphone_14',
  'iphone_se',
  'ipad_mini',
  'ipad_air',
  'pixel_7',
  'compact',
  'medium',
  'small',
  'large',
];

/// Tries to split a flat filename base (e.g., 'login_page_iphone_15_pro')
/// into (entryName, deviceName) by matching known device suffixes.
(String, String)? _matchDeviceSuffix(String baseName) {
  for (final device in _knownDevices) {
    if (baseName.endsWith('_$device') && baseName.length > device.length + 1) {
      final entryName = baseName.substring(
        0,
        baseName.length - device.length - 1,
      );
      return (entryName, device);
    }
  }
  // Fallback for custom devices: split at last underscore
  final lastUnderscore = baseName.lastIndexOf('_');
  if (lastUnderscore <= 0) return null;
  return (
    baseName.substring(0, lastUnderscore),
    baseName.substring(lastUnderscore + 1),
  );
}
