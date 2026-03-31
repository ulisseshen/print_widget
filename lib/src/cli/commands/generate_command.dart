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
      ..addFlag(
        'json',
        help: 'Output generation results as JSON.',
        negatable: false,
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
    final jsonMode = argResults!['json'] as bool;
    final flatFlag =
        argResults!.wasParsed('flat') ? argResults!['flat'] as bool : null;

    // 1. Read print_widget.yaml
    final yamlFile = File(configPath);
    if (!yamlFile.existsSync()) {
      if (jsonMode) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert({
          'success': false,
          'outputDir': '',
          'device': '',
          'screenshots': <Map<String, dynamic>>[],
          'warnings': <String>[],
          'errors': [
            'Config file not found: $configPath. '
                'Run "print_widget init" first.',
          ],
        }));
      } else {
        stderr.writeln(
          'Config file not found: $configPath\n'
          'Run "print_widget init" first.',
        );
      }
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

    final effectiveDevice = deviceOverride ?? defaultDevice;

    // Verify the Dart config file exists
    if (!File(dartConfigFile).existsSync()) {
      if (jsonMode) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert({
          'success': false,
          'outputDir': outputDir,
          'device': effectiveDevice,
          'screenshots': <Map<String, dynamic>>[],
          'warnings': <String>[],
          'errors': [
            'Dart config file not found: $dartConfigFile. '
                'Run "print_widget init" to create a template.',
          ],
        }));
      } else {
        stderr.writeln(
          'Dart config file not found: $dartConfigFile\n'
          'Run "print_widget init" to create a template.',
        );
      }
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
        if (!jsonMode) {
          stdout.writeln(
              'print_widget: Deleted old screenshots from $outputDir');
        }
      }
    }

    // Ensure output dir exists
    Directory(outputDir).createSync(recursive: true);

    // 2. Generate temporary test file
    final tempDir = Directory('.dart_tool/print_widget');
    tempDir.createSync(recursive: true);

    // Remove any stale flutter_test_config.dart in the temp dir so it
    // doesn't shadow the project's test/flutter_test_config.dart.
    final staleConfig = File('${tempDir.path}/flutter_test_config.dart');
    if (staleConfig.existsSync()) {
      staleConfig.deleteSync();
    }

    final tempTestFile = File('${tempDir.path}/print_test.dart');

    // Parse custom device spec if provided (e.g. "1440x900", "web:1440x900@2")
    final customDevice = parseCustomDevice(effectiveDevice);

    tempTestFile.writeAsStringSync(
      _generateTestContent(
        dartConfigFile: dartConfigFile,
        outputDir: outputDir,
        device: effectiveDevice,
        customDevice: customDevice,
        filterName: filterName,
        allDevices: allDevices,
        flat: flat,
      ),
    );

    if (!jsonMode) {
      stdout.writeln('print_widget: Generating screenshots...');
      stdout.writeln('  Config: $dartConfigFile');
      stdout.writeln('  Output: $outputDir');
      if (filterName != null) {
        stdout.writeln('  Filter: $filterName');
      }
      if (allDevices) {
        stdout.writeln('  Devices: all popular');
      } else if (customDevice != null) {
        stdout.writeln(
          '  Device: ${customDevice.name} (${customDevice.width.toInt()}x${customDevice.height.toInt()} @${customDevice.pixelRatio}x)',
        );
      } else {
        stdout.writeln('  Device: $effectiveDevice');
      }
      if (flat) {
        stdout.writeln('  Layout: flat (name_device.png)');
      }
      stdout.writeln('');
    }

    // 3. Run flutter test --update-goldens
    final result = await Process.run(
        'flutter',
        [
          'test',
          '--update-goldens',
          tempTestFile.path,
        ],
        runInShell: true);

    final testStdout = result.stdout.toString();
    final testStderr = result.stderr.toString();

    // Extract warnings from flutter test output
    final warnings = _extractWarnings(testStdout, testStderr);

    if (!jsonMode) {
      if (testStdout.isNotEmpty) {
        stdout.write(testStdout);
      }

      // Parse output for common errors and print actionable hints
      _parseAndPrintHints(testStdout, testStderr);
    }

    if (result.exitCode != 0) {
      // Timer pending is a warning, not a real failure — PNGs are still generated
      final isTimerOnly = testStderr.contains('Timer is still pending') ||
          testStdout.contains('Timer is still pending');
      final hasPassedTests = testStdout.contains('All tests passed') ||
          testStdout.contains('+1:');

      if (isTimerOnly && hasPassedTests) {
        // Treat as success — the screenshots were generated despite pending timers
      } else {
        if (jsonMode) {
          stdout.writeln(const JsonEncoder.withIndent('  ').convert({
            'success': false,
            'outputDir': outputDir,
            'device': effectiveDevice,
            'screenshots': <Map<String, dynamic>>[],
            'warnings': warnings,
            'errors': [
              'Flutter test failed (exit code ${result.exitCode})',
              if (testStderr.isNotEmpty) testStderr.trim(),
            ],
          }));
        } else {
          stderr.writeln('Flutter test failed (exit code ${result.exitCode}):');
          if (testStderr.isNotEmpty) {
            stderr.write(testStderr);
          }
        }
        exitCode = result.exitCode;
        return;
      }
    }

    // 4. Generate manifest.json if enabled
    if (manifestEnabled) {
      _generateManifest(outputDir, flat: flat);
    }

    // 5. Output results
    if (jsonMode) {
      // Read manifest.json to populate screenshots array
      final screenshots = <Map<String, dynamic>>[];
      final manifestFile = File('$outputDir/manifest.json');
      if (manifestEnabled && manifestFile.existsSync()) {
        final manifestData =
            jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        final manifestScreenshots =
            manifestData['screenshots'] as List<dynamic>? ?? [];
        for (final entry in manifestScreenshots) {
          final map = entry as Map<String, dynamic>;
          screenshots.add({
            'name': map['name'] as String,
            'device': map['device'] as String,
            'file': map['file'] as String,
            'status': 'success',
          });
        }
      }

      stdout.writeln(const JsonEncoder.withIndent('  ').convert({
        'success': true,
        'outputDir': outputDir,
        'device': effectiveDevice,
        'screenshots': screenshots,
        'warnings': warnings,
        'errors': <String>[],
      }));
    } else {
      stdout.writeln('');
      stdout.writeln('Screenshots generated successfully!');
      stdout.writeln('  Output directory: $outputDir');
      if (manifestEnabled) {
        stdout.writeln('  Manifest: $outputDir/manifest.json');
      }
    }
  }
}

