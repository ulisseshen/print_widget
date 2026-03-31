import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class SkillsCommand extends Command<void> {
  SkillsCommand() {
    argParser
      ..addFlag(
        'install',
        abbr: 'i',
        negatable: false,
        help: 'Install all skills (figma + stitch).',
      )
      ..addOption(
        'only',
        help: 'Install specific skills (comma-separated). E.g. figma, stitch.',
      )
      ..addOption(
        'scope',
        abbr: 's',
        help: 'Installation scope.',
        allowed: ['project', 'user'],
        defaultsTo: 'project',
      )
      ..addOption(
        'tool',
        abbr: 't',
        help: 'Target AI tool. Auto-detected if omitted.',
        allowed: ['claude', 'cursor', 'codex'],
      )
      ..addFlag(
        'list',
        abbr: 'l',
        negatable: false,
        help: 'List available skills without installing.',
      );
  }

  @override
  String get name => 'skills';

  @override
  String get description =>
      'Install AI assistant skills (Claude Code, Cursor, Codex).';

  @override
  Future<void> run() async {
    if (argResults!['list'] as bool) {
      _printSkillList();
      return;
    }

    // Resolve target tools
    final toolArg = argResults!['tool'] as String?;
    final List<_Tool> tools;

    if (toolArg != null) {
      // Explicit --tool flag bypasses detection
      tools = [_Tool.values.firstWhere((t) => t.id == toolArg)];
      stdout.writeln('');
      stdout.writeln('  Target: ${tools.first.displayName}');
      stdout.writeln('');
    } else {
      // Auto-detect installed AI tools
      final detected = _detectTools();

      stdout.writeln('');
      if (detected.isEmpty) {
        stdout.writeln('  No AI tools detected.');
        stdout.writeln('');
        stdout.writeln('  Checked for:');
        stdout.writeln('    Claude Code  ~/.claude/');
        stdout.writeln('    Cursor       .cursor/ or ~/.cursor/');
        stdout.writeln('    Codex        AGENTS.md or ~/.codex/');
        stdout.writeln('');
        stdout.writeln(
          '  Use --tool=claude|cursor|codex to install manually.',
        );
        exitCode = 1;
        return;
      }

      stdout.writeln('  Detected AI tools:');
      for (final t in detected) {
        stdout.writeln('    \u2713 ${t.displayName}');
      }
      stdout.writeln('');

      tools = detected;
    }

    // Resolve skills to install
    final installAll = argResults!['install'] as bool;
    final onlyArg = argResults!['only'] as String?;
    List<_Skill> skills;

    if (installAll) {
      // --install → install all skills
      skills = List.of(_skills);
      stdout.writeln('  Installing all skills...');
    } else if (onlyArg != null) {
      // --only=figma → install specific skills
      skills = _parseSkillIds(onlyArg);
      if (skills.isEmpty) return;
    } else {
      // No flags → interactive mode
      if (!stdin.hasTerminal) {
        stderr.writeln(
          'Interactive mode requires a terminal. '
          'Use --install (all) or --only=figma (specific).',
        );
        exitCode = 1;
        return;
      }
      skills = _promptSkills();
      if (skills.isEmpty) return;
    }

    // Resolve scope
    _Scope scope;
    if (argResults!.wasParsed('scope')) {
      scope = (argResults!['scope'] as String) == 'user'
          ? _Scope.user
          : _Scope.project;
    } else if (installAll || onlyArg != null) {
      scope = _Scope.project;
    } else {
      scope = _promptScope(tools);
    }

    // Read project config for template interpolation
    final config = _readConfig();

    // Install
    stdout.writeln('');
    var count = 0;
    for (final skill in skills) {
      for (final tool in tools) {
        if (_install(skill, tool, scope, config)) count++;
      }
    }
    stdout.writeln('');
    stdout.writeln(
      '  Done! $count skill file${count == 1 ? '' : 's'} installed.',
    );
  }

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  List<_Tool> _detectTools() {
    final home = Platform.environment['HOME'] ?? '';
    final tools = <_Tool>[];

    // Claude Code
    if (Directory('$home/.claude').existsSync() ||
        Directory('.claude').existsSync()) {
      tools.add(_Tool.claude);
    }

    // Cursor
    if (Directory('.cursor').existsSync() ||
        Directory('$home/.cursor').existsSync()) {
      tools.add(_Tool.cursor);
    }

    // Codex
    if (File('AGENTS.md').existsSync() ||
        Directory('.agents').existsSync() ||
        Directory('$home/.agents').existsSync() ||
        Directory('$home/.codex').existsSync()) {
      tools.add(_Tool.codex);
    }

    return tools;
  }

  // ---------------------------------------------------------------------------
  // Interactive prompts
  // ---------------------------------------------------------------------------

  List<_Skill> _promptSkills() {
    stdout.writeln('  Available skills:');
    for (var i = 0; i < _skills.length; i++) {
      final s = _skills[i];
      stdout.writeln('    [${i + 1}] ${s.id.padRight(12)} ${s.description}');
    }
    stdout.writeln('');
    stdout.write('  Select skills (comma-separated numbers, or "all"): ');

    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.isEmpty) {
      stdout.writeln('  No skills selected.');
      return [];
    }

    if (input.toLowerCase() == 'all') return List.of(_skills);

    final selected = <_Skill>[];
    for (final part in input.split(',')) {
      final n = int.tryParse(part.trim());
      if (n == null || n < 1 || n > _skills.length) {
        stderr.writeln('  Invalid selection: ${part.trim()}');
        exitCode = 1;
        return [];
      }
      selected.add(_skills[n - 1]);
    }
    return selected;
  }

  _Scope _promptScope(List<_Tool> tools) {
    final hasUserScope = tools.any((t) => t == _Tool.claude);
    if (!hasUserScope) return _Scope.project;

    stdout.writeln('');
    stdout.writeln('  Install scope:');
    stdout.writeln(
      '    [1] project   Git root .claude/skills/ (this project only)',
    );
    stdout.writeln(
      '    [2] user      ~/.claude/skills/ (all projects on this machine)',
    );
    stdout.write('  Select scope [1]: ');

    final input = stdin.readLineSync()?.trim() ?? '1';
    return input == '2' ? _Scope.user : _Scope.project;
  }

  // ---------------------------------------------------------------------------
  // Non-interactive parsing
  // ---------------------------------------------------------------------------

  List<_Skill> _parseSkillIds(String input) {
    final selected = <_Skill>[];
    for (final id in input.split(',').map((s) => s.trim())) {
      final skill = _skills.where((s) => s.id == id).firstOrNull;
      if (skill == null) {
        stderr.writeln('Unknown skill: $id');
        stderr.writeln(
          'Available: ${_skills.map((s) => s.id).join(', ')}',
        );
        exitCode = 1;
        return [];
      }
      selected.add(skill);
    }
    return selected;
  }

  // ---------------------------------------------------------------------------
  // List
  // ---------------------------------------------------------------------------

  void _printSkillList() {
    stdout.writeln('');
    stdout.writeln('  Available print-widget skills:');
    stdout.writeln('');
    for (final s in _skills) {
      stdout.writeln('    print-widget-${s.id}');
      stdout.writeln('      ${s.description}');
      stdout.writeln(
        '      Supports: ${s.supportedTools.map((t) => t.displayName).join(', ')}',
      );
      stdout.writeln('');
    }
    stdout.writeln(
        '  Each skill includes internal references (conventions, screen,');
    stdout.writeln('  review, iterate) that the AI reads automatically.');
    stdout.writeln('');
    stdout.writeln('  Install all:  print_widget skills --install');
    stdout.writeln('  Install one:  print_widget skills --only=figma');
    stdout.writeln('  Or run:       print_widget skills   (interactive)');
    stdout.writeln('');
    stdout.writeln('  Scope:');
    stdout.writeln(
      '    --scope=project  Git root .claude/skills/ (default, this project)',
    );
    stdout.writeln(
      '    --scope=user     ~/.claude/skills/ (all projects on this machine)',
    );
  }

  // ---------------------------------------------------------------------------
  // Config reading
  // ---------------------------------------------------------------------------

  _Config _readConfig() {
    var configPath = 'print_widget/config.dart';
    var outputDir = 'print_widget/output';

    final yamlFile = File('print_widget.yaml');
    if (yamlFile.existsSync()) {
      try {
        final yaml = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
        configPath = (yaml['config_file'] as String?) ?? configPath;
        outputDir = (yaml['output_dir'] as String?) ?? outputDir;
      } catch (_) {}
    }

    return _Config(configPath: configPath, outputDir: outputDir);
  }

  // ---------------------------------------------------------------------------
  // Installation
  // ---------------------------------------------------------------------------

  bool _install(_Skill skill, _Tool tool, _Scope scope, _Config config) {
    if (!skill.supportedTools.contains(tool)) return false;

    final path = _resolvePath(skill, tool, scope);
    final content = skill.template(tool, config);

    final file = File(path);
    if (file.existsSync()) {
      stdout.writeln('    [ok] $path \u2713');
      return false;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    stdout.writeln('    [installed] $path');

    // Write reference files alongside the main skill (Claude Code and Codex)
    if (skill.references.isNotEmpty &&
        (tool == _Tool.claude || tool == _Tool.codex)) {
      final dir = file.parent.path;
      for (final entry in skill.references.entries) {
        final refFile = File('$dir/${entry.key}');
        refFile.writeAsStringSync(entry.value(config));
        stdout.writeln('    [installed] $dir/${entry.key}');
      }
    }

    return true;
  }

  /// Detects the git repository root, or null if not in a git repo.
  String? _findGitRoot() {
    try {
      final result = Process.runSync(
        'git',
        ['rev-parse', '--show-toplevel'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return null;
  }

  String _resolvePath(_Skill skill, _Tool tool, _Scope scope) {
    final home = Platform.environment['HOME'] ?? '';
    final skillName = 'print-widget-${skill.id}';

    switch (tool) {
      case _Tool.claude:
        if (scope == _Scope.user) {
          return '$home/.claude/skills/$skillName/SKILL.md';
        }
        // Project scope: use git root so skills are visible to Claude Code
        final gitRoot = _findGitRoot();
        final base = gitRoot != null ? '$gitRoot/.claude' : '.claude';
        if (gitRoot != null && Directory.current.path != gitRoot) {
          stdout.writeln(
            '    [info] Git root: $gitRoot (installing skills there, '
            'not in ${Directory.current.path})',
          );
        }
        return '$base/skills/$skillName/SKILL.md';
      case _Tool.cursor:
        final gitRoot = _findGitRoot();
        final base = gitRoot ?? '.';
        return '$base/.cursor/rules/$skillName.mdc';
      case _Tool.codex:
        if (scope == _Scope.user) {
          return '$home/.agents/skills/$skillName/SKILL.md';
        }
        final gitRoot = _findGitRoot();
        final base = gitRoot != null ? '$gitRoot/.agents' : '.agents';
        return '$base/skills/$skillName/SKILL.md';
    }
  }
}

// =============================================================================
// Private types
// =============================================================================

enum _Tool {
  claude('claude', 'Claude Code'),
  cursor('cursor', 'Cursor'),
  codex('codex', 'Codex');

  const _Tool(this.id, this.displayName);
  final String id;
  final String displayName;
}

enum _Scope { project, user }

class _Config {
  final String configPath;
  final String outputDir;
  const _Config({required this.configPath, required this.outputDir});
}

class _Skill {
  final String id;
  final String description;
  final List<_Tool> supportedTools;
  final String Function(_Tool tool, _Config config) template;

  /// Internal reference files bundled with this skill (filename → content).
  final Map<String, String Function(_Config config)> references;

  const _Skill({
    required this.id,
    required this.description,
    required this.supportedTools,
    required this.template,
    this.references = const {},
  });
}

// =============================================================================
// Skill catalog
// =============================================================================

final _skills = <_Skill>[
  _Skill(
    id: 'figma',
    description:
        'Convert Figma designs to Flutter widgets with screenshot comparison loop',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _figmaTemplate,
    references: {
      'conventions.md': _conventionsRef,
      'screen.md': _screenRef,
      'review.md': _reviewRef,
      'iterate.md': _iterateRef,
    },
  ),
  _Skill(
    id: 'stitch',
    description:
        'Generate UI with Stitch (Google AI), implement in Flutter, verify with screenshots',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _stitchTemplate,
    references: {
      'conventions.md': _conventionsRef,
      'screen.md': _screenRef,
      'review.md': _reviewRef,
      'iterate.md': _iterateRef,
    },
  ),
];

// =============================================================================
// Skill templates
// =============================================================================

String _figmaTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _figmaClaude(config);
    case _Tool.cursor:
      return _figmaCursor(config);
    case _Tool.codex:
      return _figmaCodex(config);
  }
}

// -----------------------------------------------------------------------------
// figma — Claude Code command
// -----------------------------------------------------------------------------

String _figmaClaude(_Config c) => '''---
name: print-widget
description: Convert a Figma design into a Flutter widget with screenshot comparison loop
argument-hint: <figma-url-or-screenshot> [instructions]
---

Convert a Figma design into a Flutter widget and verify with print_widget screenshots.

## Input

\$ARGUMENTS

The user provides a Figma URL, screenshot path, or design description, optionally followed by instructions.

## Steps

1. **Get the design**: If a Figma URL was given, use the Figma MCP to fetch the frame. If a screenshot path, read the image. If a description, work from that.

2. **Save reference image** (for later visual comparison in VS Code):
   - **Figma URL**: After fetching the frame via MCP, download the exported PNG using Bash:
     ```bash
     mkdir -p ${c.outputDir}/<name>/.reference
     curl -sL "<export_url>" -o ${c.outputDir}/<name>/.reference/<device>.png
     ```
   - **File path provided**: Copy the image using Bash:
     ```bash
     mkdir -p ${c.outputDir}/<name>/.reference
     cp "<provided_path>" ${c.outputDir}/<name>/.reference/<device>.png
     ```
   - **Image pasted in chat**: The pasted image includes its source file path. Copy it using Bash:
     ```bash
     mkdir -p ${c.outputDir}/<name>/.reference
     cp "<source_path_from_pasted_image>" ${c.outputDir}/<name>/.reference/<device>.png
     ```
   - **Description only**: No reference image to save, skip this step.

3. **Analyze the design**: Identify layout structure, colors (exact hex), typography, spacing, and components.

4. **Build the Flutter widget**: Match the design using the project's theme and design system. Prefer `const` constructors. Follow any additional instructions provided.

5. **Add to print_widget config** at `${c.configPath}`:
   - Full screen → `page('screen_name', const ScreenWidget())`
   - Component → `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states → `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

6. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

7. **Visual validation loop** (autonomous — do NOT ask the user):
   a. Read the generated PNG at `${c.outputDir}/<name>/<device>.png`
   b. Compare it visually with the original design (Figma screenshot or reference image)
   c. Identify differences: layout, spacing, colors, typography, missing elements, alignment
   d. If differences found: fix the Flutter code, regenerate with `print_widget generate --name=<entry_name>`, read the new PNG, compare again
   e. Repeat until the screenshot matches the design or you've iterated 5 times
   f. After the loop: show the user the final screenshot and report what was matched/adjusted

## Working with existing widgets

If the target widget already exists in the codebase:
- **Extract, don't rewrite**: Refactor the existing widget to match the design. Extract sub-widgets into private `StatelessWidget` classes.
- **Mock as little as possible**: Use real data models, real theme, real components. Only mock external dependencies (network, platform channels).
- **Preserve behavior**: Keep existing callbacks, state management connections, and navigation intact. Only change the visual layer.

## Internal references

Read these files for detailed guidelines. They are bundled alongside this skill:
- `conventions.md` — Widget structure rules (composition over nesting, extraction, const constructors)
- `screen.md` — Screen patterns (callbacks, screen-provider separation, mock data for print_widget)
- `review.md` — Visual review checklist for auditing screenshots
- `iterate.md` — Visual iteration loop for refining the UI

## Tips

- Match exact hex colors from the design
- For responsive designs, generate with `--all-devices` to test multiple screen sizes
- If the design has multiple states (empty, loading, error, filled), use `pages()` with `state()` to capture all of them
- Read `${c.outputDir}/manifest.json` to find all generated PNG paths
''';

// -----------------------------------------------------------------------------
// figma — Cursor rule
// -----------------------------------------------------------------------------

String _figmaCursor(_Config c) => '''---
description: Guide for converting Figma designs to Flutter widgets using print_widget
globs:
  - "${c.configPath}"
  - "**/*_page.dart"
  - "**/*_screen.dart"
alwaysApply: false
---

# Figma to print_widget workflow

When implementing a UI from a Figma design in this project, follow this workflow:

## 1. Create the Flutter widget matching the design
- Match exact hex colors, spacing, and typography
- Use the project's theme and design system
- Prefer `const` constructors

## 2. Add it to print_widget config at `${c.configPath}`

For a full screen:
```dart
page('screen_name', const ScreenWidget()),
```

For a component:
```dart
widget('component_name', ComponentWidget(), size: Size(width, height)),
```

For multiple visual states:
```dart
pages('screen_name', states: [
  state('empty', ScreenWidget()),
  state('error', ScreenWidget(error: 'Something went wrong')),
  state('filled', ScreenWidget(data: mockData)),
]),
```

## 3. Save reference image (for VS Code comparison)
If you have a Figma export or design image, save it:
```bash
mkdir -p ${c.outputDir}/<name>/.reference
cp <image_path> ${c.outputDir}/<name>/.reference/<device>.png
```
If the user pasted an image, it includes the source file path — copy it directly. Skip if description only.

## 4. Generate and compare
```bash
print_widget generate --name=<entry_name>
```

Read the generated PNG at `${c.outputDir}/<name>/<device>.png`. Compare visually with the design.
If differences found: fix the code, regenerate, compare again. Repeat until match (max 5 iterations).
Show the user the final screenshot. VS Code extension auto-detects `.reference/` for pixel comparison.
''';

// -----------------------------------------------------------------------------
// figma — Codex instructions
// -----------------------------------------------------------------------------

String _figmaCodex(_Config c) => '''---
name: print-widget
description: Convert Figma designs to Flutter widgets with print_widget screenshot comparison
---

# print_widget: Figma Design Conversion

Input: \$ARGUMENTS

## Workflow

1. Get the Figma design (URL, screenshot, or description from arguments)
2. Save reference image for later comparison:
   - URL/file path: `mkdir -p ${c.outputDir}/<name>/.reference && cp/curl <source> ${c.outputDir}/<name>/.reference/<device>.png`
   - Image pasted: it includes the source file path — copy it directly.
   - Description only: skip.
3. Analyze layout, colors (exact hex), typography, and spacing
4. Build the Flutter widget matching the design
5. Add to `${c.configPath}`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
6. Run `print_widget generate --name=<name>`
7. Read generated PNG at `${c.outputDir}/<name>/<device>.png`. Compare visually with the design.
8. If differences found: fix code, regenerate, compare again. Repeat until match (max 5 iterations). Then show user the final result.
''';

// =============================================================================
// Stitch skill templates
// =============================================================================

String _stitchTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _stitchClaude(config);
    case _Tool.cursor:
      return _stitchCursor(config);
    case _Tool.codex:
      return _stitchCodex(config);
  }
}

