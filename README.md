# print_widget

Capture Flutter widgets and pages as PNG screenshots for visual verification. Designed for LLMs to generate, compare, and iterate on UI during development.

## How it works

1. Install the CLI globally (once)
2. Run `print_widget init` in your project (sets up everything)
3. Edit the config to add your widgets with your real app theme
4. Run `print_widget generate` to get PNGs + a JSON manifest

Screenshots render exactly as they would in the real app (theme, fonts, layout).

## Install

Install the CLI globally (one time):

```bash
dart pub global activate print_widget
```

Make sure `~/.pub-cache/bin` is in your PATH.

## Quick start

### Step 1: Initialize your project

```bash
cd my_flutter_app
print_widget init
```

This does everything for you:
- Adds `print_widget` as a dev dependency in your `pubspec.yaml`
- Creates `test/flutter_test_config.dart` (font loading)
- Creates `print_widget.yaml` (project config)
- Creates `test/prints/print_config.dart` (widget list template)
- Creates `test/prints/output/` (output directory)
- Updates `.gitignore`

### Step 2: Edit the config

Open `test/prints/print_config.dart` and add your app theme + widgets:

```dart
import 'package:flutter/material.dart';
import 'package:print_widget/print_widget.dart';
import 'package:my_app/theme.dart';
import 'package:my_app/pages/login_page.dart';
import 'package:my_app/widgets/product_card.dart';

final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: MyAppTheme.light,
    debugShowCheckedModeBanner: false,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
  // stateOutputMode: StateOutputMode.prefix, // default
  // stateOutputMode: StateOutputMode.suffix,
  // stateOutputMode: StateOutputMode.folder,
);

final printList = <PrintEntry>[
  // Pages - render full screen
  page('login_page', const LoginPage()),
  page('home_page', const HomePage()),

  // Widgets - render centered, with custom size
  widget('product_card',
    ProductCard(title: 'Flutter Kit'),
    size: Size(350, 420),
  ),

  // Widget on multiple devices at once
  widget('responsive_card',
    ProductCard(title: 'Responsive'),
    devices: DeviceFrame.popular,
  ),

  // Grouped states - multiple visual states under one entry
  pages('sign_in_screen', states: [
    state('empty', SignInScreen()),
    state('error', SignInScreen(initialError: 'Invalid email')),
    state('filled', SignInScreen(initialEmail: 'user@test.com')),
  ]),
];
```

### Step 3: Generate

```bash
print_widget generate
```

Done. PNGs and `manifest.json` are in your output directory.

## CLI commands

```bash
# Set up everything in your project
print_widget init

# Generate all screenshots
print_widget generate

# Generate a specific widget only
print_widget generate --name=login_page

# Generate with a specific device
print_widget generate --device=pixel_7

# Generate on all popular devices
print_widget generate --all-devices

# Delete old screenshots before generating (clean regenerate)
print_widget generate --delete-old

# List configured entries
print_widget list
```

### `init` options

```bash
# Skip adding dev dependency (if already added)
print_widget init --skip-dep

# Custom output directory
print_widget init --output=screenshots

# Custom config file path
print_widget init --config=test/my_config.dart
```

## Two things, two purposes

| What | Purpose | How |
|------|---------|-----|
| **Global CLI** | Run commands (`generate`, `list`) | `dart pub global activate print_widget` |
| **Dev dependency** | Use Dart classes (`Printable`, `PrintSession`, etc.) in your code | Added automatically by `print_widget init` |

The CLI is for running. The dev dependency is for coding. `print_widget init` handles both.

## The `Printable` mixin

Mark widgets/pages so they carry their own screenshot metadata:

```dart
class LoginPage extends StatelessWidget with Printable {
  const LoginPage({super.key});

  @override
  String get printName => 'login_page';

  @override
  PrintType get printType => PrintType.page;

  @override
  Widget build(BuildContext context) { ... }
}
```

- **`PrintType.page`** - renders full screen (widget goes directly as `home:`)
- **`PrintType.widget`** - renders centered inside a Scaffold

## Page vs Widget rendering

| | Page | Widget |
|---|---|---|
| Layout | Full screen | Centered in Scaffold |
| Use for | Screens, routes | Components, cards, buttons |
| Custom size | Uses device size | Optional `size:` parameter |

## Grouped states

Use `pages()` / `widgets()` with `state()` to capture multiple visual states of the same screen or component:

```dart
// Multiple states of a page
pages('sign_in_screen', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(initialError: 'Invalid email')),
  state('filled', SignInScreen(initialEmail: 'user@test.com')),
]),

// Multiple states of a widget
widgets('status_badge', states: [
  state('active', StatusBadge(status: Status.active)),
  state('inactive', StatusBadge(status: Status.inactive)),
], size: Size(120, 40)),
```

