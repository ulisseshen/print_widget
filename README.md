# print_widget

> **Beta** — This package is under active development. The API may change drastically between versions. That said, AI agents (Claude, Cursor, Codex) handle API changes gracefully by reading the `--llm-guide` output, so breaking changes won't break your workflow — just run `print_widget --llm-guide` and the AI adapts.

Capture Flutter widgets as PNG screenshots. Built for LLMs to see what they build.

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/login_page.png" width="200" alt="Login Page" />
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/home_page.png" width="200" alt="Home Page" />
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/product_card.png" width="200" alt="Product Card" />
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/stats_card.png" width="200" alt="Stats Card" />
</p>

## What it does

You define widgets. It generates PNGs. LLMs read the PNGs and iterate on the UI.

```
You write code → print_widget generates screenshots → LLM sees the result → fixes UI → repeat
```

## Two things in one

| What | Purpose | Install |
|------|---------|---------|
| **CLI** | Run `generate`, `list`, `config` | `dart pub global activate print_widget_flutter` |
| **Dev dependency** | Use `PrintSession`, `PrintEntry`, `Printable` in code | Added by `print_widget init` |

The CLI runs commands. The dev dependency gives you the Dart classes. `print_widget init` sets up both.

## Quick start

### 1. Install CLI (once)

```bash
dart pub global activate print_widget_flutter
```

> **Not yet on pub.dev?** Install directly from GitHub:
> ```bash
> dart pub global activate --source git https://github.com/ulisseshen/print_widget.git
> ```

### 2. Set up your project

```bash
cd my_flutter_app
print_widget init
```

### 3. Edit the config

Open `test/prints/print_config.dart`:

```dart
final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: MyAppTheme.light,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
);

final printList = <PrintEntry>[
  page('login_page', const LoginPage()),
  widget('product_card', ProductCard(title: 'Demo'), size: Size(350, 420)),

  // Multiple states of the same screen
  pages('sign_in', states: [
    state('empty', SignInScreen()),
    state('error', SignInScreen(initialError: 'Invalid email')),
  ]),
];
```

### 4. Generate

```bash
print_widget generate
```

Done. PNGs + `manifest.json` in your output directory.

## AI Assistant Onboarding

If you are an AI assistant (Claude Code, Cursor, Codex) setting up print_widget in a Flutter project, follow this complete onboarding flow:

### Step 1: Install the CLI globally

```bash
dart pub global activate --source git https://github.com/ulisseshen/print_widget.git
```

**Do NOT** add print_widget to the project's `pubspec.yaml`. It is a CLI tool, not a library dependency.

### Step 2: Run init and follow the onboarding output

```bash
cd <flutter_project>
print_widget init
```

The `init` command creates all needed files and prints **onboarding instructions specifically for you**. Read and follow them — they guide you through:
- Editing the config file with the project's theme and widgets
- Running `print_widget generate`
- Installing the AI skill (`print_widget skills --install=figma`)
- Detecting VS Code/Cursor and offering to install the preview extension

### Step 3: Read the compact reference

```bash
print_widget --llm-guide
```

This prints a condensed guide with project-specific paths, all CLI commands, entry types, device list, and the VS Code extension install instructions.

### Step 4: Add widgets to capture

Edit the config file (path shown in `init` output) and add the project's widgets:

```dart
final printList = <PrintEntry>[
  page('login_page', const LoginPage()),
  widget('product_card', ProductCard(data: mock), size: Size(350, 420)),
];
```

### Step 5: Generate and verify

```bash
print_widget generate
```

Read `manifest.json` in the output directory to find generated PNG paths. Read the PNGs to visually verify your UI work. Iterate until the screenshots match the design.

### What happens after onboarding

Once set up, you can:
- `/print-widget <figma-url>` — convert a Figma design to Flutter with screenshot comparison loop
- `print_widget generate --name=<entry>` — regenerate a single screenshot after code changes
- `print_widget generate --all-devices` — test responsive layouts across iPhone, Pixel, iPad
- Compare screenshots with design references in the VS Code extension sidebar

## CLI commands

```bash
print_widget init                        # Set up project
print_widget generate                    # Generate all screenshots
print_widget generate --name=login_page  # Generate one entry only
print_widget generate --device=pixel_7   # Override device (preset name)
print_widget generate --device=1440x900  # Override device (custom size)
print_widget generate --device=web:1440x900@2  # Custom name, size, pixel ratio
print_widget generate --all-devices      # All popular devices
print_widget generate --delete-old       # Clean regenerate
print_widget list                        # Show configured entries
print_widget config                      # View settings
print_widget config --device=pixel_7     # Change default device
print_widget skills                      # Install AI assistant skills (Claude, Cursor, Codex)
print_widget skills --list               # List available skills
print_widget --llm-guide                 # Print LLM reference
```

