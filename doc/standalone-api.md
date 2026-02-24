# Standalone test API

If you prefer writing Flutter tests directly instead of using the CLI, print_widget exposes a lower-level API that works inside any `testWidgets` block.

## Setup

### 1. Add the dependency

```yaml
dev_dependencies:
  print_widget:
    path: ../print_widget  # or from pub
```

### 2. Load fonts

Create `test/flutter_test_config.dart`:

```dart
import 'dart:async';
import 'package:print_widget/print_widget.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadPrintWidgetFonts();
  return testMain();
}
```

## API reference

### `printWidget` — capture a single widget

```dart
testWidgets('capture a button', (tester) async {
  await printWidget(
    tester,
    name: 'my_button',
    widget: FilledButton(onPressed: () {}, child: Text('Buy Now')),
    device: DeviceFrame.iPhone15Pro,
    config: PrintConfig(
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
    ),
  );
});
```

Output: `prints/my_button/iphone_15_pro.png`

Without a device, it uses the config's default size:

```dart
await printWidget(
  tester,
  name: 'simple_card',
  widget: MyCard(),
  config: PrintConfig(size: Size(350, 200)),
);
```

Output: `prints/simple_card.png`

### `printWidgetOnDevices` — same widget, multiple devices

```dart
testWidgets('capture on popular devices', (tester) async {
  await printWidgetOnDevices(
    tester,
    name: 'login_form',
    widget: LoginForm(),
    devices: DeviceFrame.popular,
  );
});
```

Output:
- `prints/login_form/iphone_15_pro.png`
- `prints/login_form/pixel_7.png`
- `prints/login_form/ipad_pro_11.png`

### `printWidgets` — catalog of widgets

```dart
testWidgets('widget catalog', (tester) async {
  await printWidgets(
    tester,
    widgets: {
      'primary_button': FilledButton(onPressed: () {}, child: Text('Primary')),
      'outlined_button': OutlinedButton(onPressed: () {}, child: Text('Outlined')),
      'icon_button': IconButton(onPressed: () {}, icon: Icon(Icons.star)),
    },
    device: DeviceFrame.iPhone15Pro,
  );
});
```

### `printWidgetThemed` — light and dark variants

```dart
testWidgets('themed profile card', (tester) async {
  await printWidgetThemed(
    tester,
    name: 'profile',
    widget: ProfileCard(user: mockUser),
    lightTheme: ThemeData.light(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
    device: DeviceFrame.pixel7,
  );
});
```

Output:
- `prints/profile_light/pixel_7.png`
- `prints/profile_dark/pixel_7.png`

## Session-based API

For more control, use `PrintSession` + `PrintEntry` directly in tests:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget/print_widget.dart';

void main() {
  final session = PrintSession(
    appWrapper: (child) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: child,
    ),
    defaultDevice: DeviceFrame.iPhone15Pro,
    outputDir: 'test/prints/output',
    // stateOutputMode: StateOutputMode.prefix, // default
  );

  final entries = <PrintEntry>[
    page('login', const LoginPage()),
    widget('card', ProductCard(title: 'Test'), size: Size(350, 400)),

    // Grouped states
    pages('sign_in', states: [
      state('empty', SignInScreen()),
      state('filled', SignInScreen(email: 'test@test.com')),
    ]),
  ];

  testWidgets('generate all', (tester) async {
    final manifestEntries = await printAllEntries(
      tester,
      entries: entries,
      session: session,
    );

    // Write manifest
    final manifest = PrintManifest(
      generatedAt: DateTime.now(),
      screenshots: manifestEntries,
    );
    final file = File('${session.outputDir}/manifest.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(manifest.toJsonString());
  });

  testWidgets('generate single entry', (tester) async {
    await printEntry(
      tester,
      entry: entries.first,
      session: session,
    );
  });
}
```

## Running

```bash
flutter test --update-goldens test/your_test_file.dart
```

The `--update-goldens` flag tells Flutter to write new PNGs instead of comparing against existing ones. Subsequent runs without the flag will compare and fail if the output has changed (regression detection).

## `PrintConfig` options

| Option | Default | Description |
|--------|---------|-------------|
| `size` | 400x800 | Render surface in logical pixels |
| `pixelRatio` | 1.0 | Device pixel ratio |
| `theme` | null | Light ThemeData |
| `darkTheme` | null | Dark ThemeData |
| `outputDir` | `'prints'` | Golden file output directory |
| `background` | null | Background color (null = transparent) |
| `padding` | zero | Padding around the widget |
| `locale` | null | Widget locale |
| `textDirection` | ltr | Text direction |
| `wrapInScaffold` | false | Wrap widget in a Scaffold |