The single-entry helpers `page()` / `widget()` remain unchanged and fully backwards compatible.

### `StateOutputMode`

Control how state names appear in the output filename via `stateOutputMode` on `PrintSession`:

```dart
final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(home: child),
  stateOutputMode: StateOutputMode.prefix, // default
);
```

| Mode | File path | Example |
|------|-----------|---------|
| `StateOutputMode.prefix` (default) | `<name>/<state>_<device>.png` | `sign_in_screen/empty_iphone_15_pro.png` |
| `StateOutputMode.suffix` | `<name>/<device>_<state>.png` | `sign_in_screen/iphone_15_pro_empty.png` |
| `StateOutputMode.folder` | `<name>/<state>/<device>.png` | `sign_in_screen/empty/iphone_15_pro.png` |

Entries without states are unaffected — always `<name>/<device>.png`.

## Output structure

With default `StateOutputMode.prefix`:

```
test/prints/output/
  login_page/
    iphone_15_pro.png
  product_card/
    iphone_15_pro.png
  responsive_card/
    iphone_15_pro.png
    pixel_7.png
    ipad_pro_11.png
  sign_in_screen/
    empty_iphone_15_pro.png
    error_iphone_15_pro.png
    filled_iphone_15_pro.png
  manifest.json
```

## Manifest JSON

The manifest is designed for LLM consumption:

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
      "height": 852.0,
      "widthPx": 1179,
      "heightPx": 2556
    },
    {
      "name": "sign_in_screen",
      "type": "page",
      "state": "empty",
      "file": "test/prints/output/sign_in_screen/empty_iphone_15_pro.png",
      "device": "iphone_15_pro",
      "width": 393.0,
      "height": 852.0,
      "widthPx": 1179,
      "heightPx": 2556
    }
  ]
}
```

## Available devices

| Device | Size | Pixel ratio |
|--------|------|-------------|
| `DeviceFrame.iPhoneSE` | 375x667 | 2.0x |
| `DeviceFrame.iPhone14` | 390x844 | 3.0x |
| `DeviceFrame.iPhone15Pro` | 393x852 | 3.0x |
| `DeviceFrame.iPhone16ProMax` | 440x956 | 3.0x |
| `DeviceFrame.iPadMini` | 744x1133 | 2.0x |
| `DeviceFrame.iPadAir` | 820x1180 | 2.0x |
| `DeviceFrame.iPadPro11` | 834x1194 | 2.0x |
| `DeviceFrame.iPadPro13` | 1024x1366 | 2.0x |
| `DeviceFrame.pixel7` | 412x915 | 2.625x |
| `DeviceFrame.pixel8Pro` | 448x998 | 3.0x |
| `DeviceFrame.samsungS24` | 360x780 | 3.0x |
| `DeviceFrame.samsungS24Ultra` | 412x915 | 3.0x |

**Preset groups:**
- `DeviceFrame.popular` - iPhone 15 Pro, Pixel 7, iPad Pro 11
- `DeviceFrame.allPhones` - all 8 phone devices
- `DeviceFrame.allTablets` - all 4 tablet devices

## AppWrapper helper

For quick setup without writing a full MaterialApp lambda:

```dart
final printSession = PrintSession(
  appWrapper: appWrapperFromMaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    locale: Locale('pt', 'BR'),
  ),
);
```

## LLM workflow

```
1. Dev installs once:  dart pub global activate print_widget

2. Dev sets up project: print_widget init
                        -> edits print_config.dart with app theme

3. LLM implements LoginPage with `with Printable`

4. LLM adds to printList:
   page('login_page', const LoginPage())
   — or grouped states:
   pages('login_page', states: [
     state('empty', LoginPage()),
     state('filled', LoginPage(email: 'test@test.com')),
   ])

5. LLM runs:  print_widget generate --name=login_page

6. LLM reads manifest.json -> finds PNG path -> views screenshot
   -> compares with Figma prototype -> iterates