The `--name` flag is useful when iterating on a single widget. Instead of regenerating all screenshots, target just the one you changed:

```bash
print_widget generate --name=product_card
```

## Entry types

There are **4 entry functions** for adding items to `printList`:

| Function | What it does | Use for |
|----------|-------------|---------|
| `page('name', Widget())` | Renders as full-screen `home:` of the app wrapper | Screens, routes, full pages |
| `widget('name', Widget(), size: Size(w, h))` | Centers widget in `Scaffold > Center > SizedBox` | Components, cards, buttons |
| `pages('name', states: [...])` | Multiple full-screen states of the same page | Login empty/error/filled |
| `widgets('name', states: [...], size: Size(w, h))` | Multiple states of the same component | Button active/disabled/loading |

### Page vs Widget

| | `page()` | `widget()` |
|---|---|---|
| Layout | Full screen (fills device frame) | Centered in Scaffold |
| Use for | Screens, routes, full pages | Components, cards, buttons |
| Custom size | Uses device frame size | Optional `size:` constrains widget |
| Scroll capture | `scrollExtent: 3000` for tall pages | `scrollExtent:` works too |
| Tab/state control | `setup:` callback to tap tabs | `setup:` callback works too |
| Provider injection | `appWrapper:` per entry | `appWrapper:` per entry |

### Widget size vs device frame

When you use `widget()` with a `size:` parameter, the size controls the `SizedBox` constraints around your widget **inside** the device frame. The widget is centered in a `Scaffold`. The screenshot is always the full device frame size.

```dart
// DeviceFrame is 1440x900. Widget gets 1100x280 constraints, centered in the 1440x900 viewport.
widget('hero_banner', HeroBanner(), size: Size(1100, 280),
  devices: [DeviceFrame.web1440]),
```

This means:
- The **device frame** sets the overall viewport and screenshot dimensions
- The **size** parameter constrains and centers the widget within that viewport
- If `size` is omitted, the widget fills the entire scaffold (useful for full-width components)
- The output PNG is always the full device frame size, with the widget centered inside

## Grouped states

Capture multiple visual states of the same component:

```dart
pages('sign_in_screen', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(initialError: 'Invalid email')),
  state('filled', SignInScreen(initialEmail: 'user@test.com')),
])
```

Output naming via `StateOutputMode`:

| Mode | File path |
|------|-----------|
| `prefix` (default) | `sign_in_screen/empty_iphone_15_pro.png` |
| `suffix` | `sign_in_screen/iphone_15_pro_empty.png` |
| `folder` | `sign_in_screen/empty/iphone_15_pro.png` |

## Devices

### Mobile & tablet presets

```dart
DeviceFrame.iPhone15Pro   // 393x852 @3x
DeviceFrame.pixel7        // 412x915 @2.625x
DeviceFrame.iPadPro11     // 834x1194 @2x
DeviceFrame.popular       // [iPhone15Pro, pixel7, iPadPro11]
DeviceFrame.allPhones     // 8 phone devices
DeviceFrame.allTablets    // 4 tablet devices
```

### Web & desktop presets

```dart
DeviceFrame.web1366       // 1366x768 @1x  — most common laptop
DeviceFrame.web1440       // 1440x900 @1x  — common desktop
DeviceFrame.web1920       // 1920x1080 @1x — Full HD
DeviceFrame.desktop1440p  // 2560x1440 @2x — QHD / 1440p
DeviceFrame.allWeb        // [web1366, web1440, web1920, desktop1440p]
```

Use web presets for responsive layout testing:

```dart
page('dashboard', DashboardPage(), devices: DeviceFrame.allWeb),
```

### Custom device sizes

Create any device size in Dart:

```dart
const myDevice = DeviceFrame(
  name: 'ultrawide',
  size: Size(3440, 1440),
  pixelRatio: 2.0,
);

page('dashboard', DashboardPage(), devices: [myDevice]),
```

Or use custom sizes directly from the CLI without touching Dart code:

```bash
# Just dimensions (name defaults to "custom", pixel ratio to 1x)
print_widget generate --device=1440x900

# With a custom name
print_widget generate --device=my_monitor:1440x900

# With name and pixel ratio
print_widget generate --device=retina:1440x900@2
```

## Font loading

**Fonts load automatically.** When `print_widget init` sets up your project, it creates a `flutter_test_config.dart` that calls `loadPrintWidgetFonts()`. This loads:

