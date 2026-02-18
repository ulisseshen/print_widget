# Architecture

This document explains the internal design decisions of print_widget and the constraints that shaped them.

## Two packages, one tool

print_widget serves two purposes:

| Role | What it provides | How it's used |
|------|-----------------|---------------|
| **Global CLI** | `print_widget init`, `generate`, `list` commands | `dart pub global activate print_widget` |
| **Dev dependency** | Dart classes: `Printable`, `PrintSession`, `PrintEntry`, `DeviceFrame`, etc. | `flutter pub add --dev print_widget` |

The **CLI** is what you run. The **dev dependency** is what you import in your Dart code. `print_widget init` handles adding the dev dependency automatically, so the user only needs to run `dart pub global activate` once.

Why not just one? The CLI needs to be available globally (so you can run `print_widget generate` from any project). But the Dart classes need to be in `pubspec.yaml` so the compiler can resolve `import 'package:print_widget/...'` in your config and widget files.

## Why does the CLI run `flutter test` internally?

Flutter **can only render widgets inside the test framework**. There is no headless Flutter renderer available outside of tests. The rendering pipeline depends on:

- `WidgetTester` to pump widgets into a virtual screen
- `TestFlutterView` to configure surface size and pixel ratio
- `matchesGoldenFile()` to capture the rendered frame as a PNG

This means any tool that wants to screenshot Flutter widgets **must** run inside `flutter test`. There is no workaround for this — it's a fundamental constraint of the Flutter engine.

### What the CLI does

When you run `print_widget generate`, the CLI:

1. Reads `print_widget.yaml` to find your config file and settings
2. If `--delete-old` is passed, deletes all files and subdirectories inside the output directory
3. Generates a **temporary test file** at `.dart_tool/print_widget/print_test.dart`
4. The temp file imports your `print_config.dart` (with your `printSession` and `printList`)
5. Runs `flutter test --update-goldens` on that temp file
6. Collects the output PNGs and generates `manifest.json`

The user never needs to know about `flutter test`. The CLI is the interface.

```
User runs:     print_widget generate [--delete-old]
                        │
                        ▼
CLI reads:     print_widget.yaml → finds config_file path
                        │
                        ▼
(if --delete-old) CLI deletes all contents of output_dir/
                        │
                        ▼
CLI generates: .dart_tool/print_widget/print_test.dart
               (imports user's print_config.dart)
                        │
                        ▼
CLI executes:  flutter test --update-goldens .dart_tool/print_widget/print_test.dart
                        │
                        ▼
Flutter test:  Pumps each widget → renders → saves PNGs via matchesGoldenFile()
                        │
                        ▼
CLI outputs:   PNGs in output_dir/ + manifest.json
```

## Rendering pipeline

### Page rendering (`PrintType.page`)

Pages represent full-screen routes. The widget is passed directly to the AppWrapper as its child:

```
AppWrapper(child: LoginPage())
  └─ MaterialApp(theme: ..., home: LoginPage())
```

The page fills the entire device screen. No additional wrapping is applied.

### Widget rendering (`PrintType.widget`)

Widgets represent UI components (cards, buttons, etc). They are wrapped in a Scaffold with Center for proper layout:

```
AppWrapper(child: Scaffold(body: Center(child: ProductCard())))
  └─ MaterialApp(theme: ..., home: Scaffold(body: Center(child: ProductCard())))
```

This ensures the widget gets proper Material context (ink effects, default text styles) and is centered on screen.

### Size behavior

| Type | Size source | Behavior |
|------|------------|----------|
| Page | Device frame size | Widget fills the entire screen |
| Widget (no `size:`) | Device frame size | Widget is centered in full device screen |
| Widget (with `size:`) | Custom `Size` | Surface is set to that exact size |

## AppWrapper

The `AppWrapper` is a function that wraps every widget/page in the app's real shell:

```dart
typedef AppWrapper = Widget Function(Widget child);
```

