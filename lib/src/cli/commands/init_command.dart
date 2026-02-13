import 'dart:io';

import 'package:args/command_runner.dart';

class InitCommand extends Command<void> {
  InitCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output directory for generated screenshots.',
        defaultsTo: 'test/prints/output',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path for the Dart config file.',
        defaultsTo: 'test/prints/print_config.dart',
      )
      ..addFlag(
        'skip-dep',
        help: 'Skip adding print_widget as a dev dependency.',
        negatable: false,
      );
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Set up print_widget in your project (adds dev dependency, creates config files).';

  @override
  Future<void> run() async {
    final outputDir = argResults!['output'] as String;
    final configPath = argResults!['config'] as String;
    final skipDep = argResults!['skip-dep'] as bool;

    // 0. Check we're in a Flutter project
    if (!File('pubspec.yaml').existsSync()) {
      stderr.writeln('No pubspec.yaml found in the current directory.');
      stderr.writeln('Run this command from the root of your Flutter project.');
      exitCode = 1;
      return;
    }

    stdout.writeln('Setting up print_widget...');
    stdout.writeln('');

    // 1. Add print_widget as dev dependency
    if (!skipDep) {
      await _addDevDependency();
    }

    // 2. Create flutter_test_config.dart
    _createFlutterTestConfig();

    // 3. Create print_widget.yaml
    final yamlFile = File('print_widget.yaml');
    if (yamlFile.existsSync()) {
      stdout.writeln('[skip] print_widget.yaml already exists');
    } else {
      yamlFile.writeAsStringSync(_yamlTemplate(
        configFile: configPath,
        outputDir: outputDir,
      ));
      stdout.writeln('[created] print_widget.yaml');
    }

    // 4. Create Dart config file
    final configFile = File(configPath);
    if (configFile.existsSync()) {
      stdout.writeln('[skip] $configPath already exists');
    } else {
      configFile.parent.createSync(recursive: true);
      configFile.writeAsStringSync(_dartConfigTemplate);
      stdout.writeln('[created] $configPath');
    }

    // 5. Create output directory
    final outDir = Directory(outputDir);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
      stdout.writeln('[created] $outputDir/');
    }

    // 6. Add output dir to .gitignore
    _addToGitignore(outputDir);

    // 7. Generate PRINT_WIDGET.md — LLM reference guide
    _createLlmGuide(configPath: configPath, outputDir: outputDir);

    stdout.writeln('');
    stdout.writeln('Done! Next steps:');
    stdout.writeln('  1. Edit $configPath — add your app theme and widgets');
    stdout.writeln('  2. Run: print_widget generate');
  }

  Future<void> _addDevDependency() async {
    // Check if already in pubspec.yaml
    final pubspec = File('pubspec.yaml').readAsStringSync();
    if (pubspec.contains('print_widget:')) {
      stdout.writeln('[skip] print_widget already in pubspec.yaml');
      return;
    }

    stdout.writeln('[running] flutter pub add --dev print_widget');
    final result = await Process.run(
      'flutter',
      ['pub', 'add', '--dev', 'print_widget'],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      stderr.writeln('Warning: Could not add print_widget as dev dependency.');
      stderr.writeln('Add it manually: flutter pub add --dev print_widget');
      if (result.stderr.toString().isNotEmpty) {
        stderr.writeln(result.stderr);
      }
    } else {
      stdout.writeln('[added] print_widget as dev_dependency');
    }
  }

  void _createFlutterTestConfig() {
    final file = File('test/flutter_test_config.dart');
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      if (content.contains('loadPrintWidgetFonts')) {
        stdout.writeln('[skip] test/flutter_test_config.dart already set up');
        return;
      }
      // File exists but doesn't have our font loading — warn the user
      stdout.writeln(
        '[warn] test/flutter_test_config.dart exists but does not call '
        'loadPrintWidgetFonts(). Add it manually:\n'
        '       await loadPrintWidgetFonts();',
      );
      return;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_flutterTestConfigTemplate);
    stdout.writeln('[created] test/flutter_test_config.dart');
  }

  void _createLlmGuide({
    required String configPath,
    required String outputDir,
  }) {
    final file = File('PRINT_WIDGET.md');
    if (file.existsSync()) {
      stdout.writeln('[skip] PRINT_WIDGET.md already exists');
      return;
    }
    file.writeAsStringSync(_llmGuideTemplate(
      configPath: configPath,
      outputDir: outputDir,
    ));
    stdout.writeln('[created] PRINT_WIDGET.md');
  }

  void _addToGitignore(String outputDir) {
    final gitignore = File('.gitignore');
    if (!gitignore.existsSync()) return;

    final content = gitignore.readAsStringSync();
    if (content.contains(outputDir)) return;

    gitignore.writeAsStringSync(
      '\n# print_widget generated screenshots\n$outputDir/\n',
      mode: FileMode.append,
    );
    stdout.writeln('[updated] .gitignore — added $outputDir/');
  }
}

String _yamlTemplate({
  required String configFile,
  required String outputDir,
}) =>
    '''# print_widget configuration
config_file: $configFile
output_dir: $outputDir
default_device: iphone_15_pro
manifest: true
''';

const _flutterTestConfigTemplate = '''import 'dart:async';
import 'package:print_widget/print_widget.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadPrintWidgetFonts();
  return testMain();
}
''';

String _llmGuideTemplate({
  required String configPath,
  required String outputDir,
}) =>
    '''# print_widget

Screenshot Flutter widgets/pages as PNGs. Config: `$configPath`. Output: `$outputDir/`.

## Generate screenshots

```bash
print_widget generate                    # all entries
print_widget generate --name=login_page  # one entry
print_widget generate --all-devices      # all popular devices
print_widget list                        # show entries
print_widget config --device=pixel_7     # change default device
```

## Add a page (full screen)

In `$configPath`, add to `printList`:
```dart
page('login_page', const LoginPage()),
```

## Add a widget (centered, custom size)

```dart
widget('product_card', ProductCard(data: mock), size: Size(350, 400)),
```

## Multi-device

```dart
widget('card', MyCard(), devices: DeviceFrame.popular),
// popular = iphone_15_pro, pixel_7, ipad_pro_11
```

## After generating

Read `$outputDir/manifest.json` to find PNGs:
```json
{"name": "login_page", "file": "login_page/iphone_15_pro.png", "device": "iphone_15_pro"}
```
View screenshot at: `$outputDir/<name>/<device>.png`

## Devices

`iphone_se`, `iphone_14`, `iphone_15_pro`, `iphone_16_pro_max`, `ipad_mini`, `ipad_air`, `ipad_pro_11`, `ipad_pro_13`, `pixel_7`, `pixel_8_pro`, `samsung_s24`, `samsung_s24_ultra`
''';

const _dartConfigTemplate = r"""import 'package:flutter/material.dart';
import 'package:print_widget/print_widget.dart';

final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    // TODO: Add your app theme here
    // theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
);

final printList = <PrintEntry>[
  // Add your widgets/pages here:
  // page('login_page', const LoginPage()),
  // widget('product_card', ProductCard(product: mockProduct)),
];
""";
