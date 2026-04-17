import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'commands/compare_command.dart';
import 'commands/config_command.dart';
import 'commands/diagnose_command.dart';
import 'commands/extract_command.dart';
import 'commands/generate_command.dart';
import 'commands/init_command.dart';
import 'commands/list_command.dart';
import 'commands/scaffold_command.dart';
import 'commands/skills_command.dart';
import 'commands/snapshot_command.dart';
import 'commands/tokenize_command.dart';

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
    ..addCommand(ExtractCommand())
    ..addCommand(SnapshotCommand())
    ..addCommand(ScaffoldCommand())
    ..addCommand(TokenizeCommand())
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
  print_widget v0.7.0
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
    print_widget extract --url=<url>         Capture design + per-element spec via Playwright
    print_widget extract --config=states.json  Run a multi-state extraction
    print_widget snapshot --name=<entry>     Promote generated to reference (Flutter-native baseline)
    print_widget snapshot --all              Snapshot every entry's generated output
    print_widget scaffold --spec=<path>      Compile _spec.json to Flutter widget (literal values, no tokens)
    print_widget scaffold --spec=<path> --stdout  Print scaffold to stdout without writing
    print_widget tokenize --input=<scaffold.dart> --theme=<theme-ref.json>  Swap literals for design-system tokens
    print_widget tokenize --input=<scaffold.dart> --theme=<theme> --strategy=near  Fuzzy color match (ΔE tolerance)
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
print_widget extract --url=<url>         # Playwright-backed design extraction
print_widget extract --config=states.json --theme=theme-ref.json
print_widget extract --url=<url> --viewport=1440x2400 --output=print_widget/output/feature
print_widget extract --url=<url> --chrome-purge="footer:last-child" --force-font="Inter:wght@400;500;600"
print_widget snapshot --name=kpi_card     # promote generated → .reference/ (Flutter-native baseline)
print_widget snapshot --all               # snapshot every entry with a generated output
print_widget snapshot --name=kpi_card --force    # overwrite existing reference
print_widget scaffold --spec=<path>       # mechanical codegen: _spec.json → Flutter widget (literal values)
print_widget scaffold --spec=<path> --stdout     # print scaffold to stdout without writing
print_widget scaffold --spec=<path> --class-name=_FooScaffold --output=lib/scaffolds/foo.dart
print_widget tokenize --input=<scaffold.dart> --theme=<theme-ref.json>  # swap literals → DS tokens
print_widget tokenize --input=<scaffold> --theme=<theme> --strategy=near --tolerance=2.0
print_widget tokenize --input=<scaffold> --theme=<theme> --stdout --json
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
compare_threshold: 0.95              # default, Flutter-native references (after snapshot)
cross_engine_threshold: 0.88         # when reference is browser-originated (accounts for Skia vs Chromium text)
thresholds:                          # optional per-entry overrides
  home/atoms/kpi_card: 0.90
  home/molecules/complex_table: 0.85
