import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Set of font family names that were successfully loaded.
///
/// Populated by [loadPrintWidgetFonts], [loadCustomFonts], and
/// [loadPackageFonts]. Used by the generated test to detect missing fonts.
final loadedFontFamilies = <String>{};

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
/// 2. Register fonts with `google_fonts` variant names (e.g. `Roboto_regular`)
/// 3. Auto-detect and load fonts from `google_fonts/` directory
/// 4. Auto-detect and load fonts declared in your project's `pubspec.yaml`
/// 5. Print warnings for fonts that could not be found
Future<void> loadPrintWidgetFonts({String? projectRoot}) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = projectRoot ?? _detectProjectRoot();
  final usesGoogleFonts = _projectUsesGoogleFonts();

  // 1. Load bundled defaults (Roboto + MaterialIcons).
  await _loadBundledFonts(usesGoogleFonts: usesGoogleFonts);

  // 2. Auto-detect and load google_fonts/ directory.
  if (root != null) {
    await _loadGoogleFontsDir(root);
  }

  // 3. Auto-detect and load project fonts from pubspec.yaml.
  await _loadProjectFonts(projectRoot: root);

  // 4. Fallback: scan common font directories for undeclared fonts.
  if (root != null) {
    await _loadFallbackFontDirs(root, usesGoogleFonts: usesGoogleFonts);
  }

  // 5. Print summary of loaded fonts.
  if (loadedFontFamilies.isNotEmpty) {
    _log(
      '[print_widget] Loaded ${loadedFontFamilies.length} font '
      'registration(s): ${loadedFontFamilies.join(', ')}',
    );
  }

  if (loadedFontFamilies.isEmpty) {
    _warn(
      '[print_widget] No fonts were loaded! Text will render as Ahem '
      '(black rectangles).\n'
      '  Add a loadFonts callback to your PrintSession:\n'
      '\n'
      '    final printSession = PrintSession(\n'
      '      appWrapper: (child) => MaterialApp(home: child),\n'
      '      loadFonts: () async {\n'
      '        await loadCustomFonts({\n'
      "          'MyFont': ['assets/fonts/MyFont-Regular.ttf'],\n"
      '        });\n'
      '      },\n'
      '    );\n',
    );
  }
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