/// Extracts warning messages from Flutter test stdout/stderr output.
///
/// Scans for overflow warnings, missing font warnings, and other
/// common issues that don't cause test failure but indicate problems.
List<String> _extractWarnings(String testStdout, String testStderr) {
  final combined = '$testStdout\n$testStderr';
  final warnings = <String>[];

  // Overflow warnings
  final overflowPattern = RegExp(
    r'A Render\w+ overflowed by ([\d.]+) pixels on the (\w+)\.',
  );
  for (final match in overflowPattern.allMatches(combined)) {
    warnings.add(
      'A RenderBox overflowed by ${match.group(1)} pixels on the '
      '${match.group(2)}',
    );
  }

  // Missing font warnings
  final fontPattern = RegExp(
    r'Warning: unable to load font (.+?) from',
    caseSensitive: false,
  );
  for (final match in fontPattern.allMatches(combined)) {
    warnings.add('Unable to load font ${match.group(1)}');
  }

  // Missing MediaQuery
  if (combined.contains('No MediaQuery')) {
    warnings.add(
      'Missing MediaQuery ancestor. Wrap your widget with MaterialApp '
      'or CupertinoApp in appWrapper.',
    );
  }

  // RenderBox layout error
  if (combined.contains('RenderBox was not laid out')) {
    warnings.add(
      'RenderBox was not laid out. A widget may have unbounded constraints.',
    );
  }

  // Missing image warnings
  final imagePattern = RegExp(
    r'═+ Exception caught by image resource service ═+',
  );
  if (imagePattern.hasMatch(combined)) {
    warnings.add(
      'Image resource error detected. Check that all images are available '
      'during test execution.',
    );
  }

  return warnings;
}

