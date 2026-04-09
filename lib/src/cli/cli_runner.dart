import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'commands/compare_command.dart';
import 'commands/config_command.dart';
import 'commands/diagnose_command.dart';
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
    ..addCommand(CompareCommand())
    ..addCommand(SkillsCommand())
    ..addCommand(DiagnoseCommand());

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
  print_widget v0.3.1
  Capture Flutter widgets as PNGs for visual verification.

  Commands:
    print_widget init                        Set up in your project
    print_widget generate                    Generate all screenshots
    print_widget generate --name=login_page  Generate one entry
    print_widget generate --all-devices      All popular devices
    print_widget generate --flat             Save all PNGs flat (name_device.png)
    print_widget generate --delete-old       Clean output before generating
    print_widget generate --json             Output results as JSON
    print_widget list                        Show configured entries
    print_widget config                      View settings
    print_widget config --device=pixel_7     Change default device (current: $defaultDevice)
    print_widget compare                     Diff generated vs reference images (pixelmatch)
    print_widget compare --name=login        Diff a single entry
    print_widget diagnose                    Analyze widgets and report needed mock data
    print_widget diagnose --name=my_widget   Diagnose a specific widget
    print_widget skills                      Install AI assistant skills (Claude, Cursor, Codex)
    print_widget skills --install            Install all available skills
    print_widget skills --install=figma      Install a specific skill
    print_widget skills --only=stitch        Install only the stitch skill
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
    samsung_s24, samsung_s24_ultra, web_1366, web_1440, web_1920, desktop_1440p
  Custom:  --device=1440x900  --device=my_name:1440x900  --device=my_name:1440x900@2
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
print_widget generate --name=login_page  # one entry only (fast iteration)
print_widget generate --all-devices      # all popular devices
print_widget generate --flat             # flat output (name_device.png, no subfolders)
print_widget generate --delete-old       # clean output before generating
print_widget generate --json             # output results as JSON
print_widget generate --device=pixel_7   # override device (preset name)
print_widget generate --device=1440x900  # override device (custom size)
print_widget generate --device=web:1440x900@2  # custom name:WxH@pixelRatio
print_widget list                        # show entries
print_widget compare                     # pixelmatch diff all entries with refs
print_widget compare --name=login        # diff one entry
print_widget compare --threshold=0.98    # override per-region threshold
print_widget diagnose                    # analyze widgets, report needed mock data
print_widget diagnose --name=my_widget   # diagnose a specific widget
print_widget config --device=pixel_7     # change default device (current: $defaultDevice)
print_widget skills                      # install AI assistant skills (interactive)
print_widget skills --install            # install all available skills
print_widget skills --install=figma      # install specific skill
print_widget skills --only=stitch        # install only the stitch skill
print_widget skills --list               # list available skills
```

## Entry types (4 functions)

| Function | Layout | Use for |
|----------|--------|---------|
| `page()` | Full screen (fills device frame) | Screens, routes, full pages |
| `widget()` | Centered in Scaffold with optional `size:` | Components, cards, buttons |
| `pages()` | Multiple full-screen states | Same page, different data |
| `widgets()` | Multiple centered widget states | Same component, different states |

All 4 accept: `devices:`, `setup:`, `scrollExtent:`, `scrollTo:`, `appWrapper:`.

## Add a page (full screen)

In `$configPath`, add to `printList`:
```dart
page('login_page', const LoginPage()),
```

## Add a widget (centered, custom size)

```dart
widget('product_card', ProductCard(data: mock), size: Size(350, 400)),
```

**size vs DeviceFrame:** The `size` parameter sets a SizedBox constraint around the widget, centered in a Scaffold. The DeviceFrame sets the viewport and screenshot dimensions. Example: DeviceFrame 1440x900 + size 1100x280 = widget gets 1100x280, centered in 1440x900 screenshot.

## Multi-device

```dart
widget('card', MyCard(), devices: DeviceFrame.popular),
// popular = iphone_15_pro, pixel_7, ipad_pro_11
```

## Devices

**Mobile/Tablet:** iphone_se, iphone_14, iphone_15_pro, iphone_16_pro_max, ipad_mini, ipad_air, ipad_pro_11, ipad_pro_13, pixel_7, pixel_8_pro, samsung_s24, samsung_s24_ultra
**Web/Desktop:** web_1366 (1366x768), web_1440 (1440x900), web_1920 (1920x1080), desktop_1440p (2560x1440@2x)
**Groups:** DeviceFrame.popular, DeviceFrame.allPhones, DeviceFrame.allTablets, DeviceFrame.allWeb

**Custom device in Dart:**
```dart
const myDevice = DeviceFrame(name: 'ultrawide', size: Size(3440, 1440), pixelRatio: 2.0);
page('dashboard', DashboardPage(), devices: [myDevice]),
```

**Custom device from CLI:** `--device=1440x900`, `--device=my_name:1440x900`, `--device=my_name:1440x900@2`

## Font loading

Fonts load automatically via `loadPrintWidgetFonts()` in `flutter_test_config.dart` (created by `init`). Bundled Roboto + MaterialIcons are always available. Auto-detection includes:
- **Project fonts** from `pubspec.yaml` `fonts:` section
- **google_fonts** auto-detected — variant names (e.g. `Roboto_400regular`) registered automatically
- **Package fonts** auto-detected from ALL dependencies (transitive included)
- **Fallback scan** of `assets/fonts/` and `fonts/` directories for any remaining font files

CLI output shows a loaded font summary — read it to verify all fonts loaded correctly.

**Custom fonts** via `loadFonts` callback on PrintSession:
```dart
final printSession = PrintSession(
  loadFonts: () async {
    await loadCustomFonts({'MyFont': ['path/to/font.ttf']});
  },
);
```

**Custom fonts** (not in pubspec): add to `flutter_test_config.dart`:
```dart
await loadCustomFonts({'BrandFont': ['assets/fonts/BrandFont-Regular.ttf']});
```
**Package fonts:** `await loadPackageFonts('my_design_system');`

## Advanced: setup, scroll, providers

**Interact before capture** (tap tabs, enter text):
```dart
page('orders_tab', OrdersScreen(), setup: (tester) async {
  await tester.tap(find.text('Orders'));
  await tester.pumpAndSettle();
}),
```

**Capture long scrollable pages:**
```dart
page('long_page', LongPage(), scrollExtent: 3000),      // full height capture
page('page_bottom', LongPage(), scrollTo: 1500),         // scroll then capture
```

**Per-entry providers** (override session appWrapper):
```dart
page('admin', AdminPage(), appWrapper: (child) => MultiProvider(
  providers: [ChangeNotifierProvider.value(value: mockAdmin)],
  child: MaterialApp(home: child),
)),
```

**Diagnose widget constructors:**
```bash
print_widget diagnose                     # shows required params + mock suggestions
print_widget diagnose --name=my_widget    # single widget
```

## After generating

Read `$outputDir/manifest.json` to find PNGs:
```json
{"name": "login_page", "file": "login_page/iphone_15_pro.png", "device": "iphone_15_pro"}
```
View screenshot at: `$outputDir/<name>/<device>.png`

## Crops and per-region comparison

`PrintEntry` accepts `crops` (inline `Map<String, Rect>`) or `cropsFrom` (path to a JSON file matching smart-extract's `_index.json` format). When set, `generate` writes cropped PNGs alongside the golden at `$outputDir/<name>/crops/<region>.png`.

```dart
page('dashboard', DashboardPage(),
  crops: {
    'header': Rect.fromLTWH(0, 0, 1440, 80),
    'cards':  Rect.fromLTWH(60, 80, 1320, 350),
  },
)

