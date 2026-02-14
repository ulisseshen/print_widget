# print_widget — API Reference

All public API is exported from `package:print_widget/print_widget.dart`.

## PrintSession

High-level session that configures how entries are rendered.

```dart
class PrintSession {
  PrintSession({
    required AppWrapper appWrapper,
    DeviceFrame? defaultDevice,
    String outputDir = 'print_widget/output',
    bool generateManifest = true,
  });
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `appWrapper` | `AppWrapper` | required | Wraps every widget/page with app shell (theme, providers, etc.) |
| `defaultDevice` | `DeviceFrame?` | `null` | Device used when entry has no `devices` list |
| `outputDir` | `String` | `'print_widget/output'` | Output directory for PNGs and manifest |
| `generateManifest` | `bool` | `true` | Whether to generate manifest.json |

## PrintEntry + Helper Functions

Represents a single widget or page to screenshot.

```dart
class PrintEntry {
  const PrintEntry({
    required String name,
    required Widget widget,
    required PrintType type,
    Size? size,
    List<DeviceFrame>? devices,
  });
}
```

### `page()` — full-screen page

```dart
PrintEntry page(String name, Widget widget, {List<DeviceFrame>? devices})
```

The widget fills the entire device screen. Passed directly to AppWrapper.

### `widget()` — centered component

```dart
PrintEntry widget(String name, Widget widget, {Size? size, List<DeviceFrame>? devices})
```

The widget is wrapped in `Scaffold > Center`. If `size` is provided, the render surface is set to that exact size.

## DeviceFrame

Defines a device's screen dimensions and pixel ratio.

```dart
class DeviceFrame {
  const DeviceFrame({
    required String name,
    required Size size,
    double pixelRatio = 1.0,
  });
}
```

### Built-in Devices

| Constant | Name | Size (dp) | Pixel Ratio |
|----------|------|-----------|-------------|
| `DeviceFrame.iPhoneSE` | `iphone_se` | 375x667 | 2.0 |
| `DeviceFrame.iPhone14` | `iphone_14` | 390x844 | 3.0 |
| `DeviceFrame.iPhone15Pro` | `iphone_15_pro` | 393x852 | 3.0 |
| `DeviceFrame.iPhone16ProMax` | `iphone_16_pro_max` | 440x956 | 3.0 |
| `DeviceFrame.iPadMini` | `ipad_mini` | 744x1133 | 2.0 |
| `DeviceFrame.iPadAir` | `ipad_air` | 820x1180 | 2.0 |
| `DeviceFrame.iPadPro11` | `ipad_pro_11` | 834x1194 | 2.0 |
| `DeviceFrame.iPadPro13` | `ipad_pro_13` | 1024x1366 | 2.0 |
| `DeviceFrame.pixel7` | `pixel_7` | 412x915 | 2.625 |
| `DeviceFrame.pixel8Pro` | `pixel_8_pro` | 448x998 | 3.0 |
| `DeviceFrame.samsungS24` | `samsung_s24` | 360x780 | 3.0 |
| `DeviceFrame.samsungS24Ultra` | `samsung_s24_ultra` | 412x915 | 3.0 |
| `DeviceFrame.small` | `small` | 320x480 | 1.0 |
| `DeviceFrame.medium` | `medium` | 400x800 | 1.0 |
| `DeviceFrame.large` | `large` | 600x1000 | 1.0 |
| `DeviceFrame.compact` | `compact` | 300x300 | 1.0 |

### Preset Groups

| Constant | Devices |
|----------|---------|
| `DeviceFrame.popular` | iPhone15Pro, pixel7, iPadPro11 |
| `DeviceFrame.allPhones` | iPhoneSE, iPhone14, iPhone15Pro, iPhone16ProMax, pixel7, pixel8Pro, samsungS24, samsungS24Ultra |
| `DeviceFrame.allTablets` | iPadMini, iPadAir, iPadPro11, iPadPro13 |

## AppWrapper

Function type that wraps every widget/page in the app's shell.

```dart
typedef AppWrapper = Widget Function(Widget child);
```

### `appWrapperFromMaterialApp` helper

```dart
AppWrapper appWrapperFromMaterialApp({
  ThemeData? theme,
  ThemeData? darkTheme,
  Locale? locale,
  Iterable<LocalizationsDelegate>? localizationsDelegates,
})
```

Creates an AppWrapper that wraps the child in a `MaterialApp` with the given theme and locale settings.

## Printable Mixin

Optional mixin for widgets that declare their own print metadata.

```dart
mixin Printable on Widget {
  String get printName;
  PrintType get printType;
}
```

## PrintType

```dart
enum PrintType { page, widget }
```

## PrintConfig

Low-level configuration for the standalone test API.

```dart
class PrintConfig {
  const PrintConfig({
    Size size = const Size(400, 800),
    double pixelRatio = 1.0,
    ThemeData? theme,
    ThemeData? darkTheme,
    String outputDir = 'prints',
    Color? background,
    EdgeInsets padding = EdgeInsets.zero,
    Locale? locale,
    TextDirection textDirection = TextDirection.ltr,
    bool wrapInScaffold = false,
  });
}
```

| Field | Default | Description |
|-------|---------|-------------|
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

## Font Loading

### `loadPrintWidgetFonts()`

```dart
Future<void> loadPrintWidgetFonts({String? projectRoot})
```

Loads bundled Roboto + MaterialIcons, then auto-detects and loads fonts declared in the project's `pubspec.yaml`. Call once in `flutter_test_config.dart`.

### `loadCustomFonts()`

```dart
Future<void> loadCustomFonts(Map<String, List<String>> fontFamilies)
```

Loads fonts from explicit file paths.

```dart
await loadCustomFonts({
  'MyFont': ['assets/fonts/MyFont-Regular.ttf'],
  'MyFont-Bold': ['assets/fonts/MyFont-Bold.ttf'],
});
```

### `loadPackageFonts()`

```dart
Future<void> loadPackageFonts(String packageName)
```

Loads fonts declared in a package dependency's `pubspec.yaml`.

## PrintManifest / PrintManifestEntry

```dart
class PrintManifest {
  PrintManifest({required DateTime generatedAt, required List<PrintManifestEntry> screenshots});
  Map<String, dynamic> toJson();
  String toJsonString();
}

