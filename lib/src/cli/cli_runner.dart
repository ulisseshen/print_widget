import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'commands/config_command.dart';
import 'commands/generate_command.dart';
import 'commands/init_command.dart';
import 'commands/list_command.dart';

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
    ..addCommand(ConfigCommand());

  // No args or just --help → show branded help
  if (args.isEmpty) {
    _printBanner();
    stdout.writeln(runner.usage);
    return;
  }

  await runner.run(args);
}

void _printBanner() {
  stdout.writeln('');
  stdout.writeln('  print_widget v0.1.0');
  stdout.writeln('  Capture Flutter widgets as PNGs for visual verification.');
  stdout.writeln('');
  stdout.writeln('  Quick start:');
  stdout.writeln('    print_widget init       Set up in your project');
  stdout.writeln('    print_widget generate   Generate screenshots');
  stdout.writeln('    print_widget list       Show configured entries');
  stdout.writeln('    print_widget config     View or change settings');
  stdout.writeln('');
  stdout.writeln('  Flags:');
  stdout.writeln('    --llm-guide             Print LLM reference guide');
  stdout.writeln('');
  stdout.writeln('  Note: Asset and file images are auto-precached before capture.');
  stdout.writeln('  Network images require internet access during generation.');
  stdout.writeln('');
}

void _printLlmGuide() {
  var configPath = 'test/prints/print_config.dart';
  var outputDir = 'test/prints/output';
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

  stdout.writeln('''# print_widget

Screenshot Flutter widgets/pages as PNGs. Config: `$configPath`. Output: `$outputDir/`.

## Commands

```bash
print_widget generate                    # all entries
print_widget generate --name=login_page  # one entry
print_widget generate --all-devices      # all popular devices
print_widget list                        # show entries
print_widget config --device=pixel_7     # change default device (current: $defaultDevice)
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

## Devices

iphone_se, iphone_14, iphone_15_pro, iphone_16_pro_max, ipad_mini, ipad_air, ipad_pro_11, ipad_pro_13, pixel_7, pixel_8_pro, samsung_s24, samsung_s24_ultra''');
}
