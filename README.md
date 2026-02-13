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

## Output structure

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

5. LLM runs:  print_widget generate --name=login_page

6. LLM reads manifest.json -> finds PNG path -> views screenshot
   -> compares with Figma prototype -> iterates
```

## Docs

- [Architecture](docs/architecture.md) - why the CLI works the way it does, rendering pipeline, limitations
- [Standalone test API](docs/standalone-api.md) - lower-level API for writing Flutter tests directly
