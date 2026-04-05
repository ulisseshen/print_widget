import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class DiagnoseCommand extends Command<void> {
  DiagnoseCommand() {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to print_widget.yaml config file.',
        defaultsTo: 'print_widget.yaml',
      )
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Diagnose a specific widget by name.',
      );
  }

  @override
  String get name => 'diagnose';

  @override
  String get description =>
      'Analyze widget constructors and report what mock data is needed.';

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
    final filterName = argResults!['name'] as String?;

    // 1. Read print_widget.yaml
    final yamlFile = File(configPath);
    if (!yamlFile.existsSync()) {
      stderr.writeln(
        'Config file not found: $configPath\n'
        'Run "print_widget init" first.',
      );
      exitCode = 1;
      return;
    }

    final yamlContent = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
    final dartConfigFile =
        yamlContent['config_file'] as String? ?? 'print_widget/config.dart';

    // 2. Read the Dart config file
    final configFile = File(dartConfigFile);
    if (!configFile.existsSync()) {
      stderr.writeln(
        'Dart config file not found: $dartConfigFile\n'
        'Run "print_widget init" to create a template.',
      );
      exitCode = 1;
      return;
    }

    final dartContent = configFile.readAsStringSync();

    stdout.writeln('print_widget diagnose');
    stdout.writeln('');
    stdout.writeln('Analyzing: $dartConfigFile');
    stdout.writeln('');

    // 3. Parse entries from the config
    final entries = _parseEntries(dartContent);
    if (entries.isEmpty) {
      stdout.writeln('No print entries detected in $dartConfigFile.');
      return;
    }

    // 4. Resolve import paths to find widget source files
    final importMap = _parseImports(dartContent, dartConfigFile);

    // 5. Analyze each entry
    var diagnosed = 0;
    for (final entry in entries) {
      if (filterName != null && entry.name != filterName) continue;
      diagnosed++;

      _diagnoseEntry(entry, importMap, dartConfigFile);
    }

    if (filterName != null && diagnosed == 0) {
      stderr.writeln('No entry named "$filterName" found.');
      exitCode = 1;
    }
  }
}