/// Scans Flutter test output for common errors and prints actionable hints.
void _parseAndPrintHints(String testStdout, String testStderr) {
  final combined = '$testStdout\n$testStderr';

  // --- Overflow errors ---
  final overflowPattern = RegExp(
    r'A Render\w+ overflowed by ([\d.]+) pixels on the (\w+)\.',
  );
  final overflowMatch = overflowPattern.firstMatch(combined);
  if (overflowMatch != null) {
    final pixels = overflowMatch.group(1);
    final direction = overflowMatch.group(2);
    stderr.writeln('');
    stderr.writeln(
      '\u26a0 Overflow detected during screenshot generation!\n'
      '\n'
      '  A widget overflowed by $pixels pixels on the $direction.\n'
      '\n'
      '  Possible fixes:\n'
      '    \u2022 Increase the \'size\' parameter on your widget() entry\n'
      '    \u2022 Use a larger DeviceFrame (e.g., DeviceFrame.web1440 for web layouts)\n'
      '    \u2022 Check that your widget handles narrow widths gracefully\n'
      '\n'
      '  Available web presets:\n'
      '    DeviceFrame.web1366  (1366x768)\n'
      '    DeviceFrame.web1440  (1440x900)\n'
      '    DeviceFrame.web1920  (1920x1080)\n'
      '\n'
      '  Tip: Use --name=<widget_name> to regenerate just one widget while iterating.',
    );
    stderr.writeln('');
  }

  // --- Import / "Could not find" errors ---
  if (combined.contains('Could not find') ||
      RegExp(
        r"Target of URI doesn't exist|cannot be found|not found.*import",
        caseSensitive: false,
      ).hasMatch(combined)) {
    stderr.writeln('');
    stderr.writeln(
      '\u26a0 Import or file resolution error detected!\n'
      '\n'
      '  Possible fixes:\n'
      '    \u2022 Check that config_file in print_widget.yaml points to the correct path\n'
      '    \u2022 Verify the Dart config file exists and compiles without errors\n'
      '    \u2022 Run "dart analyze" on your config file to check for issues',
    );
    stderr.writeln('');
  }

  // --- No MediaQuery ancestor ---
  if (combined.contains('No MediaQuery')) {
    stderr.writeln('');
    stderr.writeln(
      '\u26a0 Missing MediaQuery detected!\n'
      '\n'
      '  Your widget requires a MediaQuery ancestor that is not present.\n'
      '\n'
      '  Possible fix:\n'
      '    \u2022 Wrap your widget with MaterialApp (or CupertinoApp) in the\n'
      '      appWrapper callback of your PrintSession:\n'
      '\n'
      '      PrintSession(\n'
      '        appWrapper: (child) => MaterialApp(home: Scaffold(body: child)),\n'
      '      )',
    );
    stderr.writeln('');
  }

  // --- RenderBox was not laid out ---
  if (combined.contains('RenderBox was not laid out')) {
    stderr.writeln('');
    stderr.writeln(
      '\u26a0 RenderBox layout error detected!\n'
      '\n'
      '  A RenderBox was not laid out. This usually means a widget has\n'
      '  unbounded constraints (e.g., a Column inside a Row without\n'
      '  Expanded/Flexible, or a ListView without bounded height).\n'
      '\n'
      '  Possible fixes:\n'
      '    \u2022 Add a size parameter to your widget() entry to provide explicit bounds\n'
      '    \u2022 Wrap unbounded widgets with SizedBox, Expanded, or Flexible\n'
      '    \u2022 Use a page() entry instead, which provides full-screen constraints',
    );
    stderr.writeln('');
  }

  // --- Font / Ahem warnings ---
  if (combined.contains('Font family') && combined.contains('may not be loaded')) {
    stderr.writeln('');
    stderr.writeln(
      '\u26a0 Some fonts may not be loaded — text could render as black rectangles.\n'
      '\n'
      '  print_widget auto-loads:\n'
      '    \u2022 Bundled Roboto + MaterialIcons\n'
      '    \u2022 Fonts declared in pubspec.yaml (flutter > fonts)\n'
      '    \u2022 Fonts in google_fonts/ directory\n'
      '    \u2022 Fonts in assets/fonts/, assets/font/, fonts/\n'
      '\n'
      '  For fonts that auto-detection can\'t find, add a loadFonts callback:\n'
      '\n'
      '    final printSession = PrintSession(\n'
      '      appWrapper: (child) => MaterialApp(home: child),\n'
      '      loadFonts: () async {\n'
      '        await loadCustomFonts({\n'
      "          'MyFont': ['path/to/MyFont.ttf'],\n"
      '        });\n'
      '      },\n'
      '    );\n',
    );
    stderr.writeln('');
  }
}

