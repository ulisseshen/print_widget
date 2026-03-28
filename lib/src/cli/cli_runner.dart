import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'commands/config_command.dart';
import 'commands/generate_command.dart';
import 'commands/init_command.dart';
import 'commands/list_command.dart';
import 'commands/skills_command.dart';

Future<void> runPrintWidgetCli(List<String> args) async {
  // Handle --llm-guide before CommandRunner (global flag)
  if (args.contains('--llm-guide')) {
    _printLlmGuide();
    return;
  }

  final runner = CommandRunner<void>(
    'print_widget',
    'Capture Flutter widgets as PNG screenshots for LLM visual verification.',
  )
    ..addCommand(InitCommand())
    ..addCommand(GenerateCommand())
    ..addCommand(ListCommand())
    ..addCommand(ConfigCommand())
    ..addCommand(SkillsCommand());

  // No args or just --help → show branded help
  if (args.isEmpty) {
    _printBanner();
    stdout.writeln(runner.usage);
    return;
  }

  await runner.run(args);
}

void _printBanner() {
  var configPath = 'print_widget/config.dart';
  var outputDir = 'print_widget/output';
  var defaultDevice = 'iphone_15_pro';

  final yamlFile = File('print_widget.yaml');
  if (yamlFile.existsSync()) {
    try {
      final yaml = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
      configPath = (yaml['config_file'] as String?) ?? configPath;
      outputDir = (yaml['output_dir'] as String?) ?? outputDir;
      defaultDevice = (yaml['default_device'] as String?) ?? defaultDevice;
    } catch (_) {}
  }

  stdout.writeln('''
  print_widget v0.1.0
  Capture Flutter widgets as PNGs for visual verification.

  Commands:
    print_widget init                        Set up in your project
    print_widget generate                    Generate all screenshots
    print_widget generate --name=login_page  Generate one entry
    print_widget generate --all-devices      All popular devices
    print_widget generate --flat             Save all PNGs flat (name_device.png)
    print_widget generate --delete-old       Clean output before generating
    print_widget list                        Show configured entries
    print_widget config                      View settings
    print_widget config --device=pixel_7     Change default device (current: $defaultDevice)
    print_widget skills                      Install AI assistant skills (Claude, Cursor, Codex)
    print_widget skills --list               List available skills

  Config: $configPath   Output: $outputDir/

  Add a page (full screen) to printList:
    page('login_page', const LoginPage()),

  Add a widget (centered, custom size):
    widget('product_card', ProductCard(data: mock), size: Size(350, 400)),

  Multi-device:
    widget('card', MyCard(), devices: DeviceFrame.popular),

  After generating, read $outputDir/manifest.json to find PNGs.

  Limitations:
    - Images are auto-precached. Network images need internet during generate.
    - No animations (captures settled state after pumpAndSettle).
    - No platform channels (use mocks for native plugins).

  Devices: iphone_se, iphone_14, iphone_15_pro, iphone_16_pro_max,
    ipad_mini, ipad_air, ipad_pro_11, ipad_pro_13, pixel_7, pixel_8_pro,
    samsung_s24, samsung_s24_ultra
''');
}

void _printLlmGuide() {
  var configPath = 'print_widget/config.dart';
  var outputDir = 'print_widget/output';
  var defaultDevice = 'iphone_15_pro';

  // Read project-specific paths from print_widget.yaml if available
  final yamlFile = File('print_widget.yaml');
  if (yamlFile.existsSync()) {
    try {
      final yaml = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
      configPath = (yaml['config_file'] as String?) ?? configPath;
      outputDir = (yaml['output_dir'] as String?) ?? outputDir;
      defaultDevice = (yaml['default_device'] as String?) ?? defaultDevice;
    } catch (_) {
      // Use defaults on parse error
    }
  }

  stdout.writeln(
    '''# print_widget

Screenshot Flutter widgets/pages as PNGs. Config: `$configPath`. Output: `$outputDir/`.

## Commands

```bash
print_widget generate                    # all entries
print_widget generate --name=login_page  # one entry
print_widget generate --all-devices      # all popular devices
print_widget generate --flat             # flat output (name_device.png, no subfolders)
print_widget generate --delete-old       # clean output before generating
print_widget list                        # show entries
print_widget config --device=pixel_7     # change default device (current: $defaultDevice)
print_widget skills                      # install AI assistant skills (interactive)
print_widget skills --install=figma      # install specific skill
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

## Known limitations

- **Images are auto-precached.** Asset and file images render correctly. Network images require internet access during `generate`.
- **No animations.** Screenshots capture the settled state after `pumpAndSettle()`.
- **No platform channels.** Plugins depending on native code won't work — use mocks.

## VS Code Extension

Preview screenshots in VS Code with sidebar, multi-device grid, and design comparison:
```bash
cd extensions/vscode && npm install && npm run build && npx @vscode/vsce package
code --install-extension print-widget-preview-*.vsix
```
Reference images saved to `$outputDir/<name>/.reference/<device>.png` are auto-detected for comparison.

## Devices

iphone_se, iphone_14, iphone_15_pro, iphone_16_pro_max, ipad_mini, ipad_air, ipad_pro_11, ipad_pro_13, pixel_7, pixel_8_pro, samsung_s24, samsung_s24_ultra''',
  );
}