// -----------------------------------------------------------------------------
// stitch — Claude Code command
// -----------------------------------------------------------------------------

String _stitchClaude(_Config c) => '''---
name: print-widget-stitch
description: Generate a UI screen with Stitch (Google AI) and verify with print_widget screenshots
argument-hint: <screen-description> [instructions]
---

Generate a UI screen with Stitch (Google AI), implement it in Flutter, and verify with print_widget screenshots.

## Input

\$ARGUMENTS

The user provides a screen description or requirements, optionally followed by additional instructions.

## Steps

1. **Generate design with Stitch**: Use the Stitch MCP to generate a design screen from the description.
   - Call `mcp__stitch__generate_screen_from_text` with the user's description to create a design.
   - If the user wants variants, call `mcp__stitch__generate_variants`.
   - If a design system should be applied, use `mcp__stitch__create_design_system` or `mcp__stitch__apply_design_system`.

2. **Save reference image** (for later visual comparison in VS Code):
   - Call `mcp__stitch__get_screen` to retrieve the generated screen.
   - Export the Stitch screen as PNG and save it:
     ```bash
     mkdir -p ${c.outputDir}/<name>/.reference
     # Save the exported PNG from Stitch
     cp "<exported_png_path>" ${c.outputDir}/<name>/.reference/<device>.png
     ```
   - If export is not available, skip this step.

3. **Analyze the design**: Identify layout structure, colors (exact hex), typography, spacing, and components from the Stitch output.

4. **Build the Flutter widget**: Match the Stitch design using the project's theme and design system. Prefer `const` constructors. Follow any additional instructions provided.

5. **Add to print_widget config** at `${c.configPath}`:
   - Full screen \u2192 `page('screen_name', const ScreenWidget())`
   - Component \u2192 `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states \u2192 `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

6. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

7. **Visual validation loop** (autonomous — do NOT ask the user):
   a. Read the generated PNG at `${c.outputDir}/<name>/<device>.png`
   b. Compare it visually with the Stitch design
   c. Identify differences: layout, spacing, colors, typography, missing elements
   d. If differences found: fix the Flutter code (or use `mcp__stitch__edit_screens` to refine the design), regenerate, compare again
   e. Repeat until the screenshot matches or you've iterated 5 times
   f. After the loop: show the user the final screenshot and report what was matched/adjusted

## Stitch MCP tools reference

- `mcp__stitch__generate_screen_from_text` \u2014 Generate a screen from a text description
- `mcp__stitch__edit_screens` \u2014 Edit existing screens
- `mcp__stitch__generate_variants` \u2014 Generate design variants
- `mcp__stitch__create_design_system` / `apply_design_system` \u2014 Design system management
- `mcp__stitch__get_screen` / `list_screens` \u2014 Read screens
- `mcp__stitch__create_project` / `get_project` / `list_projects` \u2014 Project management

## Working with existing widgets

If the target widget already exists in the codebase:
- **Extract, don't rewrite**: Refactor the existing widget to match the design. Extract sub-widgets into private `StatelessWidget` classes.
- **Mock as little as possible**: Use real data models, real theme, real components. Only mock external dependencies (network, platform channels).
- **Preserve behavior**: Keep existing callbacks, state management connections, and navigation intact. Only change the visual layer.

## Internal references

Read these files for detailed guidelines. They are bundled alongside this skill:
- `conventions.md` \u2014 Widget structure rules (composition over nesting, extraction, const constructors)
- `screen.md` \u2014 Screen patterns (callbacks, screen-provider separation, mock data for print_widget)
- `review.md` \u2014 Visual review checklist for auditing screenshots
- `iterate.md` \u2014 Visual iteration loop for refining the UI

## Tips

- Match exact hex colors from the Stitch design
- For responsive designs, generate with `--all-devices` to test multiple screen sizes
- If the design has multiple states (empty, loading, error, filled), use `pages()` with `state()` to capture all of them
- Read `${c.outputDir}/manifest.json` to find all generated PNG paths
- Use `mcp__stitch__generate_variants` to explore alternative designs before committing to one
''';

