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
        allowed: ['claude', 'cursor', 'codex', 'antigravity'],
      )
      ..addFlag(
        'list',
        abbr: 'l',
        negatable: false,
        help: 'List available skills without installing.',
      )
      ..addFlag(
        'update',
        abbr: 'u',
        negatable: false,
        help: 'Update all installed skills to the latest version.',
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

    final isUpdate = argResults!['update'] as bool;

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
        stdout.writeln('    Claude Code   ~/.claude/');
        stdout.writeln('    Cursor        .cursor/ or ~/.cursor/');
        stdout.writeln('    Codex         AGENTS.md or ~/.codex/');
        stdout.writeln('    Antigravity   .agent/ or ~/.gemini/antigravity/');
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

    // Handle --update: find and overwrite all installed skills
    if (isUpdate) {
      final config = _readConfig();
      stdout.writeln('  Updating installed skills...');
      stdout.writeln('');
      var count = 0;
      for (final skill in _skills) {
        for (final tool in tools) {
          for (final scope in _Scope.values) {
            final path = _resolvePath(skill, tool, scope);
            if (File(path).existsSync()) {
              _install(skill, tool, scope, config, force: true);
              count++;
            }
          }
        }
      }
      stdout.writeln('');
      if (count == 0) {
        stdout.writeln(
          '  No installed skills found. Run "print_widget skills --install" first.',
        );
      } else {
        stdout.writeln(
          '  Done! Updated $count skill${count == 1 ? '' : 's'} to latest version.',
        );
      }
      return;
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

    // Antigravity
    if (Directory('.agent').existsSync() ||
        Directory('$home/.gemini/antigravity').existsSync() ||
        File('GEMINI.md').existsSync()) {
      tools.add(_Tool.antigravity);
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
    final hasUserScope = tools.any(
      (t) => t == _Tool.claude || t == _Tool.antigravity,
    );
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

  bool _install(
    _Skill skill,
    _Tool tool,
    _Scope scope,
    _Config config, {
    bool force = false,
  }) {
    if (!skill.supportedTools.contains(tool)) return false;

    final path = _resolvePath(skill, tool, scope);
    final content = skill.template(tool, config);

    final file = File(path);
    if (file.existsSync() && !force) {
      stdout.writeln('    [ok] $path \u2713');
      return false;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    stdout.writeln('    [${force ? 'updated' : 'installed'}] $path');

    // Write reference files alongside the main skill (SKILL.md-based tools)
    if (skill.references.isNotEmpty &&
        (tool == _Tool.claude ||
            tool == _Tool.codex ||
            tool == _Tool.antigravity)) {
      final dir = file.parent.path;
      for (final entry in skill.references.entries) {
        final refFile = File('$dir/${entry.key}');
        refFile.writeAsStringSync(entry.value(config));
        stdout.writeln(
            '    [${force ? 'updated' : 'installed'}] $dir/${entry.key}');
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
    final skillName =
        skill.id == 'main' ? 'print-widget' : 'print-widget-${skill.id}';

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
      case _Tool.antigravity:
        if (scope == _Scope.user) {
          return '$home/.gemini/antigravity/skills/$skillName/SKILL.md';
        }
        final gitRoot = _findGitRoot();
        final base = gitRoot != null ? '$gitRoot/.agent' : '.agent';
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
  codex('codex', 'Codex'),
  antigravity('antigravity', 'Antigravity');

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
    id: 'main',
    description:
        'Capture Flutter widgets as screenshots — figma conversion, stitch generation, and self-update',
    supportedTools: [
      _Tool.claude,
      _Tool.cursor,
      _Tool.codex,
      _Tool.antigravity
    ],
    template: _mainTemplate,
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

String _mainTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _mainClaude(config);
    case _Tool.cursor:
      return _mainCursor(config);
    case _Tool.codex:
    case _Tool.antigravity:
      return _mainCodex(config);
  }
}

// -----------------------------------------------------------------------------
// figma — Claude Code command
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Unified main skill — Claude Code
// -----------------------------------------------------------------------------

String _mainClaude(_Config c) => '''---
name: print-widget
description: Capture Flutter widgets as screenshots — convert Figma designs, generate with Stitch, or self-update
argument-hint: <figma|stitch|update> [url-or-description] [instructions]
---

Capture Flutter widgets as PNG screenshots for visual verification. Route by first argument:

- `figma <url-or-screenshot> [instructions]` — Convert a Figma design into a Flutter widget
- `stitch <description> [instructions]` — Generate a UI with Stitch (Google AI), implement and verify
- `update` — Update print_widget CLI and skill files to latest version

Parse the first word of \$ARGUMENTS to determine which workflow to run.

---

# figma workflow

Convert a Figma design into a Flutter widget and verify with print_widget screenshots.

## Input

\$ARGUMENTS

The user provides a Figma URL, screenshot path, or design description, optionally followed by instructions.

## Steps

1. **Get the design**: If a Figma URL was given, use the Figma MCP to fetch the frame. If a screenshot path, read the image. If a description, work from that.
   - **Large design context warning**: Figma MCP responses can exceed 100K characters for complex frames. If the response is very large, fetch individual sub-nodes instead of the entire frame.

2. **Save reference image** (MANDATORY — not optional):
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

3. **Extract color mapping** (do this BEFORE writing any code):
   - From the Figma design context, extract ALL `bg-[...]` and `text-[color:...]` values
   - Create a color mapping table: each Figma token → project DS token
   - Example:
     ```
     Figma bg-[#1E1E2E]  → AppColors.surfacePrimary
     Figma text-[#A0A0B0] → AppColors.textSecondary
     Figma bg-[#2A2A3E]  → AppColors.cardBackground
     ```
   - If no DS token exists for a Figma color, flag it to the user — NEVER use hardcoded `Color()` values

4. **Extract padding & spacing**:
   - Search for `gap-[]`, `p-[]`, `px-[]`, `py-[]` in the design context
   - Map each to Flutter `EdgeInsets` values
   - Check shell padding, content padding, and card padding separately

5. **Completeness check**: List ALL sections/components visible in the Figma design. Check each one exists in your planned implementation. Flag any missing sections BEFORE writing code.

6. **Build the Flutter widget**:
   - Use the color mapping from step 3 — DS tokens only, never hardcoded `Color()`
   - **Exact character matching**: Copy exact characters from Figma (breadcrumb separators like ›, currency symbols like \$, em dashes, etc.). Do not retype or approximate.
   - **Positive/negative value coloring**: Values with "-" prefix → red (negative/loss color). Values with "+" prefix → green (positive/gain color). This is a universal financial UI pattern.
   - **SVG icon consistency**: MaterialIcons have thick strokes. If mixing with SVG icons, use `stroke-width: 1.2–1.5` on SVGs for visual consistency.
   - Prefer `const` constructors. Follow any additional instructions provided.

7. **Add to print_widget config** at `${c.configPath}`:
   - Full screen → `page('screen_name', const ScreenWidget())`
   - Component → `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states → `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

8. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

9. **Visual validation loop** (autonomous — do NOT ask the user):
   a. Read the generated PNG at `${c.outputDir}/<name>/<device>.png`
   b. Compare it against the Figma reference using the review.md checklist (backgrounds, text colors, padding, borders, icons, typography, layout)
   c. List ALL remaining differences — do not stop at the first one
   d. Fix ALL differences in one batch, then regenerate with `print_widget generate --name=<entry_name>`
   e. Read the new PNG, compare again
   f. Repeat until the checklist is 100% verified or you have iterated 5 times
   g. After the loop: show the user the final screenshot with a verification report

10. **Save novel patterns**: If you discovered a new workaround or pattern during this task, save it to the project\u2019s CLAUDE.md for future sessions.

## Working with existing widgets

If the target widget already exists in the codebase:
- **Extract, don't rewrite**: Refactor the existing widget to match the design. Extract sub-widgets into private `StatelessWidget` classes.
- **Mock as little as possible**: Use real data models, real theme, real components. Only mock external dependencies (network, platform channels).
- **Preserve behavior**: Keep existing callbacks, state management connections, and navigation intact. Only change the visual layer.

## Internal references

Read these files for detailed guidelines. They are bundled alongside this skill:
- `conventions.md` — Widget structure rules (composition, extraction, behavioral rules)
- `screen.md` — Screen patterns (callbacks, providers, mock data, toggle states)
- `review.md` — Visual review checklist (layer-by-layer verification)
- `iterate.md` — Visual iteration loop (systematic checklist-based refinement)

## Tips

- Match exact hex colors from the design — always via DS tokens
- For responsive designs, generate with `--all-devices` to test multiple screen sizes
- If the design has multiple states (empty, loading, error, filled), use `pages()` with `state()` to capture all of them
- Read `${c.outputDir}/manifest.json` to find all generated PNG paths

---

# stitch workflow

Generate a UI screen with Stitch (Google AI), implement it in Flutter, and verify with print_widget screenshots.

## Steps

1. **Generate design with Stitch**: Use `mcp__stitch__generate_screen_from_text` with the description.
   - Optionally use `mcp__stitch__generate_variants` for alternatives.
   - Apply design system with `mcp__stitch__apply_design_system` if available.

2. **Save reference image**: Export the Stitch screen as PNG:
   ```bash
   mkdir -p ${c.outputDir}/<name>/.reference
   cp "<exported_png_path>" ${c.outputDir}/<name>/.reference/<device>.png
   ```

3. **Analyze the design**: Extract layout, colors, typography, spacing from the Stitch output.

4. **Build the Flutter widget**: Match the Stitch design using DS tokens. Follow all conventions from the figma workflow (color mapping, exact chars, etc.).

5. **Add to print_widget config** at `${c.configPath}` (same as figma workflow).

6. **Generate and validate**: Same visual validation loop as figma (generate, read PNG, verify with review.md checklist, fix, repeat).

## Stitch MCP tools

- `mcp__stitch__generate_screen_from_text` — Generate screen from text
- `mcp__stitch__edit_screens` — Edit existing screens
- `mcp__stitch__generate_variants` — Generate design variants
- `mcp__stitch__create_design_system` / `apply_design_system` — DS management
- `mcp__stitch__get_screen` / `list_screens` — Read screens

---

# update workflow

Update print_widget to the latest version.

## Steps

1. **Update the CLI**: `dart pub global activate print_widget_flutter`
2. **Verify version**: `print_widget --version`
3. **Update installed skills**: `print_widget skills --update`
4. **Verify**: `print_widget generate`
''';

// -----------------------------------------------------------------------------
// Unified main skill — Cursor rule
// -----------------------------------------------------------------------------

String _mainCursor(_Config c) => '''---
description: Guide for converting Figma designs to Flutter widgets using print_widget
globs:
  - "${c.configPath}"
  - "**/*_page.dart"
  - "**/*_screen.dart"
alwaysApply: false
---

# Figma to print_widget workflow

When implementing a UI from a Figma design in this project, follow this workflow:

## 1. Extract design tokens BEFORE coding
- Extract ALL background colors, text colors, padding values from the Figma design
- Map each Figma token to a project DS token — never use hardcoded `Color()` values
- Copy exact characters from Figma (separators, currency symbols) — don\u2019t retype
- List ALL sections visible in the design and verify each will be implemented

## 2. Create the Flutter widget matching the design
- Use DS tokens from the mapping — never hardcoded colors
- Match exact hex colors, spacing, and typography
- Prefer `const` constructors
- Cards in same Row: use `IntrinsicHeight` + `CrossAxisAlignment.stretch`
- Positive values → green, negative values → red (financial UI pattern)
- Generate after EACH visual change, not in batches

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

## 4. Save reference image (MANDATORY for VS Code comparison)
```bash
mkdir -p ${c.outputDir}/<name>/.reference
cp <image_path> ${c.outputDir}/<name>/.reference/<device>.png
```
If the user pasted an image, it includes the source file path — copy it directly. Skip if description only.

## 5. Generate and compare (layer-by-layer)
```bash
print_widget generate --name=<entry_name>
```

Read the generated PNG at `${c.outputDir}/<name>/<device>.png`. Compare using the verification checklist:
backgrounds (outside-in) → text colors → padding → borders → icons → typography → layout.
List ALL differences, fix them, regenerate, repeat until match (max 5 iterations).
Show the user the final screenshot. VS Code extension auto-detects `.reference/` for pixel comparison.

## Update workflow
1. Update CLI: `dart pub global activate print_widget_flutter`
2. Update skills: `print_widget skills --update`
3. Verify: `print_widget generate`
''';

// -----------------------------------------------------------------------------
// Unified main skill — Codex / Antigravity
// -----------------------------------------------------------------------------

String _mainCodex(_Config c) => '''---
name: print-widget
description: Capture Flutter widgets as screenshots — figma conversion, stitch generation, or self-update
---

# print_widget

Input: \$ARGUMENTS

Route by first word: `figma`, `stitch`, or `update`.

## figma workflow

1. Get the Figma design (URL, screenshot, or description)
2. Save reference image (MANDATORY):
   - URL/file path: `mkdir -p ${c.outputDir}/<name>/.reference && cp/curl <source> ${c.outputDir}/<name>/.reference/<device>.png`
   - Image pasted: copy from source path. Description only: skip.
3. Extract ALL colors and padding. Map to DS tokens — never hardcoded `Color()`. Copy exact chars.
4. List ALL sections. Verify each will be implemented.
5. Build widget using DS tokens. Positive values → green, negative → red.
6. Add to `${c.configPath}`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
7. Run `print_widget generate --name=<name>`
8. Read generated PNG at `${c.outputDir}/<name>/<device>.png`. Compare layer-by-layer: backgrounds → text colors → padding → borders → icons → typography → layout.
9. List ALL differences, fix them, regenerate, repeat until match (max 5). Show user final result.
10. Save novel patterns to CLAUDE.md for future sessions.

## stitch workflow

1. Generate design with Stitch MCP (`mcp__stitch__generate_screen_from_text`)
2. Save reference image: `mkdir -p ${c.outputDir}/<name>/.reference && cp <png> ${c.outputDir}/<name>/.reference/<device>.png`
3. Analyze layout, colors, typography, spacing from Stitch output
4. Build widget using DS tokens. Same validation loop as figma.
5. Add to `${c.configPath}` (same format as figma).
6. Generate, compare, iterate (max 5). Show final result.

Stitch MCP tools: `generate_screen_from_text`, `edit_screens`, `generate_variants`, `apply_design_system`, `get_screen`.

## update workflow

1. Update CLI: `dart pub global activate print_widget_flutter`
2. Update skills: `print_widget skills --update`
3. Verify: `print_widget generate`
''';

// =============================================================================
// Internal reference files (bundled alongside skill SKILL.md)
// =============================================================================

String _conventionsRef(_Config c) => '''# Widget Conventions

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain. Deep nesting hides intent.

## Structure rules

- **3-level rule**: Subtree deeper than 3 levels \u2192 extract to `_WidgetName extends StatelessWidget`
- **4+ children rule**: Column/Row/ListView with 4+ children \u2192 extract each child
- **Card decomposition**: Header + body + footer \u2192 3 separate private widgets
- **No `_buildXxx()` methods**: Always extract to private `StatelessWidget` classes
- **Const constructors**: All `StatelessWidget` subclasses with no required mutable params \u2192 `const`
- **Component-first**: Check the project\u2019s component library before building from scratch
- **Promote when reused**: Private widget used by 2+ features \u2192 move to shared location

## Behavioral rules (from real-world feedback)

- **IntrinsicHeight for equal-height cards**: Cards in the same Row need `IntrinsicHeight` + `CrossAxisAlignment.stretch` to match heights
- **Never add wrappers not in Figma**: Before adding Container, Card, or any wrapper widget, verify it exists as a node in the Figma design. Unnecessary wrappers add backgrounds, padding, or borders that break the match.
- **Never blanket-apply style changes**: Scope each fix to the specific component. After fixing one widget, verify that sibling widgets are unaffected.
- **Never guess, always verify**: ALWAYS check the Figma design context for actual values (colors, spacing, sizes). Never assume or approximate.
- **Copy-paste node names**: Don\u2019t retype Figma node names \u2014 copy them exactly. Typos cause silent mismatches.
- **Never remove functionality as a workaround**: If a widget causes issues (e.g. AnimatedDefaultTextStyle), find an alternative implementation (e.g. TweenAnimationBuilder) instead of removing the feature.
- **Ask before uncertain color changes**: When the design context is ambiguous about a color, show the user what you plan to change and ask BEFORE modifying code.
- **Generate after EACH visual change**: Do not batch multiple visual changes. Make one change, generate, verify, then proceed. This isolates regressions.
- **Save novel solutions to CLAUDE.md**: When you discover a new pattern or workaround, persist it to the project\u2019s CLAUDE.md so it\u2019s available in future sessions.

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don\u2019t start from scratch.
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

## Tracing widget dependencies

Before building a mock or appWrapper, trace what the widget actually needs:

```bash
# Find provider reads in the widget file
grep -n "context.read\\|context.watch\\|ref.read\\|ref.watch\\|Provider.of" lib/path/to/widget.dart

# Find inherited widgets
grep -n "Theme.of\\|MediaQuery.of\\|Navigator.of\\|Scaffold.of" lib/path/to/widget.dart
```

Start with the minimum set. Add providers only as errors appear during generation.

## Design system component customization

When a DS component almost matches but needs tweaking, choose one of these approaches (in order of preference):

1. **Add parameter to DS component** (recommended): If the DS component is yours, add an optional parameter for the customization. This keeps the design system as the single source of truth.
2. **Wrap in Container/Padding**: For spacing-only adjustments, wrap the DS component. Never modify its internal padding.
3. **Fork the component**: Last resort. Copy the DS component and modify. Document why in a comment.

Avoid option 3 unless the customization is fundamentally incompatible with the DS component\u2019s API.

## Toggle state pattern

Capture expanded/collapsed or on/off states using `pages()` with `state()` and the `setup` callback:

```dart
pages('settings_panel', states: [
  state('collapsed', const SettingsPanel()),
  state(
    'expanded',
    const SettingsPanel(),
    setup: (tester) async {
      // Tap the expand button to toggle state
      await tester.tap(find.byKey(const Key('expand_toggle')));
      await tester.pumpAndSettle();
    },
  ),
]),
```

The `setup` callback runs after `pumpAndSettle()`, so the widget is fully built before interaction. Use it for:
- Tapping toggles, accordions, expandable sections
- Scrolling to specific positions
- Entering text in form fields
- Selecting tabs or navigation items
''';

String _reviewRef(_Config c) => '''# Visual Review Checklist

Systematic, layer-by-layer verification of generated screenshots against the design.

## Verification order (outside-in)

Work through each section in order. Never declare "all colors match" without enumerating EVERY colored element.

### 1. Backgrounds (layer by layer)
- [ ] Shell / page background
- [ ] Sidebar background
- [ ] Content area background
- [ ] Card backgrounds (each card independently)
- [ ] Nested container backgrounds (modals, dropdowns, tooltips)

### 2. Text colors
- [ ] Titles / headings
- [ ] Body text / descriptions
- [ ] Values / metrics (numeric displays)
- [ ] Comparison values (red = negative, green = positive)
- [ ] Links / interactive text
- [ ] Placeholder / hint text
- [ ] Disabled text

### 3. Spacing & padding
- [ ] Shell to sidebar padding
- [ ] Shell to content area padding
- [ ] Internal card padding (top, right, bottom, left)
- [ ] Gaps between cards
- [ ] Gaps between text elements
- [ ] Section spacing

### 4. Borders & dividers
- [ ] Border colors (must use DS tokens, not hardcoded)
- [ ] Border radius values
- [ ] Divider lines (color, thickness)
- [ ] Card elevation / shadows

### 5. Icons
- [ ] Icons render correctly (no squares / missing glyphs)
- [ ] Icon sizes match design
- [ ] Icon colors match design
- [ ] SVG vs MaterialIcon stroke weight consistency

### 6. Typography
- [ ] Font families loaded correctly
- [ ] Font weights (bold, semibold, regular, light)
- [ ] Font sizes match design
- [ ] Line heights / letter spacing
- [ ] Text truncation / overflow behavior

### 7. Layout & alignment
- [ ] Horizontal alignment (start, center, end)
- [ ] Vertical alignment within rows
- [ ] Cards in same Row have equal height (IntrinsicHeight)
- [ ] Responsive behavior across breakpoints
- [ ] Safe areas respected
- [ ] No overflow warnings

## Rules

- **Layer-by-layer**: Verify backgrounds outside-in (Shell > Sidebar > Content > Cards)
- **Enumerate everything**: List every colored element explicitly — do not summarize
- **Track progress**: Mark which sections are verified vs still unchecked
- **Never skip**: Every checkbox must be explicitly passed or flagged as "not applicable"

## Verdict per entry

- **Pass**: All applicable checkboxes verified, no issues
- **Warnings**: Minor issues (tight spacing, slight color mismatch)
- **Needs fix**: Layout broken, text cut off, wrong colors, missing elements
''';

String _iterateRef(_Config c) => '''# Visual Iteration Loop

Systematic, checklist-driven refinement loop. Do NOT ask the user between iterations — run autonomously until the checklist is fully verified or 5 iterations are reached.

## Loop steps

1. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry>
   ```

2. **Read the PNG**: Read the generated image at `${c.outputDir}/<name>/<device>.png`

3. **Verify section by section** using the review.md checklist:
   - [ ] Backgrounds (shell → sidebar → content → cards)
   - [ ] Text colors (titles, body, values, comparison values, links, disabled)
   - [ ] Spacing & padding (shell, content, cards, gaps)
   - [ ] Borders & dividers (colors, radius, shadows)
   - [ ] Icons (rendering, sizes, colors)
   - [ ] Typography (families, weights, sizes, line heights)
   - [ ] Layout & alignment (horizontal, vertical, equal heights, overflow)

4. **For EACH section**: Compare against the Figma reference image or design context

5. **List ALL remaining differences** — do not stop at the first one. Group them:
   - Critical: wrong colors, missing elements, broken layout
   - Minor: slight spacing, subtle weight difference

6. **Fix ALL differences in one batch**: Make all code changes, then regenerate once

7. **Regenerate**:
   ```bash
   print_widget generate --name=<entry>
   ```

8. **Read the new PNG and compare again** — go back to step 3

9. **Repeat** until the checklist is 100% verified (all sections pass) or you have reached 5 iterations

10. **Show user the final screenshot** with a verification report:
    - Which sections pass
    - Any remaining minor differences
    - What was changed across all iterations

## Rules

- **Autonomous**: Do NOT ask the user between iterations. Only show the final result.
- **One change, one verify**: For the FIRST iteration, generate after each visual change to isolate issues. After that, batch fixes are OK.
- **Never declare done prematurely**: Every checklist item must be explicitly verified, not assumed.
- **Scope each fix**: When fixing one element, verify that sibling elements are unaffected.

## Working with existing widgets

- **Extract, don\u2019t rewrite**: Refactor by extracting sub-widgets
- **Mock as little as possible**: Use real data, theme, components
- **Preserve behavior**: Keep callbacks, state management, navigation intact
''';
