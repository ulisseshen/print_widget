import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads bundled Roboto + MaterialIcons and auto-detects project fonts.
///
/// Call this once before your tests, typically in `flutter_test_config.dart`:
///
/// ```dart
/// import 'package:print_widget_flutter/print_widget.dart';
///
/// Future<void> testExecutable(FutureOr<void> Function() testMain) async {
///   await loadPrintWidgetFonts();
///   return testMain();
/// }
/// ```
///
/// This will:
/// 1. Load bundled Roboto and MaterialIcons (always available)
/// 2. Auto-detect and load fonts declared in your project's `pubspec.yaml`
/// 3. Print warnings for fonts that could not be found
Future<void> loadPrintWidgetFonts({String? projectRoot}) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1. Load bundled defaults (Roboto + MaterialIcons).
  await _loadBundledFonts();

  // 2. Auto-detect and load project fonts from pubspec.yaml.
  await _loadProjectFonts(projectRoot: projectRoot);
}

/// Loads additional fonts from file paths.
///
/// Use this to load your app's custom fonts manually:
/// ```dart
/// await loadCustomFonts({
///   'MyFont': ['assets/fonts/MyFont-Regular.ttf'],
///   'MyFont-Bold': ['assets/fonts/MyFont-Bold.ttf'],
/// });
/// ```
Future<void> loadCustomFonts(Map<String, List<String>> fontFamilies) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in fontFamilies.entries) {
    for (final path in entry.value) {
      final file = File(path);
      if (file.existsSync()) {
        await _loadFontFromFile(file, entry.key);
        _log('  Loaded custom font: ${entry.key} <- $path');
      } else {
        _warn('  Font file not found: $path for family "${entry.key}"');
      }
    }
  }
}

/// Loads fonts declared in a package's pubspec.yaml.
///
/// Useful when you want to load fonts from a specific package dependency:
/// ```dart
/// await loadPackageFonts('my_design_system');
/// ```
Future<void> loadPackageFonts(String packageName) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final packageRoot = _findPackageRoot(packageName);
  if (packageRoot == null) {
    _warn(
      'Could not find package "$packageName". '
      'Make sure it is listed in your pubspec.yaml dependencies.',
    );
    return;
  }

  final pubspecFile = File('$packageRoot/pubspec.yaml');
  if (!pubspecFile.existsSync()) return;

  final fonts = _parseFontsFromPubspec(pubspecFile.readAsStringSync());
  if (fonts.isEmpty) {
    _log('  No fonts declared in $packageName/pubspec.yaml');
    return;
  }

  _log('  Loading fonts from package "$packageName":');
  await _loadFontEntries(fonts, packageRoot);
}

// ---------------------------------------------------------------------------
// Bundled fonts
// ---------------------------------------------------------------------------

Future<void> _loadBundledFonts() async {
  final fontsDir = _findBundledFontsDir();
  if (fontsDir != null) {
    await _loadFontFromFile(
      File('${fontsDir.path}/Roboto-Regular.ttf'),
      'Roboto',
    );
    await _loadFontFromFile(
      File('${fontsDir.path}/Roboto-Bold.ttf'),
      'Roboto',
    );
    await _loadFontFromFile(
      File('${fontsDir.path}/MaterialIcons-Regular.otf'),
      'MaterialIcons',
    );
    return;
  }

  // Fallback: load from Flutter's asset bundle (works when filesystem
  // resolution fails, e.g. pub cache or hosted dependencies).
  _log(
    '[print_widget] Bundled fonts dir not found on disk, '
    'trying rootBundle fallback...',
  );
  try {
    await _loadFontFromBundle(
      'packages/print_widget_flutter/src/fonts/Roboto-Regular.ttf',
      'Roboto',
    );
    await _loadFontFromBundle(
      'packages/print_widget_flutter/src/fonts/Roboto-Bold.ttf',
      'Roboto',
    );
    await _loadFontFromBundle(
      'packages/print_widget_flutter/src/fonts/MaterialIcons-Regular.otf',
      'MaterialIcons',
    );
  } catch (e) {
    _warn(
      'Could not load print_widget bundled fonts.\n'
      '  Tried filesystem and rootBundle fallback.\n'
      '  Error: $e\n'
      '  Text will render as Ahem (black rectangles).\n'
      '  To fix: call loadCustomFonts() with your font paths.',
    );
  }
}