// -----------------------------------------------------------------------------
// stitch — Cursor rule
// -----------------------------------------------------------------------------

String _stitchCursor(_Config c) => '''---
description: Guide for generating UI with Stitch (Google AI) and verifying with print_widget
globs:
  - "${c.configPath}"
  - "**/*_page.dart"
  - "**/*_screen.dart"
alwaysApply: false
---

# Stitch to print_widget workflow

When generating UI with Stitch (Google AI) in this project, follow this workflow:

## 1. Generate the design with Stitch MCP
- Use `mcp__stitch__generate_screen_from_text` to create a design from a text description
- Use `mcp__stitch__get_screen` to retrieve the generated screen
- Optionally use `mcp__stitch__generate_variants` for alternative designs

## 2. Create the Flutter widget matching the Stitch design
- Match exact hex colors, spacing, and typography
- Use the project's theme and design system
- Prefer `const` constructors

## 3. Add it to print_widget config at `${c.configPath}`

For a full screen:
```dart
page('screen_name', const ScreenWidget()),
```

For a component:
```dart
widget('component_name', ComponentWidget(), size: Size(width, height)),
```

For multiple visual states:
```dart
pages('screen_name', states: [
  state('empty', ScreenWidget()),
  state('error', ScreenWidget(error: 'Something went wrong')),
  state('filled', ScreenWidget(data: mockData)),
]),
```

## 4. Save reference image (for VS Code comparison)
If you exported a PNG from Stitch, save it:
```bash
mkdir -p ${c.outputDir}/<name>/.reference
cp <image_path> ${c.outputDir}/<name>/.reference/<device>.png
```

## 5. Generate and compare
```bash
print_widget generate --name=<entry_name>
```

Read the generated PNG at `${c.outputDir}/<name>/<device>.png`. Compare visually with the Stitch design.
If differences found: fix the code or use `mcp__stitch__edit_screens`, regenerate, compare again. Repeat until match (max 5).
Show the user the final screenshot. VS Code extension auto-detects `.reference/` for pixel comparison.
''';

