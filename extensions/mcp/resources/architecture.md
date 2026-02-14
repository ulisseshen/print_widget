# print_widget — Architecture

## Two Packages, One Tool

print_widget serves two purposes:

| Role | What it provides | How it's used |
|------|-----------------|---------------|
| **Global CLI** | `print_widget init`, `generate`, `list` commands | `dart pub global activate print_widget` |
| **Dev dependency** | Dart classes: `Printable`, `PrintSession`, `PrintEntry`, `DeviceFrame`, etc. | `flutter pub add --dev print_widget` |

The CLI is what you run. The dev dependency is what you import in Dart code. `print_widget init` handles adding the dev dependency automatically.

## Why `flutter test` Internally?

Flutter can only render widgets inside the test framework. There is no headless Flutter renderer available outside of tests. The rendering pipeline depends on:

- `WidgetTester` to pump widgets into a virtual screen
- `TestFlutterView` to configure surface size and pixel ratio
- `matchesGoldenFile()` to capture the rendered frame as a PNG

Any tool that wants to screenshot Flutter widgets **must** run inside `flutter test`.

## Pipeline

```
User runs:     print_widget generate
                        |
                        v
CLI reads:     print_widget.yaml -> finds config_file path
                        |
                        v
CLI generates: .dart_tool/print_widget/print_test.dart
               (imports user's config.dart)
                        |
                        v
CLI executes:  flutter test --update-goldens .dart_tool/print_widget/print_test.dart
                        |
                        v
Flutter test:  Pumps each widget -> renders -> saves PNGs via matchesGoldenFile()
                        |
                        v
CLI outputs:   PNGs in output_dir/ + manifest.json
```

## Rendering Modes

### Page rendering (`PrintType.page`)

Pages represent full-screen routes. The widget is passed directly to AppWrapper:

```
AppWrapper(child: LoginPage())
  -> MaterialApp(theme: ..., home: LoginPage())
```

The page fills the entire device screen.

### Widget rendering (`PrintType.widget`)

Widgets represent UI components (cards, buttons, etc). They are wrapped in a Scaffold with Center:

```
AppWrapper(child: Scaffold(body: Center(child: ProductCard())))
  -> MaterialApp(theme: ..., home: Scaffold(body: Center(child: ProductCard())))
```

### Size Behavior

| Type | Size source | Behavior |
|------|------------|----------|
| Page | Device frame size | Widget fills the entire screen |
| Widget (no `size:`) | Device frame size | Widget is centered in full device screen |
| Widget (with `size:`) | Custom `Size` | Surface is set to that exact size |

## AppWrapper

The `AppWrapper` wraps every widget/page in the app's real shell:

```dart
typedef AppWrapper = Widget Function(Widget child);
```

This is what makes screenshots look like the real app. The wrapper typically provides:

- **Theme** (colors, typography, shape)
- **Localizations** (translations, date formats)
- **Providers** (state management, DI)
- **MediaQuery** overrides
- **Navigator** (for pages that depend on navigation context)

## Font Loading

Flutter test renders text as blank rectangles by default (no fonts loaded). print_widget bundles three fonts:

- **Roboto-Regular.ttf** — default Material text font
- **Roboto-Bold.ttf** — bold variant
- **MaterialIcons-Regular.otf** — Material icons

`loadPrintWidgetFonts()` also auto-detects fonts declared in the project's `pubspec.yaml` and loads them. The generated test file includes setup that calls `loadPrintWidgetFonts()` before any tests run.

Additional font loading:
- `loadCustomFonts()` — load fonts from explicit file paths
- `loadPackageFonts()` — load fonts from a package dependency's pubspec.yaml

## Config File Relationship

```
print_widget.yaml          (YAML - project-level settings)
  |-- config_file: ------> print_widget/config.dart  (Dart - runtime config)
  |                           |-- printSession (AppWrapper + defaults)
  |                           +-- printList (entries to capture)
  |-- output_dir: --------> print_widget/output/  (PNGs + manifest)
  |-- default_device:       iphone_15_pro
  +-- manifest:             true
```

`print_widget.yaml` is read by the CLI at build time.
`config.dart` is executed by Flutter test at runtime (it's real Dart code that instantiates widgets).

This separation exists because:
- YAML is easy for CLIs to parse and for users to edit
- Dart is required for widget instantiation (you can't describe a Flutter widget tree in YAML)

## Limitations

1. **Requires Flutter SDK** — the host machine must have Flutter installed (the CLI shells out to `flutter test`)
2. **No animations** — screenshots capture the settled state after `pumpAndSettle()`
3. **Network images** — asset and file images are auto-precached; network images need internet during generate
4. **No platform channels** — plugins that depend on native code won't work (use mocks)
5. **Single frame** — each entry produces one PNG per device (no multi-state captures)