// Or:
page('dashboard', DashboardPage(),
  cropsFrom: '$outputDir/dashboard/.reference/_index.json',
)
```

## Visual comparison with `print_widget compare`

Objective stop condition for the iteration loop. Runs pixelmatch via Node on each generated crop against its reference crop at `$outputDir/<name>/.reference/crops/*.png`, writes per-region heatmap PNGs, exit 0 on converged or 1 on below-threshold regions.

```bash
# one-time (in the Flutter project root):
npm install pixelmatch pngjs

# then after generating:
print_widget compare --name=<entry>
print_widget compare --threshold=0.98
print_widget compare --json
```

Configure in `print_widget.yaml`:
```yaml
reference_dir: .reference
compare_threshold: 0.95
```

## Lovable / web workflow

Install the extract skill alongside the main one:
```bash
print_widget skills --only=extract
```

Then: `smart-extract-design` captures the URL via Playwright → the AI copies crops to the reference dir → implements the Flutter widget → `print_widget generate` + `print_widget compare` drive the iteration loop with revert-on-regression until convergence.

## Known limitations

- **Images are auto-precached.** Asset and file images render correctly. Network images require internet access during `generate`.
- **No animations.** Screenshots capture the settled state after `pumpAndSettle()`.
- **No platform channels.** Plugins depending on native code won't work — use mocks.

## AI Skills

Install skills for Claude Code, Cursor, and Codex:
- `/print-widget-figma <url>` — Convert Figma designs to Flutter widgets with screenshot comparison loop
- `/print-widget-stitch <description>` — Generate Flutter screens via Stitch AI with visual verification

```bash
print_widget skills                      # interactive: detect tools, select skills
print_widget skills --install            # install all skills
print_widget skills --install=figma      # install Figma skill only
print_widget skills --only=stitch        # install Stitch skill only
```

## VS Code Extension

Preview screenshots in VS Code with sidebar, multi-device grid, and design comparison:
```bash
cd extensions/vscode && npm install && npm run build && npx @vscode/vsce package
code --install-extension print-widget-preview-*.vsix
```
Reference images saved to `$outputDir/<name>/.reference/<device>.png` are auto-detected for comparison.''',
  );
}