1. **Bundled Roboto + MaterialIcons** -- always available, no setup needed
2. **Your project fonts** -- auto-detected from `pubspec.yaml` font declarations

You will see real text in screenshots, not Ahem black rectangles.

### Custom fonts

If you need to load fonts that are not declared in your `pubspec.yaml` (e.g., from a package or non-standard path), add them manually in your `flutter_test_config.dart`:

```dart
import 'package:print_widget_flutter/print_widget.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadPrintWidgetFonts();       // bundled + project fonts
  await loadCustomFonts({             // additional custom fonts
    'BrandFont': ['assets/fonts/BrandFont-Regular.ttf'],
    'BrandFont': ['assets/fonts/BrandFont-Bold.ttf'],
  });
  return testMain();
}
```

### Package fonts

Load fonts from a dependency package:

```dart
await loadPackageFonts('my_design_system');
```

## Advanced features

### Setup callback (interact before capture)

Tap tabs, enter text, open dialogs, or trigger any UI state before the screenshot:

```dart
page('orders_tab', OrdersScreen(),
  setup: (tester) async {
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
  },
)
```

Works on both entries and individual states:

```dart
pages('settings', states: [
  state('general', SettingsScreen()),
  state('notifications', SettingsScreen(),
    setup: (tester) async {
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
    },
  ),
])
```

### Scroll capture

Capture pages taller than one viewport:

```dart
// Capture the full scrollable extent (output PNG will be 1440x3000)
page('long_page', LongPage(), scrollExtent: 3000, devices: [DeviceFrame.web1440])

// Scroll to a specific offset before capturing
page('page_bottom', LongPage(), scrollTo: 1500)
```

### Per-entry provider injection

Override the session-level `appWrapper` for entries that need different providers:

```dart
page('admin_dashboard', AdminDashboard(),
  appWrapper: (child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: mockAdminProvider),
      ChangeNotifierProvider.value(value: mockOrdersProvider),
    ],
    child: MaterialApp(home: child),
  ),
  devices: [DeviceFrame.web1440],
)
```

### Widget diagnostics

Analyze widget constructors to find what mock data you need:

```bash
print_widget diagnose
print_widget diagnose --name=smart_summary
```

### JSON output

Get structured output for programmatic consumption:

```bash
print_widget generate --json
```

## Manifest

Generated `manifest.json` for LLM consumption:

```json
{
  "generatedAt": "2026-02-13T15:00:00Z",
  "screenshots": [
    {
      "name": "login_page",
      "type": "page",
      "file": "test/prints/output/login_page/iphone_15_pro.png",
      "device": "iphone_15_pro",
      "width": 393.0,
      "height": 852.0
    }
  ]
}
```

## LLM workflow

```
1. LLM implements LoginPage
2. LLM adds to printList: page('login_page', LoginPage())
3. LLM runs: print_widget generate --name=login_page
4. LLM reads manifest.json → finds PNG → views screenshot
5. LLM compares with design → iterates until it matches
```

## Works great with MCP tools

print_widget is designed to work with AI design tools via MCP (Model Context Protocol):

### Figma MCP
Autonomous design-match loop — fetch a Figma frame, implement the Flutter widget, generate a screenshot, compare pixels, fix differences, repeat until it matches.

```
AI fetches Figma design → builds widget → print_widget generate → compare → iterate
```

Reference images from Figma are saved to `.reference/` for automatic comparison in the VS Code extension.

- [Figma MCP Server](https://help.figma.com/hc/en-us/articles/32132100833559-Guide-to-the-Figma-MCP-server)

### Stitch (Google AI UI)
Generate UI screens with Stitch, then verify the Flutter implementation matches with print_widget screenshots. Stitch creates design screens from text prompts or code, and print_widget captures what the Flutter code actually renders — compare both to ensure pixel-perfect implementation.

```
Stitch generates design → AI implements in Flutter → print_widget generate → compare
```

- [Stitch MCP Setup](https://stitch.withgoogle.com/docs/mcp/setup)

## VS Code Extension

Preview and compare screenshots directly in VS Code.

- Sidebar tree view grouped by feature, state, and device
- Multi-device comparison grid
- Before/after diff with slider overlay
- Design reference comparison with similarity percentage (auto-detects `.reference/` images)

Requires Node.js 18+ to build from source:

```bash
cd extensions/vscode && npm install && npm run build && npx @vscode/vsce package
code --install-extension print-widget-preview-*.vsix
```

See [extensions/vscode/README.md](extensions/vscode/README.md) for full installation instructions (macOS, Linux, Windows).

## Docs

- [Architecture](doc/architecture.md)
- [Standalone test API](doc/standalone-api.md)