This is what makes screenshots look like the real app. The wrapper typically provides:

- **Theme** (colors, typography, shape)
- **Localizations** (translations, date formats)
- **Providers** (state management, DI)
- **MediaQuery** overrides
- **Navigator** (for pages that depend on navigation context)

Example with providers:

```dart
final printSession = PrintSession(
  appWrapper: (child) => MultiProvider(
    providers: [
      Provider<AuthService>(create: (_) => MockAuthService()),
      Provider<ApiClient>(create: (_) => MockApiClient()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: child,
    ),
  ),
);
```

## Font loading

Flutter test renders text as blank rectangles by default (no fonts loaded). print_widget bundles three fonts:

- **Roboto-Regular.ttf** — default Material text font
- **Roboto-Bold.ttf** — bold variant
- **MaterialIcons-Regular.otf** — Material icons

Additionally, `loadPrintWidgetFonts()` auto-detects fonts declared in your project's `pubspec.yaml` and loads them. This happens transparently when the CLI runs the generated test file.

The generated test file includes a `flutter_test_config.dart` setup that calls `loadPrintWidgetFonts()` before any tests run.

## Grouped states

Entries can hold multiple visual states via `pages()` / `widgets()` + `state()`:

```dart
pages('sign_in', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(error: 'Bad email')),
]);
```

At runtime, the runner iterates each state and captures it as a separate PNG. The file naming is controlled by `PrintSession.stateOutputMode` (`StateOutputMode` enum):

| Mode | Path pattern |
|------|-------------|
| `prefix` (default) | `<name>/<state>_<device>.png` |
| `suffix` | `<name>/<device>_<state>.png` |
| `folder` | `<name>/<state>/<device>.png` |

Entries without states are unaffected.

## Manifest format

The manifest is a JSON file designed for machine consumption (LLMs, CI pipelines, diff tools):

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
      "name": "sign_in",
      "type": "page",
      "state": "empty",
      "file": "test/prints/output/sign_in/empty_iphone_15_pro.png",
      "device": "iphone_15_pro",
      "width": 393.0,
      "height": 852.0,
      "widthPx": 1179,
      "heightPx": 2556
    }
  ]
}
```

| Field | Description |
|-------|------------|
| `name` | Entry name from `printList` |
| `type` | `"page"` or `"widget"` |
| `state` | State name (only present for grouped-state entries) |
| `file` | Relative path to the PNG |
| `device` | Device frame name |
| `width` | Logical width in dp |
| `height` | Logical height in dp |
| `widthPx` | Physical width in pixels (width * pixelRatio) |
| `heightPx` | Physical height in pixels (height * pixelRatio) |

## Config file relationship

```
print_widget.yaml          (YAML - project-level settings)
  ├─ config_file: ───────► test/prints/print_config.dart  (Dart - runtime config)
  │                           ├─ printSession (AppWrapper + defaults + stateOutputMode)
  │                           └─ printList (entries to capture, with optional states)
  ├─ output_dir: ──────────► test/prints/output/  (PNGs + manifest)
  ├─ default_device:         iphone_15_pro
  └─ manifest:               true
```

`print_widget.yaml` is read by the CLI at build time.
`print_config.dart` is executed by Flutter test at runtime (it's real Dart code that instantiates widgets).

This separation exists because:
- YAML is easy for CLIs to parse and for users to edit
- Dart is required for widget instantiation (you can't describe a Flutter widget tree in YAML)

## Limitations

1. **Requires Flutter SDK** — the host machine must have Flutter installed (the CLI shells out to `flutter test`)
2. **No animations** — screenshots capture the settled state after `pumpAndSettle()`
3. **No network images** — use placeholder widgets or mock image providers
4. **No platform channels** — plugins that depend on native code won't work (use mocks)
5. **Single frame** — each state produces one PNG per device (use `pages()`/`widgets()` with `state()` for multiple visual states)
