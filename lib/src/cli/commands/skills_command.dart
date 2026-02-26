import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class SkillsCommand extends Command<void> {
  SkillsCommand() {
    argParser
      ..addOption(
        'install',
        abbr: 'i',
        help: 'Skill IDs to install (comma-separated). E.g. figma,iterate',
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

    // Detect AI tools
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

    // Resolve target tools
    final toolArg = argResults!['tool'] as String?;
    final tools =
        toolArg != null
            ? [_Tool.values.firstWhere((t) => t.id == toolArg)]
            : detected;

    // Resolve skills to install
    final installArg = argResults!['install'] as String?;
    List<_Skill> skills;

    if (installArg != null) {
      skills = _parseSkillIds(installArg);
      if (skills.isEmpty) return;
    } else {
      if (!stdin.hasTerminal) {
        stderr.writeln(
          'Interactive mode requires a terminal. Use --install=figma,iterate',
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
      scope =
          (argResults!['scope'] as String) == 'user'
              ? _Scope.user
              : _Scope.project;
    } else if (installArg != null) {
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
      '    [1] project   Current project only',
    );
    stdout.writeln(
      '    [2] user      All projects (~/.claude/commands/)',
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
    stdout.writeln('  Available print_widget skills:');
    stdout.writeln('');
    for (final s in _skills) {
      stdout.writeln('    print_widget:${s.id}');
      stdout.writeln('      ${s.description}');
      stdout.writeln(
        '      Supports: ${s.supportedTools.map((t) => t.displayName).join(', ')}',
      );
      stdout.writeln('');
    }
    stdout.writeln('  Install with: print_widget skills --install=figma');
    stdout.writeln('  Or run:       print_widget skills   (interactive)');
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
      stdout.writeln('    [skip] $path (already exists)');
      return false;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    stdout.writeln('    [installed] $path');
    return true;
  }

  String _resolvePath(_Skill skill, _Tool tool, _Scope scope) {
    final home = Platform.environment['HOME'] ?? '';
    final fileName = 'print_widget:${skill.id}';

    switch (tool) {
      case _Tool.claude:
        final base =
            scope == _Scope.user ? '$home/.claude' : '.claude';
        return '$base/commands/$fileName.md';
      case _Tool.cursor:
        return '.cursor/rules/$fileName.mdc';
      case _Tool.codex:
        return '.codex/skills/$fileName.md';
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

  const _Skill({
    required this.id,
    required this.description,
    required this.supportedTools,
    required this.template,
  });
}

// =============================================================================
// Skill catalog
// =============================================================================

final _skills = <_Skill>[
  _Skill(
    id: 'figma',
    description: 'Convert Figma designs to Flutter widgets with screenshot comparison',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _figmaTemplate,
  ),
  _Skill(
    id: 'iterate',
    description: 'Visual iteration loop: generate, review, modify, regenerate',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _iterateTemplate,
  ),
  _Skill(
    id: 'conventions',
    description: 'Widget conventions: composition over nesting, extraction rules, const constructors',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _conventionsTemplate,
  ),
  _Skill(
    id: 'screen',
    description: 'Screen patterns: callbacks for actions, mock data population, screen-provider separation',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _screenTemplate,
  ),
  _Skill(
    id: 'review',
    description: 'Visual review: audit generated screenshots against design intent',
    supportedTools: [_Tool.claude, _Tool.cursor, _Tool.codex],
    template: _reviewTemplate,
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

String _iterateTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _iterateClaude(config);
    case _Tool.cursor:
      return _iterateCursor(config);
    case _Tool.codex:
      return _iterateCodex(config);
  }
}

// -----------------------------------------------------------------------------
// figma — Claude Code command
// -----------------------------------------------------------------------------

String _figmaClaude(_Config c) => '''Convert a Figma design into a Flutter widget and capture it with print_widget for visual comparison.

## Input

The user provides one of:
- A Figma frame screenshot (image file or pasted image)
- A description of the design with colors, spacing, typography
- A Figma URL (ask the user to paste or export a screenshot)

## Steps

1. **Analyze the design**: Identify layout structure, colors (exact hex), typography, spacing, and components used.

2. **Create the Flutter widget**: Build a widget that matches the design. Use the project's existing theme and design system. Prefer `const` constructors.

3. **Add to print_widget config** at `${c.configPath}`:
   - Full screen → `page('screen_name', const ScreenWidget())`
   - Component → `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states → `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

4. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

5. **Compare**: Read the generated PNG at `${c.outputDir}/<name>/<device>.png` and compare with the original design.

6. **Iterate**: Fix differences and regenerate until the screenshot matches the design.

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

## 3. Generate and compare
```bash
print_widget generate --name=<entry_name>
```

Screenshots are saved to `${c.outputDir}/<name>/<device>.png`.
Read `${c.outputDir}/manifest.json` for all generated paths.
''';

// -----------------------------------------------------------------------------
// figma — Codex instructions
// -----------------------------------------------------------------------------

String _figmaCodex(_Config c) => '''# print_widget: Figma Design Conversion

This project uses print_widget to capture Flutter widgets as PNG screenshots.

## Figma to Flutter workflow

1. Analyze the Figma design for layout, colors, typography, and spacing
2. Create a Flutter widget matching the design
3. Add the widget to `${c.configPath}`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
4. Run `print_widget generate --name=<name>` to capture the screenshot
5. Compare the PNG at `${c.outputDir}/<name>/<device>.png` with the original design
6. Iterate until it matches

## Key files
- Config: `${c.configPath}`
- Output: `${c.outputDir}/`
- Manifest: `${c.outputDir}/manifest.json`
''';

// -----------------------------------------------------------------------------
// iterate — Claude Code command
// -----------------------------------------------------------------------------

String _iterateClaude(_Config c) => '''Run the print_widget visual feedback loop: generate screenshots, review them, and iterate on the UI.

## Steps

1. **Generate screenshots**:
   ```bash
   print_widget generate
   ```
   Or for a specific entry:
   ```bash
   print_widget generate --name=<entry_name>
   ```

2. **Find the PNGs**: Read `${c.outputDir}/manifest.json` to get the list of generated screenshots with their file paths.

3. **Review each screenshot**: Read the PNG files and check:
   - Layout correctness and alignment
   - Text readability and truncation
   - Color consistency with the app theme
   - Spacing and padding between elements
   - Component sizing on different devices

4. **Identify issues** and fix the Flutter widget code.

5. **Regenerate** to verify the fix:
   ```bash
   print_widget generate --name=<entry_name> --delete-old
   ```

6. **Compare** the new screenshot with the previous version to confirm the improvement.

## Useful commands

| Command | What it does |
|---------|-------------|
| `print_widget list` | Show all configured entries |
| `print_widget generate --all-devices` | Test on iPhone 15 Pro, Pixel 7, iPad Pro 11 |
| `print_widget generate --delete-old` | Clean output before regenerating |
| `print_widget config` | View current settings |

## Output location

All PNGs are saved under `${c.outputDir}/`. The manifest at `${c.outputDir}/manifest.json` maps entry names to file paths.
''';

// -----------------------------------------------------------------------------
// iterate — Cursor rule
// -----------------------------------------------------------------------------

String _iterateCursor(_Config c) => '''---
description: print_widget visual iteration workflow for UI development
globs:
  - "${c.configPath}"
  - "**/*_page.dart"
  - "**/*_screen.dart"
  - "**/*_widget.dart"
alwaysApply: false
---

# print_widget visual iteration

This project uses print_widget to capture Flutter widgets as PNG screenshots for visual verification.

## After making UI changes

1. Run `print_widget generate` to capture updated screenshots
2. Check `${c.outputDir}/manifest.json` for generated file paths
3. Review the PNGs for visual correctness
4. If issues found, fix the widget and regenerate

## Quick reference

- Config file: `${c.configPath}` (exports `printSession` and `printList`)
- Output directory: `${c.outputDir}/`
- Generate one: `print_widget generate --name=<name>`
- Generate all: `print_widget generate`
- All devices: `print_widget generate --all-devices`
- Clean regenerate: `print_widget generate --delete-old`

## Entry types

```dart
page('name', Widget())                    // Full screen
widget('name', Widget(), size: Size(w,h)) // Component with custom size
pages('name', states: [...])              // Multiple states of a screen
widgets('name', states: [...], size: ...) // Multiple states of a component
```
''';

// -----------------------------------------------------------------------------
// iterate — Codex instructions
// -----------------------------------------------------------------------------

String _iterateCodex(_Config c) => '''# print_widget: Visual Iteration Workflow

This project uses print_widget to capture Flutter widgets as PNG screenshots.

## Visual feedback loop

1. Run `print_widget generate` to capture screenshots
2. Read `${c.outputDir}/manifest.json` for generated PNG paths
3. Review screenshots for layout, colors, spacing issues
4. Fix the Flutter code and regenerate with `print_widget generate --delete-old`

## Commands
- `print_widget generate` — capture all entries
- `print_widget generate --name=<name>` — capture specific entry
- `print_widget generate --all-devices` — test on multiple devices
- `print_widget list` — show configured entries
- `print_widget config` — view settings

## Key files
- Config: `${c.configPath}`
- Output: `${c.outputDir}/`
- Manifest: `${c.outputDir}/manifest.json`
''';

// =============================================================================
// conventions — Widget conventions skill
// =============================================================================

String _conventionsTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _conventionsClaude(config);
    case _Tool.cursor:
      return _conventionsCursor(config);
    case _Tool.codex:
      return _conventionsCodex(config);
  }
}

// -----------------------------------------------------------------------------
// conventions — Claude Code command
// -----------------------------------------------------------------------------

String _conventionsClaude(_Config c) =>
    '''Apply widget conventions when building or reviewing Flutter widgets in this project.

## What this command does

When invoked, review the current widget code and refactor it to follow the conventions below. If writing new widgets, follow them from the start.

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain. Deep nesting hides intent.

```
GOOD: Flat composition           BAD: Deep nesting
Parent                           Parent
\u251c\u2500\u2500 child1                         \u2514\u2500\u2500 Wrapper
\u251c\u2500\u2500 child2                              \u2514\u2500\u2500 Wrapper
\u2514\u2500\u2500 child3                                   \u2514\u2500\u2500 Content
```

## Rules

### 3-level rule
Any widget subtree deeper than 3 nesting levels \u2192 extract to a private `StatelessWidget`.

### 4+ children rule
`Column`, `Row`, or `ListView` with 4+ children \u2192 extract each child to a private widget.

### Card / tile decomposition
Cards with header + body + footer \u2192 3 separate private widgets.

### No `_buildXxx()` methods
Always extract to `_WidgetName extends StatelessWidget` instead of a method that returns a widget. Private widget classes are easier to test, const-optimize, and find in the widget tree.

### Const constructors
All `StatelessWidget` subclasses with no required mutable parameters must use `const` constructors.

### Component promotion criteria
| When | Where |
|------|-------|
| Used only in one screen | Keep as private widget in the same file |
| Used by 2+ features | Promote to `lib/core/components/` (or equivalent shared location) |
| Reusable but not a design-system piece | Move to `lib/core/widgets/` |

### Material widget substitutions
If the project has custom components (e.g. `AppButton`, `AppTextField`), prefer those over raw Material widgets (`ElevatedButton`, `TextField`). Check the project\u2019s component library first.

## Make it yours

This skill is a starting point. Every project has its own conventions. Update this file to reflect:
- Your project\u2019s specific component library and naming prefixes
- Your design token access patterns (e.g. `Theme.of(context)` vs a custom `AppTheme.of(context)`)
- Your spacing, radius, and typography tokens
- Any additional rules your team follows

The more specific this file is to your project, the better the AI will follow your patterns.

Run `print_widget skills` to see where this file is installed, then edit it directly.
''';

// -----------------------------------------------------------------------------
// conventions — Cursor rule
// -----------------------------------------------------------------------------

String _conventionsCursor(_Config c) => '''---
description: Widget conventions for Flutter — composition over nesting, extraction rules, const constructors
globs:
  - "**/*_page.dart"
  - "**/*_screen.dart"
  - "**/*_widget.dart"
  - "lib/core/components/**/*.dart"
alwaysApply: false
---

# Widget conventions

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain.

## Rules

1. **3-level rule**: Subtree deeper than 3 levels \u2192 extract to `_WidgetName extends StatelessWidget`
2. **4+ children rule**: Column/Row/ListView with 4+ children \u2192 extract each child
3. **Card decomposition**: Header + body + footer \u2192 3 separate private widgets
4. **No `_buildXxx()` methods**: Always extract to private `StatelessWidget` classes
5. **Const constructors**: All `StatelessWidget` subclasses with no required mutable params \u2192 `const`
6. **Component-first**: Check the project\u2019s component library before building from scratch
7. **Promote when reused**: Private widget used by 2+ features \u2192 move to shared location

## Make it yours

Edit this file to add your project\u2019s specific tokens, component prefixes, and conventions.
''';

// -----------------------------------------------------------------------------
// conventions — Codex instructions
// -----------------------------------------------------------------------------

String _conventionsCodex(_Config c) => '''# Widget Conventions

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain.

## Rules
- Subtree deeper than 3 levels \u2192 extract to `_WidgetName extends StatelessWidget`
- Column/Row/ListView with 4+ children \u2192 extract each child to a private widget
- Card with header + body + footer \u2192 3 separate private widgets
- Never use `_buildXxx()` methods \u2192 always extract to private `StatelessWidget` classes
- All `StatelessWidget` subclasses with no mutable params \u2192 `const` constructors
- Check project\u2019s component library before using raw Material widgets

## Make it yours

This is a starting point. Edit this file to add your project\u2019s design tokens, component naming, and team conventions.
''';

// =============================================================================
// screen — Screen patterns skill
// =============================================================================

String _screenTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _screenClaude(config);
    case _Tool.cursor:
      return _screenCursor(config);
    case _Tool.codex:
      return _screenCodex(config);
  }
}

// -----------------------------------------------------------------------------
// screen — Claude Code command
// -----------------------------------------------------------------------------

String _screenClaude(_Config c) =>
    '''Apply screen patterns when building or reviewing Flutter screens in this project.

## What this command does

When invoked, check that screens follow the patterns below. Refactor if needed. When writing new screens, follow them from the start.

## Callbacks over hardcoded logic

Screens are presentation-only. They display data and forward user actions via callbacks. They never contain business logic, navigation, or API calls.

```dart
// GOOD: Screen receives data and exposes callbacks
class PaymentScreen extends StatelessWidget {
  final String amount;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onPromoCodeChanged;

  const PaymentScreen({
    super.key,
    required this.amount,
    this.onSubmit,
    this.onPromoCodeChanged,
  });
}

// BAD: Screen does business logic internally
class PaymentScreen extends ConsumerWidget {
  Widget build(context, ref) {
    // Don\u2019t call APIs or navigate from inside the screen
    ref.read(paymentProvider.notifier).submit();
    Navigator.push(...);
  }
}
```

### Callback types
| Type | Use case |
|------|----------|
| `VoidCallback?` | Button press, tap, form submit |
| `ValueChanged<T>?` | Text field, toggle, selection |
| `ValueSetter<int>?` | Index-based (tabs, pages) |

Pass `null` to disable an action (e.g. a disabled button).

## Screen-provider separation

```dart
// Screen \u2014 pure function of inputs, testable without state management
class DashboardScreen extends StatelessWidget {
  final DeviceStatus status;
  final VoidCallback? onRefresh;
  // ...
}

// Page \u2014 connects to state management and passes data to the screen
class DashboardPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    return DashboardScreen(
      status: state.deviceStatus,
      onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
    );
  }
}
```

This separation allows:
- Screens testable without Riverpod/Bloc/Provider
- Screens previewable with print_widget (just pass sample data)
- State management testable without UI

## Mock data for print_widget

When adding screens to `${c.configPath}`, populate all dynamic content:
- Use representative values ("Sarah Johnson", not "User 1")
- Lists: 3\u20135 items to show scrolling
- Implement all visual states (empty, loading, filled, error, disabled)

```dart
// In ${c.configPath}
pages('dashboard', states: [
  state('empty', DashboardScreen(items: [])),
  state('loading', DashboardScreen(isLoading: true)),
  state('filled', DashboardScreen(items: sampleItems)),
  state('error', DashboardScreen(error: 'Connection lost')),
]),
```

## Make it yours

This skill is a starting point. Update this file to match your project:
- Your state management pattern (Riverpod, Bloc, Provider, etc.)
- Your Screen vs Page naming convention
- Your specific component library (AppButton, AppTextField, etc.)
- Your navigation approach (GoRouter, Navigator 2.0, etc.)

Run `print_widget skills` to see where this file is installed, then edit it directly.
''';

// -----------------------------------------------------------------------------
// screen — Cursor rule
// -----------------------------------------------------------------------------

String _screenCursor(_Config c) => '''---
description: Screen patterns for Flutter \u2014 callbacks, mock data, screen-provider separation
globs:
  - "**/*_page.dart"
  - "**/*_screen.dart"
  - "${c.configPath}"
alwaysApply: false
---

# Screen patterns

## Callbacks over hardcoded logic

Screens are presentation-only. Data in, callbacks out. No business logic, no navigation, no API calls.

- `VoidCallback?` \u2014 button press, tap, form submit
- `ValueChanged<T>?` \u2014 text field, toggle, selection
- Pass `null` to disable an action

## Screen-provider separation

- **Screen**: Pure `StatelessWidget` receiving data + callbacks. Testable, previewable with print_widget.
- **Page**: `ConsumerWidget` (or equivalent) connecting state management to the screen.

## Mock data for print_widget

In `${c.configPath}`, populate all states with representative data (empty, loading, filled, error).

## Make it yours

Edit this file to add your state management pattern, naming conventions, and component library.
''';

// -----------------------------------------------------------------------------
// screen — Codex instructions
// -----------------------------------------------------------------------------

String _screenCodex(_Config c) => '''# Screen Patterns

## Callbacks over hardcoded logic
Screens are presentation-only. Data in, callbacks out. No business logic, navigation, or API calls.

## Screen-provider separation
- Screen: Pure `StatelessWidget` with data + callbacks
- Page: Connects state management to the screen

## Mock data
In `${c.configPath}`, populate all states with representative data (empty, loading, filled, error).

## Make it yours
Edit this file to add your state management, naming conventions, and component library.
''';

// =============================================================================
// review — Visual review skill
// =============================================================================

String _reviewTemplate(_Tool tool, _Config config) {
  switch (tool) {
    case _Tool.claude:
      return _reviewClaude(config);
    case _Tool.cursor:
      return _reviewCursor(config);
    case _Tool.codex:
      return _reviewCodex(config);
  }
}

// -----------------------------------------------------------------------------
// review — Claude Code command
// -----------------------------------------------------------------------------

String _reviewClaude(_Config c) =>
    '''Review generated print_widget screenshots and report visual issues.

## What this command does

Generates fresh screenshots and audits each one for visual quality, consistency, and correctness. Outputs a verdict per screen.

## Steps

1. **Generate fresh screenshots**:
   ```bash
   print_widget generate --delete-old
   ```

2. **Read the manifest** at `${c.outputDir}/manifest.json` to get all generated PNG paths.

3. **Review each screenshot** and check:

   **Layout**
   - Content is properly aligned and centered
   - No unexpected overflow or clipping
   - Spacing between elements is consistent
   - Safe areas are respected (no content under notch/status bar)

   **Typography**
   - Text is readable at the rendered size
   - No truncation unless intentional (ellipsis)
   - Font weights and sizes follow hierarchy (headings > body > detail)

   **Colors**
   - Background, text, and accent colors are consistent across screens
   - Sufficient contrast between text and background
   - No unexpected default grey or missing color tokens

   **States**
   - Empty states show a meaningful message or illustration
   - Error states are visually distinct
   - Loading states are represented (skeleton, spinner, or placeholder)
   - Filled states use representative data (not "test" or "lorem ipsum")

   **Responsiveness** (if `--all-devices` was used)
   - Layout adapts correctly to different screen sizes
   - No horizontal overflow on smaller devices
   - Content doesn\u2019t look lost on larger devices (iPad)

4. **Report** findings per entry:
   - **Pass**: No issues found
   - **Warnings**: Minor issues (e.g. tight spacing, could be improved)
   - **Needs fix**: Layout broken, text cut off, wrong colors, missing states

5. **Fix and re-verify**: For entries that need fixes, update the widget code, regenerate with `--name=<entry_name> --delete-old`, and re-check.

## Make it yours

This is a baseline review checklist. Customize it for your project:
- Add checks for your design system tokens (specific colors, spacing values)
- Add brand-specific rules (logo placement, minimum margins)
- Add accessibility checks (minimum tap targets, contrast ratios)

Run `print_widget skills` to see where this file is installed, then edit it directly.
''';

// -----------------------------------------------------------------------------
// review — Cursor rule
// -----------------------------------------------------------------------------

String _reviewCursor(_Config c) => '''---
description: Visual review checklist for print_widget screenshots
globs:
  - "${c.outputDir}/**/*.png"
  - "${c.outputDir}/manifest.json"
alwaysApply: false
---

# Visual review checklist

After running `print_widget generate`, review each screenshot for:

1. **Layout**: Alignment, spacing, overflow, safe areas
2. **Typography**: Readability, hierarchy, truncation
3. **Colors**: Consistency, contrast, no missing tokens
4. **States**: Empty, error, loading, filled all look correct
5. **Responsiveness**: Adapts to iPhone, Pixel, iPad (if `--all-devices`)

Report: Pass / Warnings / Needs fix per entry.

## Make it yours

Edit this file to add project-specific design token checks and brand rules.
''';

// -----------------------------------------------------------------------------
// review — Codex instructions
// -----------------------------------------------------------------------------

String _reviewCodex(_Config c) => '''# Visual Review

After running `print_widget generate`, review each screenshot at `${c.outputDir}/` for:
- Layout: alignment, spacing, overflow, safe areas
- Typography: readability, hierarchy, truncation
- Colors: consistency, contrast, no missing tokens
- States: empty, error, loading, filled
- Responsiveness: adapts across devices (if `--all-devices`)

Report: Pass / Warnings / Needs fix per entry.

## Make it yours
Edit this file to add project-specific design token checks and brand rules.
''';