/// Diagnose a single entry: find the widget source, analyze constructor,
/// check for provider usage.
void _diagnoseEntry(
  _ParsedEntry entry,
  Map<String, String> importMap,
  String configFilePath,
) {
  // Find the widget class name from the entry
  final className = entry.widgetClassName;
  if (className == null) {
    stdout.writeln('? ${entry.name} — could not determine widget class');
    stdout.writeln('');
    return;
  }

  // Try to find the source file for this class
  final sourceFile = _findSourceFile(className, importMap, configFilePath);
  String? sourceContent;
  if (sourceFile != null && File(sourceFile).existsSync()) {
    sourceContent = File(sourceFile).readAsStringSync();
  }

  if (sourceContent == null) {
    // Fall back: analyze from config file inline usage
    stdout.writeln('? ${entry.name} ($className) — source file not found');
    stdout
        .writeln('  Could not locate the source file to analyze constructor.');
    stdout.writeln('');
    return;
  }

  // Parse constructor parameters
  final params = _parseConstructorParams(className, sourceContent);

  // Check for provider/context dependencies
  final contextDeps = _findContextDependencies(sourceContent);

  // Determine status and print report
  final requiredParams = params.where((p) => p.isRequired && !p.isKey).toList();
  final hasContextDeps = contextDeps.isNotEmpty;

  if (hasContextDeps) {
    stdout.writeln(
      '\u2717 ${entry.name} ($className) — uses state management (needs appWrapper setup)',
    );
    for (final dep in contextDeps) {
      stdout.writeln('  Found: ${dep.usage} at line ${dep.line}');
    }
    if (requiredParams.isNotEmpty) {
      stdout.writeln('  Required params:');
      for (final p in requiredParams) {
        stdout
            .writeln('    \u2022 ${p.name}: ${p.type} \u2192 ${p.suggestion}');
      }
    }
    stdout.writeln(
      '  Add providers to appWrapper in your PrintSession.',
    );
  } else if (requiredParams.isEmpty) {
    stdout.writeln(
      '\u2713 ${entry.name} ($className) — no required params, ready to use',
    );
    final helperName = entry.isPage ? 'page' : 'widget';
    stdout.writeln("  $helperName('${entry.name}', const $className())");
  } else {
    stdout.writeln(
      '\u26a0 ${entry.name} ($className) — ${requiredParams.length} required '
      'param${requiredParams.length == 1 ? '' : 's'} need values',
    );
    stdout.writeln('  Required:');
    for (final p in requiredParams) {
      stdout.writeln(
          '    \u2022 ${p.name}: ${p.type} \u2192 use: ${p.suggestion}');
    }

    // Print suggested entry
    stdout.writeln('');
    final helperName = entry.isPage ? 'page' : 'widget';
    final paramAssignments = requiredParams
        .map((p) => '      ${p.name}: ${p.suggestion},')
        .join('\n');
    stdout.writeln('  Suggested entry:');
    stdout.writeln('    $helperName(\'${entry.name}\', $className(');
    stdout.writeln(paramAssignments);
    stdout.writeln('    ))');
  }

  // Show optional params with callbacks
  final optionalCallbacks =
      params.where((p) => !p.isRequired && !p.isKey && p.isCallback).toList();
  if (optionalCallbacks.isNotEmpty) {
    stdout.writeln('  Optional callbacks (use no-ops):');
    for (final p in optionalCallbacks) {
      stdout.writeln('    \u2022 ${p.name}: ${p.type} \u2192 ${p.suggestion}');
    }
  }

  stdout.writeln('');
}