```

**Threshold resolution** (first match wins):
1. `--threshold=<N>` CLI flag
2. `thresholds.<entry>` in yaml
3. `_origin.json` under the reference dir: `flutter` → `compare_threshold`, `browser` or missing → `cross_engine_threshold`

The `_origin.json` file is written automatically by `print_widget extract` (sets origin to `browser`) and `print_widget snapshot` (sets origin to `flutter`). The resolved threshold + source is printed in the per-entry output so you can see why a widget passed or failed.

## Snapshot (Flutter-native references with `print_widget snapshot`)

After browser-to-Flutter iteration converges — the visual audit passes and pixelmatch is near threshold — promote the current generated PNGs to the reference position. Future iterations compare Flutter-to-Flutter, eliminating the Skia vs Chromium text-rendering gap (~5–7% that's otherwise unfixable by code changes).

```bash
print_widget snapshot --name=kpi_card         # one entry; default_device from yaml
print_widget snapshot --name=kpi_card --device=pixel_7   # specific device
print_widget snapshot --all                   # every entry with a generated output
print_widget snapshot --name=kpi_card --force # overwrite existing reference
```

Copies `<outputDir>/<name>/<device>.png` and all `<outputDir>/<name>/crops/*.png` (diff PNGs excluded) into `<outputDir>/<name>/<referenceDir>/`. Writes `<referenceDir>/_origin.json` marking the reference as `flutter`-originated so Phase 3 per-entry thresholds can pick the right gate.

By default refuses to overwrite existing reference files. Pass `--force` to replace. Pair with `generate` and `compare` in the iteration loop: converge browser-ref → `snapshot` → keep iterating against the now-Flutter-native reference at the full threshold.

## Scaffold codegen with `print_widget scaffold`

Turns a per-element `_spec.json` (from `extract`) into a Flutter widget with **literal values** — no tokens, no custom DS components, no AI guessing. This is the "mechanical transcription" step of the two-pass architecture: the scaffold locks layout first, then `tokenize` (Phase 5) swaps literals for DS tokens.

```bash
# Auto-derive class name (`_KpiCardScaffold`) and output (`lib/scaffolds/kpi_card_scaffold.dart`):
print_widget scaffold --spec=print_widget/output/01-initial/02-kpi-card_spec.json

# Explicit class and output:
print_widget scaffold \\
  --spec=print_widget/output/.specs/kpi_card_spec.json \\
  --class-name=_KpiCardScaffold \\
  --output=lib/ui/features/home/widgets/kpi_card_scaffold.dart

# Print to stdout (dry-run):
print_widget scaffold --spec=<path> --stdout

# Overwrite existing file, JSON-mode:
print_widget scaffold --spec=<path> --force --json
```

**Emission rules (deterministic — same input yields the same output):**
- `display: flex, flexDirection: column` → `Column` (`row` default → `Row`)
- `gap: N` → `SizedBox(width/height: N)` interleaved between children
- `padding: {t,r,b,l}` → collapses to `EdgeInsets.all(N)`, `.symmetric(h, v)`, or `.fromLTRB(l, t, r, b)`
- `backgroundColor` + `borderRadius` + `boxShadow` → `Container(decoration: BoxDecoration(...))`. When a padding is also present, padding goes INSIDE the Container (CSS semantics).
- `borderRadius: "50%"` / `shape: circle` → `BoxShape.circle` (no `borderRadius:`)
- `text` + `typography` → `Text(..., style: TextStyle(...))` with literal color, font family, size, weight, `height = lineHeight / fontSize`
- `svgHtml` → `SvgPicture.string("...")` with triple single-quote delimiters (requires `flutter_svg` in the consumer's pubspec)
- `flexGrow: 1` → `Expanded(child: ...)`
- `overflow: hidden` + `textOverflow: ellipsis` → `TextOverflow.ellipsis, maxLines: 1`
- `position: absolute` children → parent becomes `Stack`, child becomes `Positioned`
- Unknown/grid → `Wrap` or fallback `SizedBox` with `// TODO:` marker (review needed)

**Color handling:** CSS `rgba(R,G,B,A)` and `#RRGGBBAA` are reordered to Flutter's alpha-first `Color(0xAARRGGBB)`. Example: `rgba(11, 162, 132, 0.12)` → `Color(0x1F0BA284)`. `transparent` / `rgba(0,0,0,0)` are omitted entirely — no `backgroundColor` property emitted.

**`const` propagation:** the default constructor is `const` unless the tree contains an `SvgPicture.string(...)`. In that case the class drops `const` because `SvgPicture.string` is not a const constructor.

**File header:** every generated file opens with a 7-line banner that records the source spec path, generation timestamp, and the exact `print_widget scaffold ...` command to regenerate.

See `doc/pipeline-gaps/scaffold.md` for the full rules table and the post-scaffold workflow (generate → compare → tokenize).

## Tokenize pass with `print_widget tokenize`

Phase 5. Takes a scaffold (literal Flutter source from `scaffold`) plus a `theme-ref.json` and produces the production widget with design-system tokens substituted. No AI in the loop — substitution rules are deterministic.

```bash
# Basic: exact color match (hex must be a key in theme colors.tokenMap):
print_widget tokenize \\
  --input=lib/scaffolds/kpi_card_scaffold.dart \\
  --theme=.claude/skills/print-widget-extract/theme-ref.json \\
  --output=lib/widgets/kpi_card.dart

# Fuzzy match: accept the nearest token within ΔE ≤ tolerance:
print_widget tokenize --input=<scaffold> --theme=<theme> --strategy=near --tolerance=2.0

# Dry-run to stdout; JSON report on stderr:
print_widget tokenize --input=<scaffold> --theme=<theme> --stdout --json
```

**Substitution rules (deterministic):**
- `Color(0xAARRGGBB)` where `#RRGGBB` ∈ `colors.tokenMap` → `context.customColors.<token>`; alpha < 0xFF wraps in `.withValues(alpha: <0.N>)` (not the deprecated `withOpacity`)
- `EdgeInsets.all(N)` / `.symmetric(h, v)` / `.fromLTRB(l, t, r, b)` — each numeric arg → `YHAppSpacing.sp<index>` from `spacing.scale`; per-arg FORCE on unmapped values
- `BorderRadius.circular(N)` → `BorderRadius.circular(YHAppCornerRadiusV2.r<index>)`; 9999 → `rfull` via `"9999": "full"` in the scale
- `TextStyle(fontFamily: 'Inter', fontSize, fontWeight, color, height, letterSpacing)` → `interText(size:, weight:, color:, height:, letterSpacing:)`; non-Inter TextStyles preserved but their inner color still tokenizes
- `const` propagation: dropped from the class constructor when any substitution introduces a non-const reference (`context.customColors.X` or `interText(...)`). SVG-driven drops from scaffold are preserved.
- Idempotency: running tokenize twice is an error — the tool detects `context.customColors.`, `YHAppSpacing.`, `YHAppCornerRadiusV2.`, or `interText(` in the input and refuses.

**FORCE comments** — when a literal can't be mapped (no token for that hex / spacing value / radius), the line is prefixed with `// FORCE: no token match for ... in ...`. The tokenize header reports the count; the `--json` output returns `{substitutions: [...], forced: [...], counts: {...}}`.

Theme-ref schema (extends the existing `extract` theme-ref):
```json
{
  "colors": { "accessor": "context.customColors", "tokenMap": {"#0BA284": "brand30"} },
  "spacing": { "class": "YHAppSpacing", "prefix": "sp", "scale": {"16": 4, "24": 6} },
  "radius":  { "class": "YHAppCornerRadiusV2", "prefix": "r", "scale": {"16": 4, "9999": "full"} },
  "typography": { "helper": "interText", "import": "package:yh_design_system/typography/inter_text.dart" }
}
```

See `doc/pipeline-gaps/tokenize.md` for the full reference.

## Lovable / web workflow

`print_widget extract` owns the whole Playwright runtime. First invocation installs Chromium under `.dart_tool/print_widget/extract-runtime/` (~60s); subsequent runs reuse the cache.

```bash
# Simplest: single URL, default viewport 1440x2400, default output path.
print_widget extract --url=https://example.com/

# Multi-state navigation via states.json (clicks, fills, waits).
print_widget extract --config=states.json --theme=theme-ref.json

# Strip platform UI (Lovable footer, cookie banners) inline.
print_widget extract --url=<url> --chrome-purge="footer:last-child" --chrome-purge="[class*='cookie']"

# Force-load fonts the page declares but never imports (silent Helvetica fallback bug).
print_widget extract --url=<url> --force-font="Inter:wght@400;500;600;700"
```

Output per state under `<output>/NN-<state-slug>/`:
- `fullpage.png`, `<NN>-<section>.png` — screenshots
- **`<NN>-<section>_spec.json`** — per-element structural spec (DOM tree with computed styles, typography, icons + outerHTML). This is the IR — use exact values from here, don't guess from pixels. Format: `doc/pipeline-gaps/spec-format.md`.
- `_index.json` — crop bounds + spec filename per crop
- `tokens.json` + `_DESIGN.md` — aggregate tokens + theme mapping

Install the `smart:extract-design` skill for guided navigation and theme mapping:
```bash
print_widget skills --only=extract
```

Full flow: `extract` captures the URL → crops + specs copied to `.reference/` → agent implements the Flutter widget reading `_spec.json` first (exact values) → `print_widget generate` + `print_widget compare` drive the iteration loop with revert-on-regression until convergence.

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