class PrintManifestEntry {
  const PrintManifestEntry({
    required String name,
    required String type,
    required String file,
    required String device,
    required double width,
    required double height,
    required int widthPx,
    required int heightPx,
  });
  Map<String, dynamic> toJson();
}
```

## Standalone Test API

Functions for capturing widgets directly inside `testWidgets` blocks, without the CLI.

### `printWidget` — single widget

```dart
Future<void> printWidget(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  DeviceFrame? device,
  PrintConfig config = const PrintConfig(),
})
```

### `printWidgetOnDevices` — same widget, multiple devices

```dart
Future<void> printWidgetOnDevices(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  required List<DeviceFrame> devices,
  PrintConfig config = const PrintConfig(),
})
```

### `printWidgets` — catalog of widgets

```dart
Future<void> printWidgets(
  WidgetTester tester, {
  required Map<String, Widget> widgets,
  DeviceFrame? device,
  PrintConfig config = const PrintConfig(),
})
```

### `printWidgetThemed` — light and dark variants

```dart
Future<void> printWidgetThemed(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  ThemeData? lightTheme,
  ThemeData? darkTheme,
  DeviceFrame? device,
  PrintConfig config = const PrintConfig(),
})
```

### `printEntry` — render a PrintEntry with a PrintSession

```dart
Future<List<PrintManifestEntry>> printEntry(
  WidgetTester tester, {
  required PrintEntry entry,
  required PrintSession session,
  DeviceFrame? deviceOverride,
  PrintConfig? config,
})
```

### `printAllEntries` — render all entries

```dart
Future<List<PrintManifestEntry>> printAllEntries(
  WidgetTester tester, {
  required List<PrintEntry> entries,
  required PrintSession session,
  PrintConfig? config,
})
```