Future<void> _loadBundledFonts({required bool usesGoogleFonts}) async {
  final fontsDir = _findBundledFontsDir();
  if (fontsDir != null) {
    final robotoRegular = File('${fontsDir.path}/Roboto-Regular.ttf');
    final robotoBold = File('${fontsDir.path}/Roboto-Bold.ttf');
    final materialIcons = File('${fontsDir.path}/MaterialIcons-Regular.otf');

    // Load with standard family name.
    await _loadFontFromFile(robotoRegular, 'Roboto');
    await _loadFontFromFile(robotoBold, 'Roboto');
    await _loadFontFromFile(materialIcons, 'MaterialIcons');

    // Also register with google_fonts variant names.
    if (usesGoogleFonts) {
      _log('[print_widget] google_fonts detected — registering variant names');
      await _loadFontWithGoogleFontsVariants(
        robotoRegular,
        'Roboto',
        'Regular',
      );
      await _loadFontWithGoogleFontsVariants(robotoBold, 'Roboto', 'Bold');
    }
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

    if (usesGoogleFonts) {
      _log('[print_widget] google_fonts detected — registering variant names');
      await _loadFontFromBundle(
        'packages/print_widget_flutter/src/fonts/Roboto-Regular.ttf',
        'Roboto_regular',
      );
      await _loadFontFromBundle(
        'packages/print_widget_flutter/src/fonts/Roboto-Bold.ttf',
        'Roboto_bold',
      );
    }
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
// google_fonts variant loading
// ---------------------------------------------------------------------------

/// Registers a font file under all google_fonts variant-qualified names.
///
/// The `google_fonts` package uses `"${family}_${variant}"` naming
/// (e.g. `Roboto_regular`, `Roboto_bold`). This loads the file under
/// both the raw variant name and common aliases.
Future<void> _loadFontWithGoogleFontsVariants(
  File file,
  String family,
  String weight,
) async {
  if (!file.existsSync()) return;

  // google_fonts variant names: family_variant (lowercase).
  final variant = weight.toLowerCase();
  await _loadFontFromFile(file, '${family}_$variant');

  // Also map numeric weights to variant names.
  final numericAliases = _weightToVariantNames(weight);
  for (final alias in numericAliases) {
    if (alias != variant) {
      await _loadFontFromFile(file, '${family}_$alias');
    }
  }
}

/// Maps font weight identifiers to google_fonts variant names.
List<String> _weightToVariantNames(String weight) {
  switch (weight.toLowerCase()) {
    case '100':
    case 'thin':
      return ['100', 'thin'];
    case '200':
    case 'extralight':
      return ['200', 'extralight'];
    case '300':
    case 'light':
      return ['300', 'light'];
    case '400':
    case 'regular':
      return ['400', 'regular'];
    case '500':
    case 'medium':
      return ['500', 'medium'];
    case '600':
    case 'semibold':
      return ['600', 'semibold'];
    case '700':
    case 'bold':
      return ['700', 'bold'];
    case '800':
    case 'extrabold':
      return ['800', 'extrabold'];
    case '900':
    case 'black':
      return ['900', 'black'];
    default:
      return [weight.toLowerCase()];
  }
}

/// Parses a Google Fonts filename like `Roboto-Bold.ttf` into (family, weight).
({String family, String weight})? _parseGoogleFontFilename(String filename) {
  // Strip extension.
  final base = filename.replaceAll(RegExp(r'\.(ttf|otf)$'), '');

  // Common patterns:
  // "Roboto-Regular", "Roboto-Bold", "Roboto-Italic",
  // "Roboto-BoldItalic", "OpenSans-SemiBold"
  final dashIndex = base.lastIndexOf('-');
  if (dashIndex <= 0) return null;

  final family = base.substring(0, dashIndex);
  final weight = base.substring(dashIndex + 1);
  return (family: family, weight: weight);
}

// ---------------------------------------------------------------------------
// google_fonts/ directory auto-detection
// ---------------------------------------------------------------------------

Future<void> _loadGoogleFontsDir(String projectRoot) async {
  final googleFontsDir = Directory('$projectRoot/google_fonts');
  if (!googleFontsDir.existsSync()) return;

  _log('[print_widget] Found google_fonts/ directory — loading fonts:');

  final fontFiles = googleFontsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf') || f.path.endsWith('.otf'))
      .toList();

  if (fontFiles.isEmpty) return;

  for (final file in fontFiles) {
    final filename = file.uri.pathSegments.last;
    final parsed = _parseGoogleFontFilename(filename);
    if (parsed == null) {
      // Unknown naming pattern — load with filename as family.
      final baseName = filename.replaceAll(RegExp(r'\.(ttf|otf)$'), '');
      await _loadFontFromFile(file, baseName);
      _log('  [OK] $baseName <- $filename');
      continue;
    }

    // Load as standard family name (e.g. "Roboto").
    await _loadFontFromFile(file, parsed.family);

    // Load with google_fonts variant names (e.g. "Roboto_regular", "Roboto_bold").
    await _loadFontWithGoogleFontsVariants(file, parsed.family, parsed.weight);

    // Also handle italic variants.
    final weightLower = parsed.weight.toLowerCase();
    if (weightLower.contains('italic')) {
      final baseWeight =
          weightLower.replaceAll('italic', '').replaceAll('_', '');
      final italicVariant = baseWeight.isEmpty
          ? 'italic'
          : '${baseWeight}italic';
      await _loadFontFromFile(file, '${parsed.family}_$italicVariant');
    }

    _log('  [OK] ${parsed.family} (${parsed.weight}) <- $filename');
  }
}

// ---------------------------------------------------------------------------
// Fallback: scan common font directories
// ---------------------------------------------------------------------------

/// Scans common font directories for font files not declared in pubspec.yaml.
///
/// This catches fonts that exist on disk but aren't in the `flutter.fonts`
/// section — e.g., fonts added to `assets/fonts/` without updating pubspec.
Future<void> _loadFallbackFontDirs(
  String projectRoot, {
  required bool usesGoogleFonts,
}) async {
  const commonDirs = [
    'assets/fonts',
    'assets/font',
    'fonts',
  ];

  for (final dirPath in commonDirs) {
    final dir = Directory('$projectRoot/$dirPath');
    if (!dir.existsSync()) continue;

    final fontFiles = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf') || f.path.endsWith('.otf'))
        .toList();

    if (fontFiles.isEmpty) continue;

    _log('[print_widget] Fallback scan — found fonts in $dirPath/:');
    for (final file in fontFiles) {
      final filename = file.uri.pathSegments.last;
      final parsed = _parseGoogleFontFilename(filename);

      if (parsed == null) {
        final baseName = filename.replaceAll(RegExp(r'\.(ttf|otf)$'), '');
        await _loadFontFromFile(file, baseName);
        _log('  [OK] $baseName <- $dirPath/$filename');
        continue;
      }

      // Load as standard family name.
      await _loadFontFromFile(file, parsed.family);

      // Also register variant names if google_fonts is in use.
      if (usesGoogleFonts) {
        await _loadFontWithGoogleFontsVariants(
          file,
          parsed.family,
          parsed.weight,
        );
      }

      _log('  [OK] ${parsed.family} (${parsed.weight}) <- $dirPath/$filename');
    }
  }
}

/// Checks if the project has `google_fonts` as a dependency.
bool _projectUsesGoogleFonts() {
  final packageConfigFile = File('.dart_tool/package_config.json');
  if (!packageConfigFile.existsSync()) return false;

  try {
    final config = json.decode(packageConfigFile.readAsStringSync());
    final packages = config['packages'] as List<dynamic>?;
    if (packages == null) return false;

    return packages.any((pkg) => pkg['name'] == 'google_fonts');
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Project font auto-detection
// ---------------------------------------------------------------------------

Future<void> _loadProjectFonts({String? projectRoot}) async {
  final root = projectRoot;
  if (root == null) {
    _log('  Could not detect project root. Skipping project font loading.');
    return;
  }

  final pubspecFile = File('$root/pubspec.yaml');
  if (!pubspecFile.existsSync()) return;

  final pubspecContent = pubspecFile.readAsStringSync();
  final fonts = _parseFontsFromPubspec(pubspecContent);

  // Also load fonts with google_fonts variant names if applicable.
  final usesGoogleFonts = _projectUsesGoogleFonts();

  if (fonts.isNotEmpty) {
    _log('[print_widget] Auto-detected project fonts:');
    await _loadFontEntries(fonts, root, withVariants: usesGoogleFonts);
  }
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

Future<void> _loadFontEntries(
  List<_FontFamily> fonts,
  String root, {
  bool withVariants = false,
}) async {
  final notFound = <String>[];

  for (final family in fonts) {
    var loaded = false;
    for (final assetPath in family.assets) {
      final file = File('$root/$assetPath');
      if (file.existsSync()) {
        await _loadFontFromFile(file, family.name);

        // Also register google_fonts variant names.
        if (withVariants) {
          final filename = file.uri.pathSegments.last;
          final parsed = _parseGoogleFontFilename(filename);
          if (parsed != null) {
            await _loadFontWithGoogleFontsVariants(
              file,
              family.name,
              parsed.weight,
            );
          }
        }

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
  loadedFontFamilies.add(family);
}

Future<void> _loadFontFromBundle(String assetKey, String family) async {
  final data = await rootBundle.load(assetKey);
  final fontLoader = FontLoader(family);
  fontLoader.addFont(Future.value(data));
  await fontLoader.load();
  loadedFontFamilies.add(family);
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
