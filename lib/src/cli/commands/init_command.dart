import 'dart:io';

import 'package:args/command_runner.dart';

class InitCommand extends Command<void> {
  InitCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output directory for generated screenshots.',
        defaultsTo: 'print_widget/output',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path for the Dart config file.',
        defaultsTo: 'print_widget/config.dart',
      )
      ..addFlag(
        'skip-dep',
        help: 'Skip adding print_widget_flutter as a dev dependency.',
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

    // 1. Add print_widget_flutter as dev dependency
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
      yamlFile.writeAsStringSync(
        _yamlTemplate(configFile: configPath, outputDir: outputDir),
      );
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

    // 6. Add output dir and temp files to .gitignore
    _addToGitignore(outputDir);
    _addToGitignore('.dart_tool/print_widget');

    // 7. Generate PRINT_WIDGET.md — LLM reference guide
    _createLlmGuide(configPath: configPath, outputDir: outputDir);

    stdout.writeln('');
    stdout.writeln('Setup complete!');
    stdout.writeln('');
    stdout.writeln('AI: Guide the user through these steps:');
    stdout.writeln('  1. Edit $configPath — set the app theme and add widgets');
    stdout.writeln('  2. Run: print_widget generate');
    stdout.writeln(
      '  3. Install the AI skill — ask the user which scope (project or user)',
    );
    stdout.writeln(
      '     and which AI tool (claude, cursor, codex), then run:',
    );
    stdout.writeln(
      '     print_widget skills --install=figma --scope=<scope> --tool=<tool>',
    );
    stdout.writeln(
      '  4. Ask the user: "Do you use VS Code or Cursor?"',
    );
    stdout.writeln(
      '     If yes, offer to install the Print Widget Preview extension',
    );
    stdout.writeln(
      '     for browsing screenshots, comparing devices, and Figma diff:',
    );
    stdout.writeln(
      '     cd extensions/vscode && npm install && npm run build && npx @vscode/vsce package',
    );
    stdout.writeln(
      '     code --install-extension print-widget-preview-*.vsix',
    );
    stdout.writeln(
      '     (requires Node.js 18+ and the print_widget repo cloned locally)',
    );
    stdout.writeln('');
    stdout.writeln('After setup, show the user what they can do:');
    stdout.writeln('');
    stdout.writeln('  /print-widget <figma-url> [instructions]');
    stdout.writeln(
      '    Build a Flutter widget from a Figma design, generate a screenshot,',
    );
    stdout.writeln(
      '    and iterate until it matches. The AI applies widget conventions,',
    );
    stdout.writeln(
      '    screen patterns, and visual review automatically.',
    );
    stdout.writeln('');
    stdout.writeln('  Examples:');
    stdout.writeln(
      '    /print-widget https://figma.com/design/abc123',
    );
    stdout.writeln(
      '    /print-widget screenshot.png "Use our blue theme"',
    );
    stdout.writeln(
      '    /print-widget "Login screen with email and password fields"',
    );
    stdout.writeln('');
    stdout.writeln('  Other workflows the user can ask for directly:');
    stdout.writeln(
      '    - "Review my screenshots" — visual audit of generated PNGs',
    );
    stdout.writeln(
      '    - "Iterate on login_page" — refine an existing widget visually',
    );
    stdout.writeln(
      '    - "Apply conventions to lib/features/home.dart" — refactor widget structure',
    );
  }

  Future<void> _addDevDependency() async {
    // Check if already in pubspec.yaml
    final pubspec = File('pubspec.yaml').readAsStringSync();
    if (pubspec.contains('print_widget_flutter:')) {
      stdout.writeln('[skip] print_widget_flutter already in pubspec.yaml');
      return;
    }

    stdout.writeln('[running] flutter pub add --dev print_widget_flutter');
    final result = await Process.run('flutter', [
      'pub',
      'add',
      '--dev',
      'print_widget_flutter',
    ], runInShell: true);

    if (result.exitCode != 0) {
      stderr.writeln(
        'Warning: Could not add print_widget_flutter as dev dependency.',
      );
      stderr.writeln(
        'Add it manually: flutter pub add --dev print_widget_flutter',
      );
      if (result.stderr.toString().isNotEmpty) {
        stderr.writeln(result.stderr);
      }
    } else {
      stdout.writeln('[added] print_widget_flutter as dev_dependency');
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
    file.writeAsStringSync(
      _llmGuideTemplate(configPath: configPath, outputDir: outputDir),
    );
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

String _yamlTemplate({required String configFile, required String outputDir}) =>
    '''# print_widget configuration
config_file: $configFile
output_dir: $outputDir
default_device: iphone_15_pro
manifest: true
''';

const _flutterTestConfigTemplate = '''import 'dart:async';
import 'package:print_widget_flutter/print_widget.dart';

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
print_widget skills                      # install AI assistant skills
print_widget skills --list               # list available skills
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

## Grouped states (multiple visual states of the same page/widget)

Use `pages()` / `widgets()` with `state()` to group visual states under one folder:
```dart
pages('sign_in_screen', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(initialError: 'Invalid email')),
  state('filled', SignInScreen(initialEmail: 'user@test.com')),
]),
```
Output depends on `stateOutputMode` set in `printSession`:
- `StateOutputMode.prefix` (default): `$outputDir/sign_in_screen/empty_<device>.png`
- `StateOutputMode.suffix`: `$outputDir/sign_in_screen/<device>_empty.png`
- `StateOutputMode.folder`: `$outputDir/sign_in_screen/empty/<device>.png`

For widgets with states:
```dart
widgets('status_badge', states: [
  state('active', StatusBadge(status: Status.active)),
  state('inactive', StatusBadge(status: Status.inactive)),
], size: Size(120, 40)),
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
Grouped states include a `"state"` field:
```json
{"name": "sign_in_screen", "state": "empty", "file": "sign_in_screen/empty_iphone_15_pro.png", "device": "iphone_15_pro"}
```
View screenshot at: `$outputDir/<name>/<device>.png` or with states depending on `stateOutputMode`

## Devices

`iphone_se`, `iphone_14`, `iphone_15_pro`, `iphone_16_pro_max`, `ipad_mini`, `ipad_air`, `ipad_pro_11`, `ipad_pro_13`, `pixel_7`, `pixel_8_pro`, `samsung_s24`, `samsung_s24_ultra`

## AI post-init workflow

After running `print_widget init`, guide the user through:

1. **Add widgets to config**: Scan `lib/` for `*_page.dart`, `*_screen.dart`, `*_widget.dart` files. Ask the user which ones to add to `$configPath` as `page()` or `widget()` entries.

2. **Install AI skills**: Ask the user:
   - Which skills to install: `figma`, `iterate`, `conventions`, `screen`, `review`
   - Which scope: `project` (current project) or `user` (all projects)
   - Then run: `print_widget skills --install=<skills> --scope=<scope>`

3. **Figma visual loop** (recommend if user works with designs):
   - Get the Figma design (screenshot or Figma MCP)
   - Build the Flutter widget to match
   - Run `print_widget generate --name=<entry>`
   - Read the generated PNG and compare with the design
   - Fix differences and regenerate until it matches

4. **Generate first screenshots**: Run `print_widget generate` and review the output.
''';

const _dartConfigTemplate = r"""import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';

final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    // TODO: Add your app theme here
    // theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
  // How state names appear in output files:
  // StateOutputMode.prefix  → empty_iphone_15_pro.png  (default)
  // StateOutputMode.suffix  → iphone_15_pro_empty.png
  // StateOutputMode.folder  → empty/iphone_15_pro.png
  // stateOutputMode: StateOutputMode.prefix,
);

final printList = <PrintEntry>[
  // Single-state entries:
  // page('login_page', const LoginPage()),
  // widget('product_card', ProductCard(product: mockProduct)),
  //
  // Grouped states (multiple visual states of the same page):
  // pages('sign_in_screen', states: [
  //   state('empty', SignInScreen()),
  //   state('error', SignInScreen(initialError: 'Invalid email')),
  //   state('filled', SignInScreen(initialEmail: 'user@test.com')),
  // ]),
];
""";