String _generateTestContent({
  required String dartConfigFile,
  required String outputDir,
  required String device,
  CustomDevice? customDevice,
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
    if (printSession.setup != null) {
      await printSession.setup!();
    }
    await loadPrintWidgetFonts();
    if (printSession.loadFonts != null) {
      await printSession.loadFonts!();
    }
  });

  group('print_widget generate', () {
    testWidgets('generate screenshots', (tester) async {
      final session = printSession;
      final entries = printList;

      for (final entry in entries) {
        ${filterName != null ? "if (entry.name != '$filterName') continue;" : ''}

        final devices = entry.devices ??
            ${allDevices ? 'DeviceFrame.popular' : customDevice != null ? "[const DeviceFrame(name: '${customDevice.name}', size: Size(${customDevice.width}, ${customDevice.height}), pixelRatio: ${customDevice.pixelRatio})]" : "[_resolveDevice('$device') ?? session.defaultDevice ?? DeviceFrame.iPhone15Pro]"};

        // Build render targets: (stateName?, widget, stateSetup?)
        final targets = <(String?, Widget, Future<void> Function(WidgetTester)?)>[];
        if (entry.states != null && entry.states!.isNotEmpty) {
          for (final s in entry.states!) {
            targets.add((s.name, s.widget, s.setup));
          }
        } else {
          targets.add((null, entry.widget, null));
        }

        // Pre-validation: warn about potential issues before running golden tests
        _printWidgetValidate(entry, devices);

        for (final (stateName, targetWidget, stateSetup) in targets) {
          for (final deviceFrame in devices) {
            // Configure surface (override height when scrollExtent is set)
            final renderSize = entry.scrollExtent != null
                ? Size(deviceFrame.size.width, entry.scrollExtent!)
                : deviceFrame.size;
            await tester.binding.setSurfaceSize(renderSize);
            tester.view.physicalSize = renderSize * deviceFrame.pixelRatio;
            tester.view.devicePixelRatio = deviceFrame.pixelRatio;

            // Wrap with entry-level or session-level app wrapper
            final wrapper = entry.appWrapper ?? session.appWrapper;
            final wrapped = wrapper(targetWidget);

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

            // Run entry-level setup callback if provided
            if (entry.setup != null) {
              await entry.setup!(tester);
              await tester.pumpAndSettle();
            }

            // Run state-level setup callback if provided
            if (stateSetup != null) {
              await stateSetup(tester);
              await tester.pumpAndSettle();
            }

            // Scroll to offset if requested
            if (entry.scrollTo != null) {
              final scrollables = find.byType(Scrollable);
              if (scrollables.evaluate().isNotEmpty) {
                final scrollableState = tester.state<ScrollableState>(scrollables.first);
                scrollableState.position.jumpTo(entry.scrollTo!);
                await tester.pumpAndSettle();
              }
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

void _printWidgetValidate(PrintEntry entry, List<DeviceFrame> devices) {
  // Check 1: Size exceeds device frame dimensions
  if (entry.size != null) {
    for (final device in devices) {
      final exceedsWidth = entry.size!.width > device.size.width;
      final exceedsHeight = entry.size!.height > device.size.height;
      if (exceedsWidth || exceedsHeight) {
        final dims = <String>[];
        if (exceedsWidth) dims.add('width');
        if (exceedsHeight) dims.add('height');
        debugPrint(
          '⚠ Widget "\${entry.name}" size '
          '(\${entry.size!.width.toInt()}x\${entry.size!.height.toInt()}) '
          'exceeds device "\${device.name}" '
          '(\${device.size.width.toInt()}x\${device.size.height.toInt()}) '
          'on \${dims.join(" and ")}.\\n'
          '  The widget may overflow. Consider using a larger device or reducing the size.',
        );
      }
    }
  }

  // Check 2: Missing widget (SizedBox.shrink placeholder without states)
  if (entry.states == null && entry.widget is SizedBox) {
    final sizedBox = entry.widget as SizedBox;
    if (sizedBox.width == 0 && sizedBox.height == 0 &&
        sizedBox.child == null) {
      debugPrint(
        '⚠ Widget "\${entry.name}" appears to be a SizedBox.shrink() with no states.\\n'
        '  This entry may be misconfigured. Did you mean to use pages() or widgets() with states?',
      );
    }
  }
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
    'web_1366': DeviceFrame.web1366,
    'web_1440': DeviceFrame.web1440,
    'web_1920': DeviceFrame.web1920,
    'desktop_1440p': DeviceFrame.desktop1440p,
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
      final match = matchDeviceSuffix(baseName);
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
      final widgetName =
          widgetDir.uri.pathSegments.where((s) => s.isNotEmpty).last;

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

/// Parsed result of a custom device spec like "1440x900" or "my_name:1440x900@2".
class CustomDevice {
  const CustomDevice(this.name, this.width, this.height, this.pixelRatio);
  final String name;
  final double width;
  final double height;
  final double pixelRatio;
}

/// Parses custom device specs. Returns null for preset names.
///
/// Accepted formats:
/// - `1440x900` → name "custom", 1440x900, @1x
/// - `my_name:1440x900` → name "my_name", 1440x900, @1x
/// - `my_name:1440x900@2` → name "my_name", 1440x900, @2x
CustomDevice? parseCustomDevice(String spec) {
  final match =
      RegExp(r'^(?:(\w+):)?(\d+)x(\d+)(?:@([\d.]+))?$').firstMatch(spec);
  if (match == null) return null;

  final name = match.group(1) ?? 'custom';
  final width = double.parse(match.group(2)!);
  final height = double.parse(match.group(3)!);
  final pixelRatio = match.group(4) != null
      ? double.parse(match.group(4)!)
      : 1.0;

  return CustomDevice(name, width, height, pixelRatio);
}

/// Known device names sorted longest-first so that 'iphone_15_pro'
/// matches before 'iphone_15'.
///
/// This list must match DeviceFrame presets. A test in
/// test/device_frame_test.dart verifies they stay in sync.
///
/// NOTE: This is intentionally a plain string list (no Flutter import)
/// because the CLI binary must run with plain `dart`, not `flutter`.
/// Exposed for testing — verifies this list stays in sync with DeviceFrame.allPresets.
const knownDeviceNames = _knownDevices;

const _knownDevices = [
  'iphone_16_pro_max',
  'samsung_s24_ultra',
  'desktop_1440p',
  'iphone_15_pro',
  'pixel_8_pro',
  'samsung_s24',
  'ipad_pro_13',
  'ipad_pro_11',
  'iphone_14',
  'iphone_se',
  'ipad_mini',
  'ipad_air',
  'web_1920',
  'web_1440',
  'web_1366',
  'pixel_7',
  'compact',
  'medium',
  'small',
  'large',
];

/// Tries to split a flat filename base (e.g., 'login_page_iphone_15_pro')
/// into (entryName, deviceName) by matching known device suffixes.
///
/// Exposed as a top-level function so it can be tested directly.
(String, String)? matchDeviceSuffix(String baseName) {
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