// -----------------------------------------------------------------------------
// stitch — Codex instructions
// -----------------------------------------------------------------------------

String _stitchCodex(_Config c) => '''---
name: print-widget-stitch
description: Generate UI with Stitch (Google AI) and verify with print_widget screenshots
---

# print_widget: Stitch Design Generation

Input: \\\$ARGUMENTS

## Workflow

1. Generate a design with Stitch MCP (`mcp__stitch__generate_screen_from_text`)
2. Retrieve the screen with `mcp__stitch__get_screen`
3. Save reference image: `mkdir -p ${c.outputDir}/<name>/.reference && cp <exported_png> ${c.outputDir}/<name>/.reference/<device>.png`
4. Analyze layout, colors (exact hex), typography, and spacing from the Stitch output
5. Build the Flutter widget matching the design
6. Add to `${c.configPath}`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
7. Run `print_widget generate --name=<name>`
8. Read generated PNG at `${c.outputDir}/<name>/<device>.png`. Compare visually with the Stitch design.
9. If differences found: fix code or use `mcp__stitch__edit_screens`, regenerate, compare again. Repeat until match (max 5). Show user the final result.
''';

// =============================================================================
// Internal reference files (bundled alongside skill SKILL.md)
// =============================================================================

String _conventionsRef(_Config c) => '''# Widget Conventions

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain. Deep nesting hides intent.

## Rules

- **3-level rule**: Subtree deeper than 3 levels \u2192 extract to `_WidgetName extends StatelessWidget`
- **4+ children rule**: Column/Row/ListView with 4+ children \u2192 extract each child
- **Card decomposition**: Header + body + footer \u2192 3 separate private widgets
- **No `_buildXxx()` methods**: Always extract to private `StatelessWidget` classes
- **Const constructors**: All `StatelessWidget` subclasses with no required mutable params \u2192 `const`
- **Component-first**: Check the project\u2019s component library before building from scratch
- **Promote when reused**: Private widget used by 2+ features \u2192 move to shared location

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don't start from scratch.
- **Mock as little as possible**: Use real data and theme. Only mock external dependencies (network, platform channels).
- **GoRouter ancestor**: Widgets using navigation (`context.go()`, `GoRouterState.of()`) need `MaterialApp.router` with `GoRouter` in the `appWrapper` \u2014 not plain `MaterialApp`
''';