```

## Figma MCP match loop

When the LLM has access to a [Figma MCP server](https://github.com/nichochar/figma-mcp), it can run an autonomous design-match loop — fetching the original design from Figma, implementing it, taking a screenshot, comparing both images, and iterating until they match.

### Prerequisites

- Figma MCP server configured in your editor (Cursor, VS Code, etc.)
- `print_widget init` already run in the project
- The Figma file URL or node ID for the target design

### The loop

```
┌─────────────────────────────────────────────────────┐
│  1. FETCH — LLM uses Figma MCP to get the design   │
│     • get_file or get_node_images for the screen    │
│     • extracts colors, spacing, typography, layout  │
│                                                     │
│  2. IMPLEMENT — LLM writes the Flutter widget/page  │
│     • uses the app theme from printSession          │
│     • adds entry to printList                       │
│                                                     │
│  3. CAPTURE — LLM runs print_widget generate        │
│     • gets a real PNG rendered with the app theme    │
│                                                     │
│  4. COMPARE — LLM views both images side by side    │
│     • Figma screenshot (from MCP) vs generated PNG  │
│     • identifies mismatches: spacing, colors, sizes │
│                                                     │
│  5. ITERATE — LLM fixes the differences             │
│     • adjusts code → re-generates → re-compares     │
│     • repeats until the output matches the design   │
└─────────────────────────────────────────────────────┘
```

### Example prompts

**Implement a full screen from Figma (with states)**

> Implement the sign-in screen from this Figma file: `<figma-url>`
>
> Use Figma MCP to fetch the design. Implement it as a Flutter page.
> Add it to `printList` using `pages()` with states for empty, error, and filled.
> Run `print_widget generate` and compare your screenshot against the Figma design.
> Keep iterating until they match.

**Pixel-match a single component**

> Fetch the product card component from Figma node `<node-id>` in file `<figma-url>`.
> Implement it as a reusable widget. Add it to `printList` with `widget()` using `size: Size(350, 420)`.
> Generate the screenshot, compare it with the Figma image, and fix every difference you find — colors, border radius, font weight, spacing. Iterate until they are visually identical.

**Batch-implement a whole Figma page with all variants**

> This Figma page has the onboarding flow: `<figma-url>`
>
> It contains 4 screens: welcome, name_input, plan_selection, and confirmation.
> Fetch each screen from Figma, implement them as Flutter pages, and add them all to `printList`.
> For name_input, create states: empty, filled, and error.
> Generate all screenshots and compare each one against its Figma counterpart. Fix mismatches one screen at a time.

**Refine an existing screen that drifted from the design**

> The home screen implementation has drifted from the Figma design.
> Fetch the latest Figma design from `<figma-url>` node `<node-id>`.
> Generate a screenshot of the current HomeScreen with `print_widget generate --name=home_screen`.
> Compare both images. List every visual difference you find, then fix them one by one. After each fix, re-generate and re-compare until they match.

**Responsive check across devices**

> Fetch the dashboard screen from Figma: `<figma-url>`
> Figma has frames for iPhone 15 Pro, Pixel 7, and iPad Pro 11.
> Implement the DashboardScreen and add it to `printList` with `devices: DeviceFrame.popular`.
> Generate screenshots for all 3 devices. Compare each one against the matching Figma frame and iterate until all 3 match.

**Extract design tokens and build the theme first**

> Before implementing any screens, fetch the Figma file `<figma-url>` and extract the design tokens: color palette, text styles, spacing scale, and border radii.
> Create a `lib/theme.dart` with a ThemeData that matches the Figma tokens exactly.
> Set it as the theme in `printSession.appWrapper`.
> Then implement the login screen, generate a screenshot, and compare with the Figma design.

### What the LLM does (step by step)

```
1. Figma MCP: get_file({ fileKey: "abc123" })
   → retrieves the design tree (nodes, styles, colors)

2. Figma MCP: get_node_images({ fileKey: "abc123", nodeId: "42:1" })
   → gets a PNG of the original Figma design

3. Implements SignInScreen in lib/pages/sign_in_screen.dart

4. Adds to print_config.dart:
   pages('sign_in_screen', states: [
     state('empty', SignInScreen()),
     state('error', SignInScreen(initialError: 'Invalid email')),
     state('filled', SignInScreen(initialEmail: 'user@test.com')),
   ]),

5. Runs: print_widget generate --name=sign_in_screen
   → produces:
     sign_in_screen/empty_iphone_15_pro.png
     sign_in_screen/error_iphone_15_pro.png
     sign_in_screen/filled_iphone_15_pro.png

6. Reads the generated PNG and compares with the Figma image
   → "The button padding is 12px, Figma shows 16px. Fixing..."

7. Fixes code → re-generates → re-compares

8. Repeats until satisfied
```

### Tips for best results

- **Match the device size to Figma's frame** — if the Figma frame is 393x852 (iPhone 15 Pro), use `DeviceFrame.iPhone15Pro` so the comparison is pixel-accurate
- **Use states for form screens** — designers often create variants (empty, filled, error); `pages()` + `state()` maps directly to that
- **One screen at a time** — use `--name=` to generate only the screen being iterated on, keeping the feedback loop fast
- **Let the LLM read the Figma styles** — the MCP provides actual color/font values, so the LLM can use exact tokens instead of eyeballing

## Docs

- [Architecture](doc/architecture.md) - why the CLI works the way it does, rendering pipeline, limitations
- [Standalone test API](doc/standalone-api.md) - lower-level API for writing Flutter tests directly