// ---------------------------------------------------------------------------
// Project font auto-detection
// ---------------------------------------------------------------------------

Future<void> _loadProjectFonts({String? projectRoot}) async {
  final root = projectRoot ?? _detectProjectRoot();
  if (root == null) {
    _log('  Could not detect project root. Skipping project font loading.');
    return;
  }

  final pubspecFile = File('$root/pubspec.yaml');
  if (!pubspecFile.existsSync()) return;

  final fonts = _parseFontsFromPubspec(pubspecFile.readAsStringSync());
  if (fonts.isEmpty) return;

  _log('[print_widget] Auto-detected project fonts:');
  await _loadFontEntries(fonts, root);
}

/// Parses font family declarations from a pubspec.yaml string.
///
/// Expects the YAML structure:
/// ```yaml
/// flutter:
///   fonts:
///     - family: MyFont
///       fonts:
///         - asset: assets/fonts/MyFont-Regular.ttf
///         - asset: assets/fonts/MyFont-Bold.ttf
///           weight: 700
/// ```
List<_FontFamily> _parseFontsFromPubspec(String pubspecContent) {
  final families = <_FontFamily>[];

  // Simple line-based parser to avoid a yaml dependency.
  final lines = pubspecContent.split('\n');
  var inFlutter = false;
  var inFonts = false;
  var inFamilyBlock = false;
  var inFontsArray = false;
  String? currentFamily;
  final currentAssets = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;

    // Detect top-level `flutter:` section.
    if (trimmed.startsWith('flutter:') && indent == 0) {
      inFlutter = true;
      inFonts = false;
      continue;
    }

    // Exit flutter section if we hit another top-level key.
    if (indent == 0 && trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      if (inFlutter) {
        // Save last family if any.
        if (currentFamily != null && currentAssets.isNotEmpty) {
          families.add(_FontFamily(currentFamily, List.of(currentAssets)));
        }
        inFlutter = false;
        inFonts = false;
        inFamilyBlock = false;
        inFontsArray = false;
        currentFamily = null;
        currentAssets.clear();
      }
      continue;
    }

    if (!inFlutter) continue;

    // Detect `fonts:` under flutter.
    if (trimmed.startsWith('fonts:') && !inFamilyBlock) {
      inFonts = true;
      continue;
    }

    if (!inFonts) continue;

    // Detect `- family: FamilyName`.
    final familyMatch = RegExp(r'^-\s*family:\s*(.+)$').firstMatch(trimmed);
    if (familyMatch != null) {
      // Save previous family.
      if (currentFamily != null && currentAssets.isNotEmpty) {
        families.add(_FontFamily(currentFamily, List.of(currentAssets)));
      }
      currentFamily = familyMatch.group(1)!.trim();
      currentAssets.clear();
      inFamilyBlock = true;
      inFontsArray = false;
      continue;
    }

    if (!inFamilyBlock) continue;

    // Detect `fonts:` array inside a family block.
    if (trimmed.startsWith('fonts:')) {
      inFontsArray = true;
      continue;
    }

    if (!inFontsArray) continue;

    // Detect `- asset: path/to/font.ttf`.
    final assetMatch = RegExp(r'^-\s*asset:\s*(.+)$').firstMatch(trimmed);
    if (assetMatch != null) {
      currentAssets.add(assetMatch.group(1)!.trim());
      continue;
    }

    // Still inside fonts array for weight/style lines.
    if (trimmed.startsWith('weight:') || trimmed.startsWith('style:')) {
      continue;
    }
  }

  // Save last family.
  if (currentFamily != null && currentAssets.isNotEmpty) {
    families.add(_FontFamily(currentFamily, List.of(currentAssets)));
  }

  return families;
}