/// Parse import statements to build a map of class-name hints -> file paths.
Map<String, String> _parseImports(String dartContent, String configFilePath) {
  final imports = <String, String>{};
  final configDir = File(configFilePath).parent.path;
  final projectRoot = Directory.current.path;

  // Try to read the package name from pubspec.yaml
  String? ownPackageName;
  final pubspecFile = File('$projectRoot/pubspec.yaml');
  if (pubspecFile.existsSync()) {
    try {
      final pubspec = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
      ownPackageName = pubspec['name'] as String?;
    } catch (_) {}
  }

  // Match: import 'package:xxx/yyy.dart'; and import '../relative.dart';
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]''');

  for (final match in importPattern.allMatches(dartContent)) {
    final importPath = match.group(1)!;

    // Skip dart: and print_widget library imports
    if (importPath.startsWith('dart:')) continue;
    if (importPath.startsWith('package:print_widget_flutter')) continue;
    if (importPath.startsWith('package:print_widget/')) continue;

    // For package: imports, try to resolve via lib/
    if (importPath.startsWith('package:')) {
      final parts = importPath.substring('package:'.length).split('/');
      if (parts.length >= 2) {
        final packageName = parts[0];
        final rest = parts.sublist(1).join('/');

        // Try common locations relative to project root and config dir
        final candidates = <String>[
          // If it's the project's own package, resolve to lib/
          if (ownPackageName != null && packageName == ownPackageName)
            '$projectRoot/lib/$rest',
          '$projectRoot/lib/$rest',
          _resolvePath(configDir, 'lib/$rest'),
          _resolvePath(configDir, '../lib/$rest'),
          '$projectRoot/packages/$packageName/lib/$rest',
        ];

        for (final candidate in candidates) {
          if (File(candidate).existsSync()) {
            imports[importPath] = candidate;
            break;
          }
        }
      }
    } else {
      // Relative import
      final resolved = _resolvePath(configDir, importPath);
      if (File(resolved).existsSync()) {
        imports[importPath] = resolved;
      }
    }
  }

  return imports;
}

/// Resolve a potentially relative path against a base directory.
String _resolvePath(String baseDir, String path) {
  if (path.startsWith('/')) return path;
  return Uri.file(baseDir).resolve(path).toFilePath();
}

/// Try to find the source file for a given class name by searching imports.
String? _findSourceFile(
  String className,
  Map<String, String> importMap,
  String configFilePath,
) {
  // Check each imported file for the class definition
  for (final entry in importMap.entries) {
    final filePath = entry.value;
    if (!File(filePath).existsSync()) continue;

    final content = File(filePath).readAsStringSync();
    // Check if this file defines the class
    if (RegExp('class\\s+$className\\s').hasMatch(content)) {
      return filePath;
    }
  }

  // Also check the config file directory and lib/ for files that might contain the class
  final searchDirs = <Directory>[
    File(configFilePath).parent,
    Directory('${Directory.current.path}/lib'),
  ];

  for (final dir in searchDirs) {
    if (!dir.existsSync()) continue;
    try {
      final dartFiles = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (RegExp('class\\s+$className\\s').hasMatch(content)) {
          return file.path;
        }
      }
    } catch (_) {
      // Permission errors, etc.
    }
  }

  return null;
}

/// Parse constructor parameters for a given class from its source code.
List<_ConstructorParam> _parseConstructorParams(
  String className,
  String sourceContent,
) {
  final params = <_ConstructorParam>[];

  // Find the constructor block: ClassName({ ... }) or ClassName( ... )
  // Handles: const ClassName({ ... }), ClassName.named({ ... })
  final constructorPattern = RegExp(
    '(?:const\\s+)?$className\\s*\\(([^)]*(?:\\{[^}]*\\})?[^)]*)\\)',
    dotAll: true,
  );

  final match = constructorPattern.firstMatch(sourceContent);
  if (match == null) return params;

  var paramBlock = match.group(1)!.trim();

  // Determine if using named params (curly braces)
  final isNamed = paramBlock.contains('{');

  if (isNamed) {
    // Extract content inside { ... }
    final braceStart = paramBlock.indexOf('{');
    final braceEnd = paramBlock.lastIndexOf('}');
    if (braceStart >= 0 && braceEnd > braceStart) {
      paramBlock = paramBlock.substring(braceStart + 1, braceEnd).trim();
    }
  }

  // Split by commas, respecting nested generics
  final paramStrings = _splitParams(paramBlock);

  for (final paramStr in paramStrings) {
    final trimmed = paramStr.trim();
    if (trimmed.isEmpty) continue;

    final param = _parseParam(trimmed, sourceContent);
    if (param != null) {
      params.add(param);
    }
  }

  return params;
}

/// Split a parameter string by commas, respecting nested angle brackets and parens.
List<String> _splitParams(String input) {
  final results = <String>[];
  var depth = 0;
  var current = StringBuffer();

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '<' || ch == '(' || ch == '[') {
      depth++;
      current.write(ch);
    } else if (ch == '>' || ch == ')' || ch == ']') {
      depth--;
      current.write(ch);
    } else if (ch == ',' && depth == 0) {
      results.add(current.toString());
      current = StringBuffer();
    } else {
      current.write(ch);
    }
  }

  final last = current.toString().trim();
  if (last.isNotEmpty) results.add(last);

  return results;
}

/// Parse a single parameter declaration.
_ConstructorParam? _parseParam(String paramStr, String sourceContent) {
  final trimmed = paramStr.trim();

  // Skip super.key and key
  if (trimmed.contains('super.key') || trimmed == 'Key? key') return null;

  final isRequired = trimmed.startsWith('required ');
  final withoutRequired =
      isRequired ? trimmed.substring('required '.length).trim() : trimmed;

  // Check for default value
  final hasDefault = withoutRequired.contains('=');
  final withoutDefault = hasDefault
      ? withoutRequired.substring(0, withoutRequired.indexOf('=')).trim()
      : withoutRequired;

  // Pattern: this.paramName
  final thisPattern = RegExp(r'^this\.(\w+)$');
  final thisMatch = thisPattern.firstMatch(withoutDefault);
  if (thisMatch != null) {
    final paramName = thisMatch.group(1)!;
    final type = _inferTypeFromField(paramName, sourceContent);
    final isKey = paramName == 'key';
    return _ConstructorParam(
      name: paramName,
      type: type,
      isRequired: isRequired && !hasDefault,
      isKey: isKey,
    );
  }

  // Pattern: Type paramName or Type? paramName
  final typedPattern = RegExp(r'^(.+?)\s+(\w+)$');
  final typedMatch = typedPattern.firstMatch(withoutDefault);
  if (typedMatch != null) {
    final type = typedMatch.group(1)!.trim();
    final paramName = typedMatch.group(2)!;
    final isKey = paramName == 'key';
    return _ConstructorParam(
      name: paramName,
      type: type,
      isRequired: isRequired && !hasDefault,
      isKey: isKey,
    );
  }

  return null;
}

/// Infer the type of a field from `final Type name;` declarations in the source.
String _inferTypeFromField(String fieldName, String sourceContent) {
  // Match: final Type fieldName; or late Type fieldName; or Type fieldName;
  final fieldPattern = RegExp(
    '(?:final|late|late\\s+final)\\s+([\\w<>,?\\s]+?)\\s+$fieldName\\s*[;=]',
  );
  final match = fieldPattern.firstMatch(sourceContent);
  if (match != null) {
    return match.group(1)!.trim();
  }
  // Try without qualifier: Type fieldName;
  final barePattern = RegExp(
    '^\\s*([A-Z][\\w<>,?]*(?:\\s*<[^>]+>)?)\\s+$fieldName\\s*[;=]',
    multiLine: true,
  );
  final bareMatch = barePattern.firstMatch(sourceContent);
  if (bareMatch != null) {
    return bareMatch.group(1)!.trim();
  }
  return 'dynamic';
}

/// Find context-dependent / state management usage in the source.
List<_ContextDependency> _findContextDependencies(String sourceContent) {
  final deps = <_ContextDependency>[];
  final lines = sourceContent.split('\n');

  final patterns = [
    RegExp(r'context\.read\s*<([^>]+)>'),
    RegExp(r'context\.watch\s*<([^>]+)>'),
    RegExp(r'Provider\.of\s*<([^>]+)>'),
    RegExp(r'ref\.read\s*\('),
    RegExp(r'ref\.watch\s*\('),
    RegExp(r'context\.select\s*<([^>]+)>'),
    RegExp(r'BlocProvider\.of\s*<([^>]+)>'),
    RegExp(r'context\.read\s*\(\)'),
    RegExp(r'GetIt\.I\b'),
    RegExp(r'getIt\b.*\.get\b'),
  ];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // Skip comments
    if (line.trimLeft().startsWith('//')) continue;

    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        deps.add(_ContextDependency(
          usage: line.trim(),
          line: i + 1,
        ));
        break; // One match per line is enough
      }
    }
  }

  return deps;
}

/// Parse entries from the config file (same logic as list_command.dart).
List<_ParsedEntry> _parseEntries(String dartContent) {
  final entries = <_ParsedEntry>[];

  // Match page('name', WidgetClass(...)) or widget('name', WidgetClass(...))
  final singlePattern = RegExp(
    r'''\b(page|widget)\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:const\s+)?(\w+)''',
  );
  for (final match in singlePattern.allMatches(dartContent)) {
    entries.add(_ParsedEntry(
      type: match.group(1)!,
      name: match.group(2)!,
      widgetClassName: match.group(3),
    ));
  }

  // Match pages('name', states: [state('s', WidgetClass(...))])
  final groupPattern = RegExp(
    r'''\b(pages|widgets)\s*\(\s*['"]([^'"]+)['"]\s*,\s*states\s*:\s*\[([\s\S]*?)\]\s*[,)]''',
  );
  for (final match in groupPattern.allMatches(dartContent)) {
    final type = match.group(1)! == 'pages' ? 'page' : 'widget';
    final name = match.group(2)!;
    final statesBlock = match.group(3)!;

    // Get class name from first state
    final stateClassPattern = RegExp(
      r'''\bstate\s*\(\s*['"][^'"]+['"]\s*,\s*(?:const\s+)?(\w+)''',
    );
    final stateMatch = stateClassPattern.firstMatch(statesBlock);
    final className = stateMatch?.group(1);

    // Get state names
    final stateNamePattern = RegExp(r'''\bstate\s*\(\s*['"]([^'"]+)['"]''');
    final stateNames = <String>[];
    for (final sm in stateNamePattern.allMatches(statesBlock)) {
      stateNames.add(sm.group(1)!);
    }

    entries.add(_ParsedEntry(
      type: type,
      name: name,
      widgetClassName: className,
      states: stateNames,
    ));
  }

  return entries;
}

class _ParsedEntry {
  const _ParsedEntry({
    required this.type,
    required this.name,
    this.widgetClassName,
    this.states = const [],
  });
  final String type;
  final String name;
  final String? widgetClassName;
  final List<String> states;

  bool get isPage => type == 'page' || type == 'pages';
}

class _ConstructorParam {
  const _ConstructorParam({
    required this.name,
    required this.type,
    required this.isRequired,
    required this.isKey,
  });

  final String name;
  final String type;
  final bool isRequired;
  final bool isKey;

  bool get isCallback =>
      type == 'VoidCallback' ||
      type == 'VoidCallback?' ||
      type.startsWith('ValueChanged') ||
      type.startsWith('ValueSetter') ||
      type.startsWith('Function') ||
      type.contains('Function(') ||
      type.contains('Function?(') ||
      type.contains('=> ');

  /// Suggest a sensible default value for this parameter type.
  String get suggestion {
    // Callbacks
    if (type == 'VoidCallback' || type == 'VoidCallback?') return '() {}';
    if (type.startsWith('ValueChanged<') || type.startsWith('ValueSetter<')) {
      return '(_) {}';
    }
    if (type.startsWith('Function') || type.contains('Function(')) {
      return '() {}';
    }

    // Common Flutter types
    if (type == 'Key' || type == 'Key?') return "const ValueKey('test')";
    if (type == 'Widget' || type == 'Widget?') {
      return 'const SizedBox.shrink()';
    }
    if (type == 'IconData' || type == 'IconData?') return 'Icons.star';
    if (type == 'Color' || type == 'Color?') return 'Colors.blue';
    if (type == 'TextStyle' || type == 'TextStyle?') {
      return 'const TextStyle()';
    }
    if (type == 'EdgeInsets' || type == 'EdgeInsetsGeometry') {
      return 'EdgeInsets.zero';
    }

    // Primitives
    if (type == 'String' || type == 'String?') return "'Demo'";
    if (type == 'int' || type == 'int?') return '0';
    if (type == 'double' || type == 'double?') return '0.0';
    if (type == 'bool' || type == 'bool?') return 'false';
    if (type == 'num' || type == 'num?') return '0';

    // Collections
    if (type.startsWith('List<')) return "const []";
    if (type.startsWith('Map<')) return 'const {}';
    if (type.startsWith('Set<')) return 'const {}';

    // DateTime
    if (type == 'DateTime' || type == 'DateTime?') {
      return 'DateTime(2024, 1, 1)';
    }

    // Nullable types can be null
    if (type.endsWith('?')) return 'null';

    // Fallback
    return '/* provide $type */';
  }
}

class _ContextDependency {
  const _ContextDependency({
    required this.usage,
    required this.line,
  });
  final String usage;
  final int line;
}
