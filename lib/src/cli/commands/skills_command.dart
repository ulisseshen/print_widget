import 'dart:io';
import 'dart:isolate';

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

    // Resolve extract.mjs via package URI before any reference template
    // is rendered. Works under `dart pub global activate` where
    // Platform.script points at a snapshot shim in ~/.pub-cache/bin.
    await _populateExtractScriptCache();

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
        refFile.parent.createSync(recursive: true);
        refFile.writeAsStringSync(entry.value(config));
        stdout.writeln(
            '    [${force ? 'updated' : 'installed'}] $dir/${entry.key}');
      }
    }

    return true;
  }

  /// Populates [_cachedExtractScript] by resolving the package URI for
  /// `extract.mjs`. This is the reliable path for `dart pub global activate`
  /// installs, where `Platform.script` points at a snapshot shim rather
  /// than the actual source file.
  Future<void> _populateExtractScriptCache() async {
    if (_cachedExtractScript != null) return;
    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:print_widget_flutter/src/tools/extract.mjs'),
      );
      if (uri != null) {
        final file = File.fromUri(uri);
        if (file.existsSync()) {
          _cachedExtractScript = file.readAsStringSync();
        }
      }
    } catch (_) {
      // Fall through — _extractScriptRef has its own heuristic fallback.
    }
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
      'compare.md': _compareRef,
      'viewport.md': _viewportRef,
      'parallel.md': _parallelRef,
      'lovable.md': _lovableRef,
    },
  ),
  _Skill(
    id: 'extract',
    description:
        'Extract design tokens from a live web page (Lovable, Figma Make, any SPA) — Playwright capture + section crops + theme mapping',
    supportedTools: [
      _Tool.claude,
      _Tool.codex,
      _Tool.antigravity,
    ],
    template: _extractTemplate,
    references: {
      'scripts/extract.mjs': _extractScriptRef,
      'theme-ref.json': _themeRefTemplate,
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
   - **5+ independent siblings → parallel agent team**: If the design contains 5 or more independent sibling components (row of KPI cards, grid of tiles, list of chips), stop and read `parallel.md`. Dispatch one agent per slot with the artifact-producing contract instead of building serially. This applies to every provider — figma, stitch, lovable, or a hand-written spec.

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

9. **Visual validation loop** (autonomous — do NOT ask the user). Follow `iterate.md`:
   a. Read the generated PNG at `${c.outputDir}/<name>/<device>.png`
   b. **Tier 1 (structural):** Compare against the Figma reference using the review.md checklist (backgrounds, text colors, padding, borders, icons, typography, layout)
   c. **Tier 2 (perceptual):** Run `print_widget compare --name=<entry_name>` — this invokes pixelmatch against `${c.outputDir}/<name>/.reference/` and prints per-region scores. Exit 0 = converged, exit 1 = regions below threshold (default 0.95), heatmaps at `${c.outputDir}/<name>/crops/*_diff.png`
   d. List ALL remaining differences from both tiers — never stop at the first one
   e. **Back up files** before editing: `cp <file> /tmp/pw_iter_<N>_backup.dart`
   f. Fix ALL differences in one batch, then regenerate: `print_widget generate --name=<entry_name>`
   g. Re-run compare. **Revert on regression:** if any region's score dropped vs the previous iteration, restore from backup and try a different approach
   h. Repeat until BOTH tiers pass OR the 15-iteration hard cap is reached
   i. On cap: produce the escalation report from `iterate.md` — never silently accept mismatches
   j. After convergence: show the user the final screenshot with a verification report

10. **Save novel patterns**: If you discovered a new workaround or pattern during this task, save it to the project\u2019s CLAUDE.md for future sessions.

## Working with existing widgets

If the target widget already exists in the codebase:
- **Extract, don't rewrite**: Refactor the existing widget to match the design. Extract sub-widgets into private `StatelessWidget` classes.
- **Mock as little as possible**: Use real data models, real theme, real components. Only mock external dependencies (network, platform channels).
- **Preserve behavior**: Keep existing callbacks, state management connections, and navigation intact. Only change the visual layer.

## Internal references

Read these files for detailed guidelines. They are bundled alongside this skill:
- `conventions.md` — Widget structure rules (composition, extraction, DS discovery, behavioral rules)
- `screen.md` — Screen patterns (callbacks, providers, mock data, toggle states)
- `review.md` — Visual review checklist (layer-by-layer verification)
- `iterate.md` — Autonomous visual iteration loop (3-tier stop conditions, revert-on-regression, escalation)
- `compare.md` — How to use `print_widget compare` and read pixelmatch heatmaps
- `viewport.md` — Phase 0 viewport contract (critical for web references)
- `parallel.md` — Parallel agent teams for building 5+ sibling components at once (works for figma, stitch, lovable, or any provider)
- `lovable.md` — Adapter for Lovable.dev URLs (uses smart-extract + compare; adds Lovable-specific bits on top of `parallel.md`)

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
   - **5+ independent siblings → parallel agent team**: If the Stitch output contains 5 or more independent sibling components, stop and read `parallel.md`. Dispatch one agent per slot instead of building serially.

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
- **5+ independent sibling components** (row of cards, grid of tiles) → use the parallel agent team pattern from `parallel.md` instead of building serially
- **Material ancestor mandatory**: wrap every widget root in `Material(type: MaterialType.transparency)` to avoid yellow double-underlines under text in the generated PNG

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
4. List ALL sections. Verify each will be implemented. If 5+ independent sibling components (row of cards, grid of tiles), stop and read `parallel.md` — dispatch one agent per slot instead of building serially.
5. Build widget using DS tokens. Positive values → green, negative → red. Wrap every widget root in `Material(type: MaterialType.transparency)` to avoid yellow underlines under text.
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
3. Analyze layout, colors, typography, spacing from Stitch output. If 5+ independent sibling components, read `parallel.md` and dispatch an agent team.
4. Build widget using DS tokens. Same validation loop as figma. Wrap every widget root in `Material(type: MaterialType.transparency)` to avoid yellow underlines.
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
- **Material ancestor is MANDATORY for any widget that renders text**: If a generated PNG shows yellow double-underlines under text, that is Flutter\u2019s "no DefaultTextStyle / no Material ancestor" marker \u2014 the widget has no `Material` in its ancestor tree. Every atom, molecule, and organism print entry must resolve a `Material` ancestor, either by wrapping its own root in `Material(color: Colors.transparent, type: MaterialType.transparency, child: ...)` or via the session `appWrapper`. Assume nothing about the consumer context; a reusable widget that relies on "someone upstream will provide Material" will ship broken the first time it\u2019s captured standalone. ALWAYS visually audit the generated PNG for yellow lines before trusting any compare score \u2014 pixelmatch can still return a high score while every glyph is underlined.
- **FittedBox(scaleDown) for cross-context reuse**: Atoms/molecules that will be rendered standalone AND composed into an organism at a narrower width must wrap variable-width text values in `Flexible > FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft) > Text(...)`. This keeps the standalone capture at natural size while shrinking smoothly in the tighter organism slot \u2014 no clipping, no truncation, no fontSize downgrades. Apply proactively when the component will be composed; retrofitting after the organism fails is 3x the work.

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don\u2019t start from scratch.
- **Mock as little as possible**: Use real data and theme. Only mock external dependencies (network, platform channels).
- **GoRouter ancestor**: Widgets using navigation (`context.go()`, `GoRouterState.of()`) need `MaterialApp.router` with `GoRouter` in the `appWrapper` \u2014 not plain `MaterialApp`

## Design system component discovery (MANDATORY before creating a new widget)

Before creating ANY new widget \u2014 button, card, chip, pill, toggle, tab, badge, filter \u2014 search the project for existing equivalents. Creating a parallel component set is the #1 source of wasted iterations.

Run these greps at the start of every implementation:

```bash
# All widget declarations in the project
Grep: "class \\w+ extends (Stateless|Stateful)Widget" in lib/ and packages/

# Common component locations
Glob: lib/core/components/*.dart
Glob: lib/design_system/**/*.dart
Glob: packages/*/lib/src/widgets/*.dart
Glob: packages/*_design_system/lib/**/*.dart
```

Build a one-line catalog of each found widget: `ComponentName \u2014 what it does`.

For each visual element in the reference:
1. Classify it: is it a button, pill, segmented button, tab, chip, card, toggle, badge?
2. Search the catalog for a matching type.
3. If found: use it. Do NOT create a new one.
4. If not found: flag it to the user before creating. The user may want to add it to the DS instead of inlining it in a feature.

Red flags that you're about to reinvent a DS component:
- You\u2019re about to name something `_FilterChipsWidget`, `_CustomToggle`, `_EmbeddedSegmentedButton`, etc. \u2014 these almost always exist
- You\u2019re about to handwrite a `Container(decoration: BoxDecoration(borderRadius: ..., color: ...))` for something the DS calls a Card
- You\u2019re about to use `Colors.*` or `TextStyle(fontSize: ...)` directly \u2014 those are tokens, not literals

Rule: **never** create a widget of a well-known pattern (filter, toggle, card, button, chip) without first verifying the DS doesn\u2019t have it.
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

Systematic verification of generated screenshots against the reference. **Run this before trusting any `print_widget compare` score.** Pixelmatch is pixel-only and cannot detect truncated text, wrong glyphs, swapped icons, or font fallbacks — all of which leave the numeric score looking "close enough" while the visual is broken.

## The 5-point visual audit (gate before trusting score)

Open the three PNGs side by side: `<entry>/<device>.ref.png`, `<entry>/<device>.png`, `<entry>/<device>.diff.png`. For each of the five checks, the answer must be an unqualified YES before the score matters.

1. **Text complete.** Every string present, every word present, no `...` where the reference has full text, no missing trailing characters (a clipped `%` or `.` at the edge of a pill passes pixelmatch at >95% while being visibly wrong).
2. **Font matches.** Glyph shapes are identical — inspect `R`, `\$`, `%`, `a`, `o`, `g` which are the best tells for font fallback. A Helvetica Neue rendering next to a real Inter rendering is visible at a glance.
3. **Layout intact.** No Flutter overflow markers (yellow/black stripes), no misaligned columns, padding and gaps visually consistent, rounded corners where the reference has them.
4. **Colors match.** Primaries, muted, positive/negative deltas visually indistinguishable. Accept only when values average the same, not when they "look about right".
5. **Icons correct.** Same family, same pose, same fill vs stroke style. Material Symbols substituted for Lucide is almost never a visual match — use `flutter_svg` with the Lucide SVG string inline.

If any of the five fails, the entry is **not converged** even if the compare score is 99%. Fix the failing dimension and re-run. Do not mark the entry done with a failing visual audit on the excuse that "the score passes".

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

This is a **fully autonomous** visual iteration loop. It uses `print_widget compare` as the objective stop condition, **never asks the user mid-loop**, **reverts regressions automatically**, and produces an escalation report **only** when a hard cap is hit. Do not silently accept mismatches. Do not stop at iteration 5 and ask for approval — keep going until convergence or escalation.

## Three-Tier Stop Conditions

The loop exits only when **all active tiers pass**, or when the hard cap triggers an escalation.

- **Tier 1 — STRUCTURAL (AI vision):** Compare the generated PNG against the reference using the `review.md` checklist. Verify layout structure, exact text content, colors mapped to theme tokens, and DS components used where available.
- **Tier 2 — PERCEPTUAL (pixelmatch):** Run `print_widget compare --name=<entry>` and require exit code `0`. All per-region scores must be `>= threshold` (default `0.95`).
- **Tier 3 — STUCK DETECTION:** If the same region score stagnates (\u00b11%) for **2 consecutive iterations**, the loop is stuck and must take recovery action (see Stuck Detection).
- **Hard cap:** **15 iterations maximum** (not 5). On cap, produce the escalation report. **Never silently accept a mismatch.**

## Iteration Steps

1. **Generate:** `print_widget generate --name=<entry>`
2. **Read generated PNG:** `${c.outputDir}/<entry>/<device>.png`
3. **Read reference PNG:** `${c.outputDir}/<entry>/<device>.ref.png` (sibling suffix layout) or `${c.outputDir}/<entry>/.reference/<device>.png` (legacy layout).
4. **Tier 1 check (AI vision):** Compare generated vs reference using the **5-point visual audit** in `review.md`: text complete, fonts match, layout intact, colors match, icons correct. Failing any one is enough to reject even if Tier 2 passes — pixelmatch cannot detect truncated text or wrong glyphs.
5. **Tier 2 check (perceptual):** Run `print_widget compare --name=<entry>` and read the per-region scores from the output.
6. **If Tier 1 AND Tier 2 pass \u2192** STOP. Converged. Emit the final report and exit the loop.
7. **Backup before edit:** Save the current state of every file you are about to touch: `cp lib/features/.../screen.dart /tmp/pw_iter_<N>_backup.dart`. Do this **before** making any changes — it is required for revert.
8. **List ALL differences** from both tiers. Group them as `critical` and `minor`. Reference the heatmap PNGs from `${c.outputDir}/<entry>/<device>.diff.png` (sibling layout) or `${c.outputDir}/<entry>/crops/*_diff.png` (legacy) for each region that failed.
9. **Fix ALL differences in one batch.** Do not fix one at a time and regenerate between each — it wastes iterations and hides regressions.
10. **Regenerate and re-compare:** repeat steps 1, 4, 5.
11. **Regression check:** Compare new per-region scores against the previous iteration's scores. If **any region's score dropped**, revert the touched files from the backup: `cp /tmp/pw_iter_<N>_backup.dart lib/features/.../screen.dart`. Record the approach as tried-and-reverted. Try a **different** approach.
12. **Loop back to step 4.** Increment iteration counter. If counter reaches 15, jump to the Escalation Report.

## Revert-on-Regression Rule

This is the single most important safety rule. The loop must never drift into worse code.

- **Before every fix**, back up **all** files being touched to `/tmp/pw_iter_<N>_backup.*`.
- **After regeneration**, diff the new per-region scores against the previous iteration's scores.
- **If any region's score dropped**, revert **all** modified files immediately. Do not keep partial improvements that worsen another region.
- **Track tried-and-reverted approaches** in memory (region + approach + delta). Do not retry the same fix on the same region.
- If you are about to attempt a fix that matches a previously reverted one, pick a different strategy instead.

## Stuck Detection

- If the same region has the same score (\u00b11%) for **2 iterations in a row**, the loop is stuck.
- **Recovery actions (in order):**
  1. **Font safety check** — verify the reference was captured with the real declared font. Lovable and similar SPAs declare `font-family: Inter` without importing the font; the browser silently falls back to Helvetica/DejaVu. If the reference looks subtly "off" in glyph shapes, re-run extract with `forceFonts: ["Inter:wght@..."]` in `states.json` to inject the Google Fonts stylesheet before capture.
  2. **Fresh reference** — re-run the smart-extract for Lovable, or re-fetch the Figma MCP node for Figma. The reference crop may be stale or the crop region may be wrong.
  3. **Font variation / kerning** — if both the reference and the Flutter render use real Inter but widths still differ, the TextStyle needs `fontVariations: [FontVariation('opsz', fontSize)]` and `fontFeatures: [FontFeature.enable('kern')]`. Chromium applies these by default; Flutter does not.
- Re-run the compare after each recovery action.
- If still stuck after all three, **escalate** (emit the escalation report and stop).

## Anti-Inference Rule (Critical)

Visual fidelity requires observation, not guessing.

- **NEVER infer** icons, colors, or component choices from semantic names (e.g., do not assume `settings` means a gear icon, or `primary` means blue).
- **ALWAYS observe** the reference crops visually at full resolution before choosing an icon, color, or component.
- If a crop is too small to distinguish an icon, **inspect the source**: Chrome DOM for Lovable, Figma design context for Figma. Never guess.
- If inference is the only remaining option, **escalate to the user**. Do not ship a guess.

## DS Component Discovery (Run Before Every Iteration)

- Before creating a new widget, **grep existing components** in:
  - `lib/core/components/`
  - `packages/*/lib/src/widgets/`
  - `lib/design_system/`
- If a similar component already exists, **use it**. Do not duplicate.
- If the design system lacks something the reference needs, **flag it to the user** in the final report — do not silently build a one-off.

## Per-Iteration Checklist

The loop exits only when **every** box checks:

```
\u25a1 Every text string matches (exact characters, no approximations)
\u25a1 Every color maps to a theme token (no raw Color() or hex literals)
\u25a1 Every spacing maps to a token (no raw EdgeInsets values)
\u25a1 Every icon matches visual observation (not inferred from name)
\u25a1 DS components used where they exist
\u25a1 print_widget compare: all regions >= threshold
\u25a1 dart analyze: 0 errors, 0 warnings on modified files
```

If any box is unchecked at iteration 15, do **not** check it — emit the escalation report instead.

## Escalation Report Format

Emit this **only** when the hard cap (15 iterations) is hit, when stuck detection fails after a fresh reference fetch, or when the anti-inference rule forces a user decision. Never emit it as a shortcut to stop early.

```
ITERATION 15 \u2014 STOPPED WITH RESIDUAL DIFF

Converged dimensions:
  \u2713 Layout, Colors, Typography

Residual:
  \u2717 <region>: <score>% \u2014 <root cause hypothesis>
    Suggested fix: <specific suggestion>

Approaches tried and reverted:
  - <approach 1>: worsened <region> from X% to Y%
  - <approach 2>: broke analyzer

Next step: user intervention needed. See heatmap at <path>.
```

Include the path to the worst-offending heatmap PNG from `${c.outputDir}/<entry>/crops/` so the user can inspect it directly. Reference the config at `${c.configPath}` if configuration changes are part of the suggested fix.

## Working With Existing Widgets

When the target file already contains code:

- **Extract, don\u2019t rewrite.** Pull sub-trees into private `_WidgetName extends StatelessWidget` classes rather than replacing the whole file.
- **Mock as little as possible.** Preserve real data flow; only mock what the widget cannot reach in a test context (network, platform channels).
- **Preserve behavior.** Callbacks, state, and navigation must continue to work — visual iteration must not regress functionality.
- If a rewrite is genuinely required, back up the full file first and list the behavioral diff in the final report.
''';

String _compareRef(_Config c) => '''# Comparison workflow

`print_widget compare` runs pixelmatch on each generated entry against its reference and returns per-region similarity scores plus heatmap PNGs. It is one of **two** layers in the visual validation loop — the other being your own eyes (see "Visual audit is mandatory" below).

## File layout (sibling suffix — current, preferred)

```
${c.outputDir}/<feature>/<layer>/<group>/<entry>/
├── <device>.png       ← generated by print_widget
├── <device>.ref.png   ← reference (from Figma / Lovable / screenshot)
└── <device>.diff.png  ← pixelmatch heatmap (written on compare)
```

The `<layer>` segment follows **atomic design**: `atoms`, `molecules`, `organisms`, `pages`. Entry names use slashes so the nesting is automatic:

```dart
widget('home/atoms/performance/delta_badge', ...)
pages('home/molecules/product/product_card', ...)
```

## Legacy layout (still supported)

```
${c.outputDir}/<entry>/.reference/<device>.png
${c.outputDir}/<entry>/.reference/crops/*.png
```

Compare auto-detects which layout is in use. New projects should use the sibling suffix.

## Prerequisites

- `node` on PATH, `npm install pixelmatch pngjs` in the repo root.
- `cropsFrom:` set on the `PrintEntry` if you want per-region scoring.
- Reference PNG at the expected path (see layout above).

## Running

```bash
print_widget compare                      # all entries with references
print_widget compare --name=<entry>       # one entry (nested entries only)
print_widget compare --device=<frame>     # override default device
print_widget compare --threshold=0.90     # override the 0.95 default
print_widget compare --json               # machine-readable output
```

**`compare` without `--name` does not auto-discover nested entries** — it lists top-level dirs in `${c.outputDir}/` and treats each as an entry. For `home/atoms/.../` style entries, always pass `--name=home/atoms/.../entry_name` explicitly.

## Thresholds that work in practice

- **0.95** — pure shape atoms (no text), medium-to-large layouts with mostly structure
- **0.90** — molecules and cards with mixed text + structure
- **0.85** — small atoms (<100px²) with dense text
- **0.80** — components with custom icons or glyphs you cannot precisely replicate

Thresholds exist to detect regression during iteration, not to rubber-stamp convergence. **A score of 98% can still hide truncated text** if the missing character sits in a small region of the image.

## Visual audit is mandatory

Pixelmatch is pixel-only. It cannot tell you:

- A character is clipped off the right edge of a pill (score stays high)
- An icon is the wrong shape but the right color + size (score stays high)
- Text is in the wrong font but the layout is otherwise identical
- Colors that average out to "close" but are perceptibly different

**After every `compare` run, before trusting the score, read the three PNGs side by side** and answer these five questions:

1. **Text**: every string present and complete, no truncation, no trailing ellipsis where the ref has full text?
2. **Font**: do the glyph shapes match? `R`, `\$`, `%`, `a`, `o` are the best tells — a font fallback is visible at a glance on these.
3. **Layout**: alignment, padding, gaps all visually consistent? No yellow/black overflow markers from Flutter?
4. **Colors**: primaries, muted, positive/negative deltas visually match?
5. **Icons**: same family, same pose, same fill vs stroke style?

Only if all five pass do you trust the score and mark the entry converged. If any fails, fix it even if the score is already above threshold — **regression in text or icon semantics is invisible to pixelmatch**.

## Common failure modes

- **Dimension mismatch** → viewport pinning problem, see `viewport.md`.
- **Wrong font in reference** → if the source site declares a font-family it never imports (common in Lovable/Figma Make), the browser silently falls back to the OS sans-serif. The captured reference is in the wrong font and every comparison lies. See `viewport.md` / `lovable.md` for the `forceFonts:` option on extract.
- **Score high but text truncated** → visual audit caught it. Widen the DeviceFrame buffer, adjust the ref via `magick -gravity west -extent WxH` to match, and re-run.
- **Score low but looks right** → probably subpixel rendering differences between Chromium and Flutter for small text. Drop the threshold for that entry or accept a ~5% gap as cross-engine baseline.

## Making the border radius visible (white-on-white cards)

A card with `background: rgba(255,255,255,0.7)` on a light page has an invisible border. To verify radius + shadow during iteration, wrap the entry in a Material with a contrast background, and pad the reference PNG with the same contrast via `magick`:

```dart
// In print_widget/config.dart
widget(
  'home/molecules/my_card',
  Material(
    color: const Color(0xFFE0F2F1), // soft teal contrast
    child: const Padding(
      padding: EdgeInsets.all(14),
      child: Align(
        alignment: Alignment.topCenter,
        child: MyCard(...),
      ),
    ),
  ),
  size: const Size(340, 340),
  devices: [...],
)
```

```bash
# Pad the tight ref crop to the same 340x340 @ 2x with teal background:
magick ref_tight.png -background "#E0F2F1" -gravity center -extent 680x680 \\
  ${c.outputDir}/<entry>/<device>.ref.png
```

Now both the generated and reference show the card centered on a teal background, making the rounded corners and shadow verifiable at a glance.

## Iteration loop integration

Exit codes are designed for scripting:

- `0` → all regions converged, loop done
- `1` → one or more regions below threshold, loop must continue
- `2` → fatal error (missing Node, bad config, reference not found)

**Dev-time workflow** — delete the old generated PNG before each regen, but keep the reference:

```bash
rm -f ${c.outputDir}/<entry>/<device>.png ${c.outputDir}/<entry>/<device>.diff.png
print_widget generate --name=<entry>
print_widget compare  --name=<entry> --device=<frame>
```

## Never accept mismatch silently

If `compare` fails repeatedly on the same region, do **not** lower the threshold to "make it pass". Escalate with the residual diff report: which region, current score, heatmap path, last change attempted. Silent tolerance is how visual drift accumulates across sessions.
''';

String _viewportRef(_Config c) => '''# Viewport Contract (Phase 0)

## Why this matters

Flutter and the reference source must render at **exactly** the same dimensions. Any mismatch causes pixelmatch to throw a dimension error, and the iteration loop either gets stuck or — worse — drifts in the wrong direction while appearing to make progress.

This is specifically the **web-divergence problem**: mobile targets are constrained by device presets, but web viewports are arbitrary. A 1440-wide reference against a 1280-wide Flutter render will *never* converge, no matter how many iterations you run.

## Rule

**Pin the viewport before writing any code.** Not before generation, not before compare — before *extraction*, before *implementation*, before anything else. Phase 0 is called Phase 0 because it blocks all later phases.

## Determining the target viewport

- **Figma**: call `mcp__figma__get_metadata` → read `frame.width` x `frame.height`.
- **Lovable (Playwright extract)**: read `tokens.json` → the `viewport: {width, height}` field set by the extract script.
- **Screenshot upload**: read image dimensions via `identify <file>` (ImageMagick) or `sips -g pixelWidth -g pixelHeight <file>` on macOS.
- **User-supplied URL**: detect via the page's `<meta name="viewport">` tag, or ask the user directly. Do not assume.

## Pinning on the print_widget side

Either use a matching DeviceFrame preset:

```dart
devices: [DeviceFrame.web1440]
```

or define a custom one inline:

```dart
DeviceFrame(
  name: 'custom_lovable',
  size: Size(1440, 900),
  pixelRatio: 2.0,
)
```

Pass it via the `devices:` parameter of the `PrintEntry` in `${c.configPath}`.

## Pinning on the reference side

- **Lovable extract**: pass `viewport: {width, height}` to the extract script's `states.json`. The Playwright run will set `page.setViewportSize(...)` before capture.
- **Figma**: download the PNG at the frame's natural dimensions (1x), do not rescale.
- **Screenshot**: use the file as-is; do not resize.

## HARD STOP

If the two dimensions do not match, **do not proceed**. Do not generate, do not compare, do not "see how close it gets". Fix the viewport first. The iteration loop cannot converge against a mismatched target; every change you make will look like progress on some regions and regression on others, and the loop will oscillate until the hard cap.

## Fallback for tall scrolling pages

If the reference is a non-standard scrolling capture (e.g. 1440 x 2400), configure print_widget with:

```dart
DeviceFrame(
  name: 'lovable_scroll',
  size: Size(1440, 2400),
  pixelRatio: 2.0,
)
// and on the entry:
scrollExtent: 2400,
```

so the rendered Flutter widget matches the full-page screenshot rather than just the above-the-fold viewport.
''';

String _parallelRef(_Config c) => '''# Parallel agent teams

## Purpose

When a single task produces 5 or more independent sibling components (a Figma screen with 8 cards, a Stitch-generated dashboard with multiple tiles, a Lovable page row with N KPI widgets), build them in parallel using an **agent team**, not sequentially. This applies to ANY provider — figma, stitch, lovable, or a hand-written spec — as long as the siblings do not depend on each other.

## When to use it

Use a parallel team when ALL of the following hold:

- The task produces 5+ components that share a container (row, grid, flex-wrap)
- Each component has its own data and renders independently (no cross-component state)
- Each component could theoretically be built by a different person with the same brief
- You have a reference per component (Figma node, Stitch snippet, Lovable DOM node, screenshot crop)

Do NOT use a parallel team when:

- There are only 2-4 siblings — overhead beats the gain
- Components share state or one configures another
- You have only one global reference (a single screenshot of the whole page with no per-component crops) — resolve crops first
- The design system component that all siblings use does not exist yet — build the shared atom first, serially, then parallel the siblings

## Why parallel beats sequential

- **Independent units**: Each component is a self-contained leaf — its own icon, its own reference crop, its own mock data, its own Flutter snippet. There is no data flow between siblings.
- **Zero drift**: Serial builds accumulate drift — the 7th component gets built with different conventions than the 1st because you "learned something new" halfway through. Parallel agents all start from the same brief, so conventions stay uniform.
- **Clean main session**: No 7 rounds of edits to `${c.configPath}` — the main session aggregates everything once.
- **Faster convergence**: 7 agents running at once finish in roughly the time of one, so the feedback loop to `print_widget compare` stays tight.

## Hard contract — what each agent produces

Every agent in the team MUST emit exactly these artifacts to its own isolated workspace dir (no shared files). Nothing else. The exact file set depends on the provider:

### Provider-agnostic (always required)

| Artifact | Purpose |
|---|---|
| `<slot>.ref.png` | Reference image of the component (cropped Figma export, Stitch screenshot, Lovable DOM crop) |
| `data.json` | Mock data — every label, value, delta, percentage, state matching the reference exactly |
| `snippet.dart.txt` | Ready-to-drop Dart widget code using the project design system tokens — NOT written into `lib/` directly |

### Provider-specific (when applicable)

| Artifact | When | Purpose |
|---|---|---|
| `icon.svg` | Custom icons (Lucide, Heroicons, hand-drawn) that are not in the project icon set | Captured SVG outerHTML from the source DOM, or exported from Figma |
| `icon_const.dart.txt` | Same | `const String <slot>Svg = r"""<svg>...</svg>""";` declaration |
| `tokens.md` | Source uses novel colors or spacings that do not exist in the project theme | One row per new token with its proposed project-theme name |

**Forbidden for every agent**: editing `${c.configPath}`, editing any shared file under `lib/`, running `print_widget generate`, running tests, or touching another agent's workspace. These are all main-session responsibilities.

## Workspace isolation

Give each agent a unique workspace dir — this is what makes parallel safe without git worktrees:

```
/tmp/agent-team-<feature>/
  <slot-1>/   <- agent 1 writes only here
  <slot-2>/   <- agent 2 writes only here
  <slot-3>/   <- agent 3 writes only here
  ...
```

Agent workspaces are artifact buckets — nothing is committed from them. The main session reads the artifacts and aggregates into the repo.

## Mandatory Flutter rules every agent must obey

These rules apply to every agent regardless of provider. Bake them into the brief:

- **Material ancestor**: Every widget that renders text must resolve a `Material` ancestor. Wrap the widget root in `Material(color: Colors.transparent, type: MaterialType.transparency, child: ...)`. Yellow double-underlines in the generated PNG = missing Material. The agent's `snippet.dart.txt` output must already include this wrapper or a clearly marked TODO for the main session to add one.
- **FittedBox for cross-context reuse**: If the component will be rendered standalone AND composed into a narrower organism slot, variable-width text values must be wrapped in `Flexible > FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft) > Text(...)`. Apply proactively; retrofitting later is 3x the work.
- **Design system tokens only**: No raw `Color(0x...)`, no raw `EdgeInsets.all(16)`. Every value must reference a token from the project theme. If the source uses a color that has no token, record it in `tokens.md` for the main session — do not inline raw hex.
- **Const constructors**: Private `StatelessWidget` subclasses → `const`. No `_buildXxx()` methods — always extract sub-widgets.
- **No test runs**: Agents must not run `print_widget generate`, `flutter test`, or any build command. The snippet is text, not a compiled artifact. The main session is the only place builds happen.

## Agent brief template

Copy this into every agent's prompt, filling in `<slot>` and provider-specific fields:

```
You are building a single component (<slot>) as part of a parallel agent team.

Reference source: <figma-url | stitch-snippet | lovable-url>
Reference node/selector: <node-id | CSS selector | crop coordinates>
Viewport (if web): <WxH>

Workspace: /tmp/agent-team-<feature>/<slot>/   (write ONLY here)

Produce these artifacts:
  - <slot>.ref.png        (reference crop at the target resolution)
  - data.json             (mock data matching the reference exactly — labels,
                           numbers, states)
  - snippet.dart.txt      (ready-to-drop Dart widget using project DS tokens)
  - icon.svg              (ONLY if the component uses a custom icon not in the
                           project icon set)
  - icon_const.dart.txt   (ONLY if icon.svg exists — const String declaration)
  - tokens.md             (ONLY if the source introduces new colors/spacings
                           that do not exist in the project theme)

DO NOT:
  - edit ${c.configPath}
  - edit anything under lib/
  - run print_widget generate or any build/test command
  - touch any other agent's workspace

Flutter rules:
  - Wrap the widget root in Material(type: MaterialType.transparency) to avoid
    yellow underlines under text.
  - If the component will be composed into a narrower organism slot, wrap
    variable-width text values in Flexible > FittedBox(scaleDown, centerLeft).
  - Use only project design system tokens. No raw Color() or EdgeInsets literals.
  - Private StatelessWidget subclasses must be const.
  - No _buildXxx() methods — always extract sub-widgets.

Report back when all required artifacts are written.
```

## Main session aggregation

After all agents finish, the main session takes over:

1. **Audit each workspace** — verify every required artifact is present. Missing artifacts = rerun that specific agent.
2. **Copy reference crops**: each `<slot>.ref.png` to `${c.outputDir}/<feature>/<slot>/<slot>.ref.png`
3. **Drop widget snippets**: each `snippet.dart.txt` into `lib/ui/features/<feature>/widgets/<slot>.dart`
4. **Aggregate icons**: each `icon_const.dart.txt` into a shared `<feature>_icons.dart`, or inline per widget if one-offs
5. **Reconcile tokens**: merge all `tokens.md` rows — duplicates resolve to the same new token. Add new tokens to the project theme BEFORE adding entries to `${c.configPath}`.
6. **One config edit**: add all slots to `${c.configPath}` in a single pass.
7. **Batch generate**: `print_widget generate --name=<slot>` for each, or the full batch if supported.
8. **Visual audit every PNG before trusting scores**: look for yellow underlines (Material ancestor), text truncation, missing icons, wrong colors. Pixelmatch can score high while glyphs are underlined.
9. **Compare**: `print_widget compare` and iterate per the iterate.md loop on the worst-scoring slots. Re-dispatch a single agent per slot if a specific one needs a rewrite.
10. **One commit for the whole team** — clean history over one-commit-per-slot.

## Team anti-patterns

- **Shared config edits**: the moment two agents both want to edit `${c.configPath}`, you have a race. Keep all config edits in the main session.
- **Inter-agent chat**: agents must not read each other's workspaces or coordinate. Independence is the contract.
- **Re-generating the reference from scratch in every agent**: if the reference comes from a central source (smart-extract, Figma MCP), capture it once in the main session and copy into each agent workspace before dispatch.
- **Partial briefs**: copy-pasting the brief template with `<slot>` un-filled is the #1 cause of agent failures. Fill every placeholder before dispatch.
- **Skipping the visual audit**: trusting pixelmatch scores blind is how yellow-underlined components ship. Always eyeball the PNG grid before shipping.
''';

String _lovableRef(_Config c) => '''# Lovable Adapter

## Purpose

Convert a Lovable.dev URL (or any deployed React web app) into a Flutter widget with visual validation against the live reference. The adapter wires together `smart-extract-design` (reference capture), the Token Bundle process (theme mapping), and `print_widget compare` (objective convergence).

## Critical pre-flight gotchas

Read every one of these before touching a Lovable URL. Each represents hours of debugging lost by someone who skipped it.

1. **Lovable declares fonts without importing them.** Nearly every Lovable project puts `font-family: Inter, sans-serif` (or similar) in CSS but never `@import`s the font file. The browser silently falls back to the OS sans-serif — macOS Playwright falls back to Helvetica Neue, Linux to DejaVu. Any reference captured without force-loading the font is rendered in the **wrong font**, and every downstream comparison lies. Fix: add `forceFonts:` to `states.json` for extract:
   ```json
   { "forceFonts": ["Inter:wght@300;400;500;600;700"] }
   ```
   The extract will inject the Google Fonts stylesheet and await `document.fonts.ready` before capture.

2. **Use the published URL, not the preview URL.** `preview--xxx.lovable.app` requires authentication and falls through to the Lovable login page. The same project without `preview--` (e.g. `xxx.lovable.app`) is public. Always ask for the published URL.

3. **Inspect the leaf element, not the container.** Tailwind classes like `text-[12px]` often override parent sizes on the inner `<span>`. A walk-up inspector that stops at the pill container returns the wrong font size. Always descend to `childNodes.length === 0` with text, or trust the DevTools element panel the user screenshots — DevTools is the oracle.

4. **Flutter's Inter is ~15% wider than Chromium's Inter** at the same size, even from the same TTF file. Causes: Chromium auto-applies the `opsz` axis from variable fonts, Flutter does NOT; subpixel positioning differs; kerning is on by default in Chromium. Partial fix — use Inter Variable (from rsms/inter releases, not fontsource static) plus `FontVariation('opsz', fontSize)` + `FontFeature.enable('kern')` on every TextStyle. Minimum `opsz` on Inter is 14, so text < 14px still has a residual ~5% width gap that you compensate for by bumping DeviceFrame width and padding the reference with `magick -gravity west -extent WxH`.

5. **Custom SVG icons → embed verbatim with `flutter_svg`.** Do not substitute with Material Symbols. Capture the `svg.outerHTML` from the Lovable DOM (filter by `.lucide` class for Lucide icons), paste as a `const` String literal, render with `SvgPicture.string(svg, colorFilter: ColorFilter.mode(brandColor, BlendMode.srcIn))`. This also applies to decorative SVGs (e.g. concentric circles in card corners) — replace any Flutter CustomPainter you were about to write with the inline SVG.

## Flow

### 1. User provides a Lovable URL

Example: `https://my-app.lovable.app` (without the `preview--` prefix). Confirm the URL resolves and is publicly reachable before doing anything else.

### 2. Phase 0 — Viewport contract

Ask the user for the target viewport, or detect it from the site's media queries. Pin it on both sides. **Fail fast if unclear** — see `viewport.md`. Do not skip this step "just to see what comes out"; a mismatched viewport poisons every subsequent phase.

### 3. Extract reference

Invoke the `smart:extract-design` skill (install via `print_widget skills --only=extract`) with the URL and the pinned viewport. It produces, under `/tmp/extract-<slug>/01-<state>/`:

- `fullpage.png` — reference image of the full scrollable page
- `<NN>-<section>.png` — section crops, auto-detected from the DOM (e.g. `01-hero.png`, `02-features.png`)
- `_index.json` — crop bounding boxes (x, y, w, h) per region
- `tokens.json` — raw tokens (colors, spacing, typography, radii, optionally iconography)
- `_DESIGN.md` — theme mapping report with \u2705 / \ud83c\udfa8 / \u26a0\ufe0f / \u274c markers per token

### 4. Copy to the print_widget reference dir

```bash
mkdir -p ${c.outputDir}/<feature>/.reference/crops
cp /tmp/extract-<slug>/01-<state>/fullpage.png ${c.outputDir}/<feature>/.reference/
cp /tmp/extract-<slug>/01-<state>/[0-9]*.png ${c.outputDir}/<feature>/.reference/crops/
cp /tmp/extract-<slug>/01-<state>/_index.json ${c.outputDir}/<feature>/.reference/
```

This is the layout `print_widget compare` expects.

### 5. Build the Token Bundle from _DESIGN.md

Walk each token row in `_DESIGN.md` and decide:

- \u2705 **exact match** → use the existing project token as-is
- \ud83c\udfa8 **forced override** → use the override token the report suggests (brand color pinned, etc.)
- \u26a0\ufe0f **close match** → ask the user: reuse the nearest existing token, or create a new one? Do not decide silently.
- \u274c **new color/value** → propose a new token with both light and dark values; add to the project theme before implementation

The output of this step is a concrete mapping table: *extracted token → project token*. Every value used in step 7 must come from this table.

### 6. Design-system component discovery

Grep existing components (`lib/ui/`, `lib/components/`, `lib/design_system/`, etc.) and map each visible section from step 3's crops to an existing DS widget where possible. **Do not create custom widgets when the DS already has them** — that's how parallel component sets get born.

For each section in `_index.json`, record: *section → DS widget* or *section → needs-new-widget (why)*.

### 7. Implement the Flutter widget

Constraints:

- Use **only** mapped tokens from step 5. No raw hex codes. No raw `EdgeInsets.all(16)` — use spacing tokens.
- Mirror the DOM structure implied by the crops; keep widget nesting shallow (extract to private `StatelessWidget` classes, no `_buildXxx()` methods).
- Add to `${c.configPath}` as a `page(...)` entry:

  ```dart
  page('<feature>', MyFeatureScreen(),
    devices: [/* the pinned viewport from Phase 0 */],
    cropsFrom: '${c.outputDir}/<feature>/.reference/_index.json',
  )
  ```

  `cropsFrom` tells `generate` to produce crops at the same bounding boxes as the reference, so `compare` has matched pairs.

### 8. Generate + compare

```bash
print_widget generate --name=<feature>
print_widget compare  --name=<feature>
```

Read the per-region scores and heatmaps. Exit code 0 means done; exit code 1 means at least one region is still below threshold.

### 9. Iterate

Follow `iterate.md`:

- Make the smallest change that targets the worst-scoring region
- Regenerate, recompare
- **Revert on regression** (if a change drops any previously-passing region below threshold, undo it)
- **Escalate on hard cap** (if 15 iterations pass without net improvement, stop and report the residual diff)

## Re-extraction

If the user changes the Lovable design later:

1. Re-run `smart:extract-design` with the same slug
2. Diff the new `_DESIGN.md` against the old one
3. Surface which tokens changed and which sections now have different bounding boxes
4. Decide per-row whether to update the Flutter implementation or pin to the old reference

Do not silently overwrite the old reference — the diff is what tells the user whether their design actually drifted or the extractor just got unlucky.

## Parallel agent teams (5+ sibling components)

When the Lovable page contains 5+ sibling components under one container (a row of KPI cards, a grid of tiles, a list of chips), use the **parallel agent team** pattern from `parallel.md`. That reference file owns the provider-agnostic rules — artifact contract, workspace isolation, agent brief template, main session aggregation — so read it first. This section adds only the Lovable-specific bits.

### Lovable-specific gotcha: Playwright ESM import path

Every agent that runs a custom Playwright script will hit the same trap: `import 'playwright'` in an ESM `.mjs` file resolves relative to the script's own directory, NOT the current working directory. `NODE_PATH` does not help with ESM. Three fixes, in order of preference:

1. **Copy the script into `/tmp/.smart-extract-design/` and run from there** — that dir already has `node_modules/playwright` installed by the smart-extract-design skill's first-time setup. `cd /tmp/.smart-extract-design && node your-script.mjs`.
2. **Symlink `node_modules`** from `/tmp/.smart-extract-design/` into the agent workspace: `ln -s /tmp/.smart-extract-design/node_modules /tmp/agent-team-<feature>/<slot>/node_modules`.
3. **Absolute import** (last resort): `import { chromium } from '/tmp/.smart-extract-design/node_modules/playwright/index.mjs'`.

Put this in every agent brief. Otherwise each agent will burn ~15min re-deriving the workaround.

### Lovable-specific gotcha: DOM structure dump BEFORE writing any Dart

For the container (organism level — NOT the atoms), dump the real DOM structure via Playwright before writing a single line of the Dart organism widget:

```js
// Inspect the target container at the pinned viewport
const container = document.querySelector('<selector>');
const style = getComputedStyle(container);
const dump = {
  display: style.display,             // flex? grid?
  flexDirection: style.flexDirection,
  flexWrap: style.flexWrap,            // flex-wrap: wrap changes the visible set per viewport
  gap: style.gap,
  padding: style.padding,
  childCount: container.children.length,
  children: [...container.children].map((c) => ({
    tag: c.tagName,
    cls: c.className,
    bbox: c.getBoundingClientRect(),
  })),
};
console.log(JSON.stringify(dump, null, 2));
```

Commit the dump as a doc comment on the organism widget so future maintainers can verify composition without re-running Playwright. This prevents "I thought it was a Row, but it was a flex-wrap Wrap with 50 segments" retrofits.

### Lovable-specific gotcha: responsive grid reflow

Lovable uses responsive flex-wrap grids. **The set of visible children depends on the viewport.** A card that exists in the 1280 DOM visible row may not be in the 1920 row, and vice versa. Always inspect at the exact target viewport you pinned in Phase 0. If you inspect at the wrong viewport you will either miss a card or capture a phantom one — and the phantom will not match anything in the live site at your chosen viewport.

### Lovable-specific additions to the generic brief

When filling in the `parallel.md` brief template for a Lovable job, add these fields:

- **Reference source**: the published (non-`preview--`) Lovable URL
- **Reference node/selector**: CSS selector of the container + the index of the child slot
- **Viewport**: the viewport pinned in Phase 0 (critical — do not inherit the default)
- **Playwright runtime**: "run all .mjs scripts from `/tmp/.smart-extract-design` (see above)"
- **Icon capture**: "Filter by `.lucide` class to grab the Lucide SVG outerHTML from the DOM; paste as a `const` String"
- **Font rules**: "The container uses Inter. If the captured reference shows fallback fonts, force-inject `forceFonts: ['Inter:wght@300;400;500;600;700']` into the extract states.json" (see the pre-flight gotchas at the top of this file)

## Anti-inference note

For icons, **inspect the DOM via the extract's `tokens.json`**. If iconography detection is enabled, it lists Lucide / Heroicons / Material icon names directly from the rendered SVG `data-*` or class attributes. **Never guess icons from labels** ("Settings" does not automatically mean `Icons.settings` — the reference might use `tune` or `gear` or a custom SVG). Guessing icons is the single most common source of visual drift on web-derived Flutter widgets.
''';

String _extractTemplate(_Tool tool, _Config c) => _extractClaude(c);

String _extractClaude(_Config c) => '''---
name: smart:extract-design
description: Extract design tokens (colors, typography, spacing, radius), screenshot and crop sections from web prototypes (Lovable, Figma Make, any React/Vue SPA), and map everything to the project theme. Use when the user asks to "extract design", "capture this lovable", "grab the tokens from this page", or "/smart:extract-design". Always ask at runtime how to navigate (single URL vs clicks/URLs) — never hardcode selectors.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Smart Extract Design

Pipeline to extract the design of any rendered web page and produce:

- **Full-page @2x screenshots** of each state/screen
- **Automatic section crops** (detection via DOM bounding boxes)
- **Raw design tokens** (colors, typography, spacing, radius, shadows, iconography)
- **Mapping to the project design system** with badges \u2705/\ud83c\udfa8/\u26a0\ufe0f/\u274c
- **Proposal of new tokens** (light + dark) when needed

All navigation is asked at runtime. The skill **does not assume** dropdowns, tab bars, or any specific UI pattern.

---

## First-time setup — edit `theme-ref.json`

Open the skill's `theme-ref.json` (next to this SKILL.md) and fill in:

- `palette` — hex → token name mappings for your design system (e.g. `"#0BA284": "brand30"`)
- `semanticOverrides` — hex → `{token, role}` for colors that should map by semantic role even when the RGB distance isn\u2019t the closest
- `spacingScale`, `typographyScale`, `fontWeightMap` — your scale tokens

Without this file, extraction still works but mapping falls back to raw hex values. Edit once per project, then forget.

---

## STEP 1 — Collect input via AskUserQuestion

**ALWAYS use `AskUserQuestion`**, never free-text prompts.

**Question 1 — Base URL:** free input. If already given in the conversation, reuse it.

**Question 2 — How to navigate:**
- "Single screen" — capture only the initial state
- "Multiple URLs" — list of URLs (/home, /dashboard, /settings)
- "Same URL with clicks" — user describes which elements to click (text=Dashboard, etc.)
- "Mixed" — URLs + clicks

**Question 3 — Output dir (optional):** default `${c.outputDir}/extract-<host-slug>-<timestamp>`.

**Question 4 — Viewport (optional):**
- Desktop 1440x2400 (recommended)
- Mobile 390x844
- Tablet 820x1180

---

## STEP 2 — Build states.json

```json
{
  "url": "https://example.com/",
  "viewport": { "width": 1440, "height": 2400 },
  "deviceScaleFactor": 2,
  "output": "${c.outputDir}/extract-example",
  "states": [
    { "name": "initial", "steps": [] },
    {
      "name": "focus-state",
      "steps": [
        { "action": "click", "selector": "text=My Home" },
        { "action": "wait", "ms": 500 },
        { "action": "click", "selector": "text=Focus" }
      ],
      "settleMs": 1200
    }
  ]
}
```

**Actions:** `goto`, `click`, `fill`, `wait`, `scroll`, `press`. Prefer `text=VisibleLabel` selectors — most stable across SPA re-renders.

**Dropdown tip:** dropdowns close after selection — always reopen before the next state.

---

## STEP 3 — Prepare runtime (Playwright)

Playwright lives in a `node_modules` sibling of the script. Copy extract.mjs to a temp dir that holds `node_modules`:

```bash
RUN_DIR="/tmp/.smart-extract-design"
mkdir -p "\$RUN_DIR"
cp <this-skill-dir>/scripts/extract.mjs "\$RUN_DIR/extract.mjs"
cd "\$RUN_DIR"
if [ ! -d node_modules/playwright ]; then
  npm init -y > /dev/null 2>&1
  npm install playwright --silent
  npx playwright install chromium
fi
```

First run downloads Chromium (~60s). Subsequent runs reuse the cache.

---

## STEP 4 — Run the extraction

```bash
cd /tmp/.smart-extract-design
node extract.mjs "/path/to/states.json" --theme="<this-skill-dir>/theme-ref.json"
```

Output per state at `<output>/NN-<slug>/`:
- `fullpage.png`
- `NN-<section>.png` — one per detected section
- `_index.json` — bounding boxes
- `tokens.json` — raw tokens (including iconography if detected)
- `_DESIGN.md` — formatted tokens + mapping to theme

---

## STEP 5 — Review mismatches and ask the user

Read each `_DESIGN.md` and collect:
- \u274c new colors
- \u26a0\ufe0f close-but-not-exact colors

For each distinct new hex, **use `AskUserQuestion`**:

```
question: "The prototype uses `#XXXXXX` (N occurrences). How should we map it?"
options:
  - "Force to <suggested-token> (ΔE < 20)"
  - "Create new token <suggested-name>"
  - "Keep as raw hex (discuss with design)"
```

Rules for the 1st (recommended) option:
1. Identify the closest token by **semantic role**, not just RGB distance
2. If ambiguous, fall back to nearest RGB neighbor
3. If \u0394E > 60, change the 1st option to "create new token"

After capturing decisions, add forced mappings to a local `theme-ref-local.json` (copy of theme-ref.json + session overrides). **Do NOT edit the global `theme-ref.json`.**

Re-run just the mapping phase:
```bash
node extract.mjs states.json --theme=<output>/theme-ref-local.json
```

---

## STEP 6 — Generate consolidated docs

At the top of the output dir, create:

### `NORMALIZATION.md`
Table "Prototype → project token" including exact matches (\u2705) and forced overrides (\ud83c\udfa8).

### `NEW_TOKENS.md`
For each "create new token" decision, emit a proposal with light + dark values and code snippets for the project's theme files.

### `SUMMARY.md`
Index: processed URL, date, viewport, captured states, counts (\u2705/\ud83c\udfa8/\u274c), links.

---

## STEP 7 — Present the result

Show:
1. File structure generated (short tree)
2. Mapping highlights (exact / forced / new counts)
3. Decisions requiring action (new tokens to add)
4. Next steps — typically hand off to the `print-widget` skill's lovable adapter

---

## Handoff to print_widget

After extraction completes, the output is ready for the `print-widget` skill's `lovable.md` adapter:

```bash
# Copy extract output to print_widget reference dir
mkdir -p ${c.outputDir}/<feature>/.reference/crops
cp <extract-dir>/01-<state>/fullpage.png ${c.outputDir}/<feature>/.reference/
cp <extract-dir>/01-<state>/[0-9]*.png ${c.outputDir}/<feature>/.reference/crops/
cp <extract-dir>/01-<state>/_index.json ${c.outputDir}/<feature>/.reference/
```

Then invoke the print-widget skill's lovable adapter to build the Flutter widget and iterate with `print_widget compare` as the stop condition.

---

## General rules

- **Never hardcode** labels or selectors — always ask via `AskUserQuestion`
- **Never assume** dropdown/tab/sidebar patterns
- **Confirm interpretation** before running if the user already gave state info in chat
- **Pragmatism**: single screen with no interaction → 1 state with `steps: []`

## When NOT to use this skill

- The prototype exposes API/design tokens directly (use them)
- It's an actual Figma file (use the `figma` workflow in the main print-widget skill)
- You only need 1 quick screenshot, no crops or tokens

## Fallback if Playwright fails

If Chromium can't install:
```bash
# Native Chrome headless (screenshot only — loses crops and tokens)
/Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\
  --headless=new --screenshot=/tmp/x.png --window-size=1440,2400 <URL>
```
Warn the user that without Playwright the skill loses interaction, section crops, and token extraction.
''';

/// Reads the bundled `extract.mjs` from the package at install time and
/// returns it as a string.
///
/// Uses [Isolate.resolvePackageUri] so the path resolves correctly both
/// in local dev (path dependency) and after `dart pub global activate`
/// (from pub.dev or `--source path`). Falls back to [Platform.script]
/// heuristics and finally to an embedded stub with a reinstall hint.
String _extractScriptRef(_Config c) {
  // Synchronous resolution via Isolate.resolvePackageUri is not available,
  // so we cache the async result to a top-level [_cachedExtractScript]
  // during [SkillsCommand.run] before this function is called. If the
  // cache is populated, return it directly.
  if (_cachedExtractScript != null) return _cachedExtractScript!;

  final scriptPath = Platform.script.toFilePath();
  final scriptDir = File(scriptPath).parent.path;
  final candidates = <String>[
    '$scriptDir/../lib/src/tools/extract.mjs',
    '$scriptDir/../../lib/src/tools/extract.mjs',
    '${File(scriptPath).parent.parent.path}/lib/src/tools/extract.mjs',
    // Global activate from path: the snapshot shim lives in
    // ~/.pub-cache/bin but the source is at the activated package path.
    // Walk up the snapshot path looking for lib/src/tools/extract.mjs.
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      try {
        return file.readAsStringSync();
      } catch (_) {
        // fall through to the next candidate
      }
    }
  }
  return '// ERROR: Could not locate extract.mjs in the print_widget '
      'package.\n// Please reinstall with: '
      'dart pub global activate print_widget_flutter\n';
}

/// Populated by [SkillsCommand.run] before any reference template is
/// rendered. Async-resolved via [Isolate.resolvePackageUri] so it works
/// under `dart pub global activate` where [Platform.script] points at a
/// snapshot shim in `~/.pub-cache/bin` and the relative path heuristics
/// in [_extractScriptRef] fail.
String? _cachedExtractScript;

String _themeRefTemplate(_Config c) => '''{
  "name": "my-project-theme",
  "source": "Replace with a short description of where these tokens come from (e.g. 'design-system package v1.2.0', 'Figma library X', 'tailwind.config.js').",

  "palette": {
    "__comment": "Add your hex -> token mappings here, e.g. '#FFFFFF': 'white'. Use uppercase hex. These are exact matches — the extractor flags colors in this map with a \u2705 badge."
  },

  "semanticOverrides": {
    "__comment": "Add hex -> { token, role } for colors that should map by semantic role even when the RGB distance isn't the closest. Example: '#8FC3C3': { 'token': 'brand30', 'role': 'accent-brand' }. These are flagged with a \ud83c\udfa8 badge and take priority over palette matches."
  },

  "spacingScale": {
    "__comment": "example — replace with your own",
    "xs": "4px",
    "sm": "8px",
    "md": "16px",
    "lg": "24px"
  },

  "typographyScale": {
    "__comment": "example — replace with your own",
    "body": "14px",
    "title": "20px",
    "display": "32px"
  },

  "fontWeightMap": {
    "__comment": "example — replace with your own",
    "regular": "400",
    "medium": "500",
    "semibold": "600",
    "bold": "700"
  }
}
''';