String _screenRef(_Config c) => '''# Screen Patterns

## Callbacks over hardcoded logic

Screens are presentation-only. Data in, callbacks out. No business logic, navigation, or API calls.

| Type | Use case |
|------|----------|
| `VoidCallback?` | Button press, tap, form submit |
| `ValueChanged<T>?` | Text field, toggle, selection |
| `ValueSetter<int>?` | Index-based (tabs, pages) |

Pass `null` to disable an action.

## Screen-provider separation

- **Screen**: Pure `StatelessWidget` receiving data + callbacks. Testable, previewable with print_widget.
- **Page**: Connects state management to the screen.

## Mock data for print_widget

In `${c.configPath}`, populate all states with representative data:
- Use representative values ("Sarah Johnson", not "User 1")
- Lists: 3\u20135 items to show scrolling
- All visual states: empty, loading, filled, error, disabled

## Working with existing screens

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don't start over.
- **Mock as little as possible**: Pass real data models. Only mock external systems.
- **Preserve the Page**: Only modify the Screen (presentation). Keep the wiring intact.

## Mock patterns for full page rendering

### Progressive mock \u2014 start with noSuchMethod

When a page depends on providers, start with a catch-all mock and add overrides as errors appear:

```dart
class _AppMock implements MyProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

If a method returns `Future<void>`, `noSuchMethod` returning null will crash. Use an async-safe base:

```dart
class _AsyncSafeMock implements MyProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final returnType = invocation.memberName;
    // For Future-returning methods, return completed future
    return Future<void>.value();
  }
}
```

Then add overrides as type errors appear:
```dart
@override
int get menuOpened => -1;

@override
String get currentUserId => 'mock-user-id';

@override
List<Order> get orders => [];
```

### Full page shell \u2014 GoRouter + Providers + Scaffold

For capturing a complete page with AppBar, Sidebar, and navigation:

```dart
appWrapper: (child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MyProvider>.value(value: _AppMock()),
      // Add all required providers
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: '/my-page',
        routes: [
          GoRoute(
            path: '/my-page',
            builder: (context, state) => child,
          ),
        ],
      ),
    ),
  );
},
```

If the page needs a Scaffold shell (AppBar + Sidebar):
```dart
builder: (context, state) => Scaffold(
  body: Row(children: [
    const SideBar(),
    Expanded(child: Column(children: [
      const CustomAppBar(),
      Expanded(child: child),
    ])),
  ]),
),
```

### GoRouter as required ancestor

Widgets using `context.go()`, `GoRouterState.of(context)`, or any navigation REQUIRE `MaterialApp.router` with `GoRouter` in the tree. Without it, the widget crashes with "GoRouter not found". Always use `MaterialApp.router` (not `MaterialApp`) when the widget uses navigation.
''';

String _reviewRef(_Config c) => '''# Visual Review Checklist

After generating screenshots, review each one for:

**Layout**: Alignment, spacing, overflow, safe areas
**Typography**: Readability, hierarchy, truncation
**Colors**: Consistency, contrast, no missing tokens
**States**: Empty, error, loading, filled all look correct
**Responsiveness**: Adapts across devices (if `--all-devices`)

## Verdict per entry

- **Pass**: No issues found
- **Warnings**: Minor issues (tight spacing, could be improved)
- **Needs fix**: Layout broken, text cut off, wrong colors, missing states
''';

String _iterateRef(_Config c) => '''# Visual Iteration Loop

1. Generate: `print_widget generate --name=<entry>`
2. Read PNGs from `${c.outputDir}/manifest.json`
3. Review: layout, colors, spacing, typography
4. Ask user what needs fixing
5. Fix code, regenerate with `--delete-old`
6. Confirm with user. Repeat until satisfied.

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets
- **Mock as little as possible**: Use real data, theme, components
- **Preserve behavior**: Keep callbacks, state management, navigation intact
''';