Future<void> _loadFontEntries(List<_FontFamily> fonts, String root) async {
  final notFound = <String>[];

  for (final family in fonts) {
    var loaded = false;
    for (final assetPath in family.assets) {
      final file = File('$root/$assetPath');
      if (file.existsSync()) {
        await _loadFontFromFile(file, family.name);
        _log('  [OK] ${family.name} <- $assetPath');
        loaded = true;
      } else {
        notFound.add('$assetPath (family: ${family.name})');
      }
    }
    if (!loaded) {
      _warn('  [MISSING] ${family.name} - no font files found');
    }
  }

  if (notFound.isNotEmpty) {
    _warn(
      '\n'
      '[print_widget] Some font files were not found:\n'
      '${notFound.map((f) => '  - $f').join('\n')}\n'
      '\n'
      'To fix this, either:\n'
      '  1. Ensure the font files exist at the declared paths\n'
      '  2. Or load them manually in your flutter_test_config.dart:\n'
      '\n'
      '     await loadCustomFonts({\n'
      "       'MyFont': ['/absolute/path/to/MyFont.ttf'],\n"
      '     });\n',
    );
  }
}

// ---------------------------------------------------------------------------
// Path resolution helpers
// ---------------------------------------------------------------------------

String? _detectProjectRoot() {
  // Walk up from CWD looking for pubspec.yaml.
  var dir = Directory.current;
  for (var i = 0; i < 10; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Directory? _findBundledFontsDir() {
  final candidates = [
    // When running from the package source itself.
    Directory('lib/src/fonts'),
    // When running from a consumer project via package_config.json.
    ..._findPackageFontsDirs('print_widget_flutter'),
    // When running from CLI-generated test at .dart_tool/print_widget/.
    Directory('../../lib/src/fonts'),
  ];

  for (final dir in candidates) {
    try {
      if (dir.existsSync()) return dir;
    } catch (_) {
      // resolveSymbolicLinksSync can throw on broken symlinks; skip.
    }
  }
  return null;
}

String? _findPackageRoot(String packageName) {
  final packageConfigFile = File('.dart_tool/package_config.json');
  if (!packageConfigFile.existsSync()) return null;

  try {
    final config = json.decode(packageConfigFile.readAsStringSync());
    final packages = config['packages'] as List<dynamic>?;
    if (packages == null) return null;

    for (final pkg in packages) {
      if (pkg['name'] == packageName) {
        var rootUri = pkg['rootUri'] as String;
        if (rootUri.startsWith('../') || rootUri.startsWith('..\\')) {
          rootUri = '${packageConfigFile.parent.path}/$rootUri';
        } else if (rootUri.startsWith('file://')) {
          rootUri = Uri.parse(rootUri).toFilePath();
        }
        // Normalize path — resolve symlinks when possible, fall back to raw path.
        final dir = Directory(rootUri);
        try {
          return dir.resolveSymbolicLinksSync();
        } catch (_) {
          // resolveSymbolicLinksSync throws if the path doesn't exist.
          if (dir.existsSync()) return dir.path;
          return rootUri;
        }
      }
    }
  } catch (_) {}
  return null;
}

List<Directory> _findPackageFontsDirs(String packageName) {
  final root = _findPackageRoot(packageName);
  if (root == null) return [];
  return [Directory('$root/lib/src/fonts')];
}

// ---------------------------------------------------------------------------
// Core loader
// ---------------------------------------------------------------------------

Future<void> _loadFontFromFile(File file, String family) async {
  if (!file.existsSync()) return;

  final bytes = file.readAsBytesSync();
  final fontLoader = FontLoader(family);
  fontLoader.addFont(
    Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
  );
  await fontLoader.load();
}

Future<void> _loadFontFromBundle(String assetKey, String family) async {
  final data = await rootBundle.load(assetKey);
  final fontLoader = FontLoader(family);
  fontLoader.addFont(Future.value(data));
  await fontLoader.load();
  _log('  Loaded font from bundle: $family <- $assetKey');
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

void _log(String message) {
  // ignore: avoid_print
  print(message);
}

void _warn(String message) {
  // ignore: avoid_print
  print('\x1B[33m$message\x1B[0m'); // Yellow text.
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _FontFamily {
  const _FontFamily(this.name, this.assets);
  final String name;
  final List<String> assets;
}
