# Set Up print_widget in a Project

Follow these steps to initialize print_widget in a Flutter project.

## Steps

### 1. Install the CLI globally

```bash
dart pub global activate print_widget
```

### 2. Initialize in the Flutter project

Run from the Flutter project root:

```bash
print_widget init
```

This creates:
- `print_widget.yaml` — project settings
- `print_widget/config.dart` — Dart config with `printSession` and `printList`

It also adds `print_widget` as a dev dependency in `pubspec.yaml`.

### 3. Configure the AppWrapper

Edit `print_widget/config.dart` and set the `appWrapper` to match the app's real shell. This ensures screenshots use the correct theme, providers, and localizations.

**Simple setup (theme only):**

```dart
final printSession = PrintSession(
  appWrapper: appWrapperFromMaterialApp(
    theme: AppTheme.light,
  ),
);
```

**Full setup (theme + providers):**

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
  defaultDevice: DeviceFrame.iPhone15Pro,
  outputDir: 'print_widget/output',
);
```

### 4. Add entries to printList

```dart
final printList = <PrintEntry>[
  page('login_page', const LoginPage()),
  page('home_page', const HomePage()),
  widget('product_card', ProductCard(data: mockProduct), size: Size(350, 400)),
];
```

### 5. Generate screenshots

```bash
print_widget generate
```

Screenshots are saved to `print_widget/output/` and a `manifest.json` is generated.

### 6. Verify output

Read `print_widget/output/manifest.json` to find the paths to generated PNGs, then view them to confirm they look correct.
