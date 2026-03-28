# print_widget -- The Big Picture

A comprehensive overview of the print_widget ecosystem: what it is, how every piece connects, and how to use the full workflow from zero to production.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [What Is print_widget?](#what-is-print_widget)
3. [Complete Architecture](#complete-architecture)
4. [The Rendering Pipeline](#the-rendering-pipeline)
5. [Core Dart Library](#core-dart-library)
6. [CLI Commands](#cli-commands)
7. [VS Code Extension](#vs-code-extension)
8. [AI Skills System](#ai-skills-system)
9. [MCP Integration](#mcp-integration)
10. [The Complete User Workflow](#the-complete-user-workflow)
11. [How Everything Connects](#how-everything-connects)
12. [File Map](#file-map)

---

## Quick Start

```bash
# 1. Install the CLI globally (once)
dart pub global activate print_widget_flutter

# 2. Initialize in your Flutter project
cd my_flutter_app
print_widget init

# 3. Edit the generated config file (print_widget/config.dart)
#    Add your widgets and pages to printList

# 4. Generate screenshots
print_widget generate

# 5. View results
#    PNGs are in print_widget/output/
#    manifest.json lists everything that was generated
```

---

## What Is print_widget?

print_widget solves a specific problem: **LLMs cannot see what they build in Flutter**. When an AI assistant writes a Flutter widget, it has no way to verify the visual result. print_widget gives LLMs eyes.

It captures Flutter widgets and pages as PNG screenshots. An LLM can then:
1. Build a widget
2. Generate a screenshot
3. Read the screenshot image
4. Compare it against a design (from Figma or a reference image)
5. Fix differences and regenerate until it matches

**Target audience**: Flutter developers working with AI coding assistants (Claude Code, Cursor, Codex), and the AI assistants themselves.

**The package name on pub.dev is `print_widget_flutter`**. The CLI command is just `print_widget`.

---

## Complete Architecture

print_widget is not one tool -- it is an ecosystem of five interconnected pieces:

```
+-----------------------------------------------------------------------+
|                        print_widget ECOSYSTEM                         |
|                                                                       |
|  +-------------------+   +-------------------+   +------------------+ |
|  |   Dart Library    |   |    CLI Tool        |   |  VS Code Ext.   | |
|  |                   |   |                    |   |                  | |
|  | PrintSession      |   | init               |   | Tree sidebar    | |
|  | PrintEntry        |   | generate           |   | Preview panel   | |
|  | DeviceFrame       |   | list               |   | Device compare  | |
|  | PrintConfig       |   | config             |   | Diff slider     | |
|  | FontLoader        |   | skills             |   | Figma compare   | |
|  | PrintManifest     |   | --llm-guide        |   | Source linker   | |
|  +--------+----------+   +--------+-----------+   +--------+---------+ |
|           |                        |                        |          |
|           |    +-------------------+                        |          |
|           |    |                                            |          |
|           v    v                                            v          |
|  +-------------------+                        +-------------------+   |
|  | manifest.json     |<-----------------------| .reference/ imgs  |   |
|  | (generated PNGs)  |                        | (design targets)  |   |
|  +-------------------+                        +-------------------+   |
|                                                                       |
|  +-------------------+   +-------------------+                        |
|  |   AI Skills       |   |   MCP Server      |                        |
|  |                   |   |                    |                        |
|  | figma skill       |   | Resources (guide,  |                        |
|  | conventions.md    |   |   api, arch)       |                        |
|  | screen.md         |   | Prompts (setup,    |                        |
|  | review.md         |   |   add, compare)    |                        |
|  | iterate.md        |   |                    |                        |
|  +-------------------+   +-------------------+                        |
+-----------------------------------------------------------------------+
```

### Two Roles, One Package

| Role | Purpose | Install method |
|------|---------|----------------|
| **Global CLI** | Run `init`, `generate`, `list`, `config`, `skills` commands | `dart pub global activate print_widget_flutter` |
| **Dev dependency** | Import `PrintSession`, `PrintEntry`, `DeviceFrame`, etc. in Dart code | Added automatically by `print_widget init` |

The CLI is the interface. The dev dependency provides the classes your config file imports. Both come from the same Dart package.

---

## The Rendering Pipeline

This is the core mechanism. Understanding it explains why everything else exists.

**Fundamental constraint**: Flutter can only render widgets inside its test framework. There is no headless Flutter renderer. The only way to get a PNG of a Flutter widget is via `flutter test --update-goldens` and the `matchesGoldenFile()` matcher.

### End-to-End Data Flow

```
STEP 1: User defines config
==============================

  print_widget.yaml                    print_widget/config.dart
  +-------------------------+          +----------------------------------+
  | config_file: config.dart|--------->| printSession = PrintSession(     |
  | output_dir: output/     |          |   appWrapper: (child) =>         |
  | default_device: iph_15  |          |     MaterialApp(home: child),    |
  | manifest: true          |          |   defaultDevice: iPhone15Pro,    |
  | flat: false             |          | );                               |
  +-------------------------+          |                                  |
                                       | printList = [                    |
                                       |   page('login', LoginPage()),    |
                                       |   widget('card', MyCard()),      |
                                       | ];                               |
                                       +----------------------------------+


STEP 2: CLI generates temp test
==============================

  .dart_tool/print_widget/print_test.dart
  +------------------------------------------+
  | import '../../print_widget/config.dart'; |
  | void main() {                            |
  |   testWidgets('generate', (tester) {     |
  |     for (entry in printList) {           |
  |       // set surface size                |
  |       // pump widget through appWrapper  |
  |       // matchesGoldenFile(...)          |
  |     }                                    |
  |   });                                    |
  | }                                        |
  +------------------------------------------+


STEP 3: Flutter test renders PNGs
==============================

  CLI runs: flutter test --update-goldens .dart_tool/print_widget/print_test.dart

  For each entry + device combination:
    1. tester.binding.setSurfaceSize(device.size)
    2. tester.view.physicalSize = device.size * device.pixelRatio
    3. tester.pumpWidget(appWrapper(widget))
    4. tester.pumpAndSettle()
    5. precacheImages()
    6. expectLater(find.byType(MaterialApp), matchesGoldenFile(path))


STEP 4: CLI writes manifest
==============================

  print_widget/output/
  +-- login_page/
  |   +-- iphone_15_pro.png
  +-- card/
  |   +-- iphone_15_pro.png
  +-- manifest.json
      {
        "generatedAt": "2026-03-26T...",
        "screenshots": [
          { "name": "login_page", "file": "login_page/iphone_15_pro.png", ... },
          { "name": "card", "file": "card/iphone_15_pro.png", ... }
        ]
      }
```

### Page vs Widget Rendering

The `PrintType` determines how the widget is wrapped before capture:

```
PAGE:                                    WIDGET:
appWrapper(                              appWrapper(
  LoginPage()  <-- direct child            Scaffold(
)                                            body: Center(
                                               child: Padding(
                                                 child: ProductCard()
                                               )
Result: Full screen, fills device          )
                                         )
                                         )
                                         Result: Centered on screen with optional size constraint
```

### Grouped States

A single entry can produce multiple PNGs by using `pages()` / `widgets()` with `state()`:

```dart
pages('sign_in', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(initialError: 'Bad email')),
  state('filled', SignInScreen(initialEmail: 'user@test.com')),
])
```

Output naming depends on `PrintSession.stateOutputMode`:

| Mode | Example path |
|------|-------------|
| `prefix` (default) | `sign_in/empty_iphone_15_pro.png` |
| `suffix` | `sign_in/iphone_15_pro_empty.png` |
| `folder` | `sign_in/empty/iphone_15_pro.png` |

### Flat Mode

When `flat: true` (via `--flat` flag or `print_widget.yaml`), all PNGs go directly in the output root:

```
Normal:  output/login_page/iphone_15_pro.png
Flat:    output/login_page_iphone_15_pro.png
```

---

## Core Dart Library

All public API is exported from `package:print_widget_flutter/print_widget.dart`.

### Class Relationship Diagram

```
AppWrapper (typedef)                    DeviceFrame
  Widget Function(Widget child)           name, size, pixelRatio
        |                                 16 presets + 3 groups
        |                                       |
        v                                       |
PrintSession ----------------------------------|
  appWrapper                                    |
  defaultDevice? ------------------------------|
  outputDir                                     |
  generateManifest                              |
  stateOutputMode                               |
  flat                                          |
                                                |
PrintEntry <--- page(), widget(), pages(), widgets()
  name                                          |
  widget                                        |
  type (PrintType.page | .widget)               |
  size?                                         |
  devices? ------------------------------------|
  states? ---> List<PrintState>
                 name
                 widget

Printable (mixin)
  printName
  printType
  (optional: widgets can declare their own metadata)

PrintConfig (standalone API only)
  size, pixelRatio, theme, outputDir, background, padding, locale, ...

PrintManifest / PrintManifestEntry
  (data classes for the generated manifest.json)
```

### Key Classes

**PrintSession** -- The top-level configuration object. Defines how all entries are rendered: the app shell (`appWrapper`), default device, output directory, state naming mode, and flat mode. Users create one `printSession` in their config file.

**PrintEntry** -- A single screenshot definition. Has a `name` (used for output directory), a `widget` to render, a `type` (page or widget), optional `size`, optional `devices` list, and optional `states` for grouped captures. Created via helper functions `page()`, `widget()`, `pages()`, `widgets()`.

**DeviceFrame** -- Defines a device's screen dimensions and pixel ratio. Has 16 built-in presets (iPhoneSE through iPadPro13, Pixel 7/8, Samsung S24, and 4 generic sizes) plus 3 preset groups (`popular`, `allPhones`, `allTablets`).

**PrintState** -- A named visual state within a grouped entry. Created via the `state()` helper.

**PrintConfig** -- Lower-level configuration for the standalone test API (used when calling `printWidget()` directly in test files, bypassing the CLI).

**FontLoader** -- `loadPrintWidgetFonts()` loads bundled Roboto + MaterialIcons, then auto-detects fonts from the project's `pubspec.yaml`. `loadCustomFonts()` and `loadPackageFonts()` provide manual control.

**PrintManifest / PrintManifestEntry** -- Data classes representing the generated `manifest.json`. Each entry includes name, type, file path, device, logical dimensions, physical dimensions, and optional state name.

**Printable** -- An optional mixin that widgets can use to declare their own print metadata (`printName`, `printType`).

### Two APIs

| API | When to use | Entry point |
|-----|------------|-------------|
| **Session API** (recommended) | CLI-driven workflow. Define `printSession` + `printList` in config. | `printEntry()`, `printAllEntries()` |
| **Standalone API** | Direct use inside `testWidgets` blocks, no CLI needed. | `printWidget()`, `printWidgetOnDevices()`, `printWidgets()`, `printWidgetThemed()` |

---

## CLI Commands

The CLI is the primary user interface. All commands read `print_widget.yaml` for project settings.

### `init`

Sets up print_widget in a Flutter project. Creates:
- `print_widget.yaml` (project settings)
- `print_widget/config.dart` (Dart config with `printSession` + `printList` template)
- `test/flutter_test_config.dart` (font loading setup)
- `print_widget/output/` directory
- `PRINT_WIDGET.md` (LLM reference guide)
- `.gitignore` entries for output and temp files

Also runs `flutter pub add --dev print_widget_flutter` to add the package dependency.

After init, outputs AI-friendly guidance text with next steps (edit config, generate, install skills).

### `generate`

The main command. Generates screenshots by:
1. Reading `print_widget.yaml` for settings
2. Optionally deleting old output (`--delete-old`)
3. Generating a temp test at `.dart_tool/print_widget/print_test.dart`
4. Running `flutter test --update-goldens` on the temp test
5. Scanning the output directory and writing `manifest.json`

Flags:
- `--name=<entry>` -- generate a single entry (faster iteration)
- `--device=<device>` -- override the default device
- `--all-devices` -- generate for iPhone 15 Pro, Pixel 7, and iPad Pro 11
- `--flat` -- flat output naming (`name_device.png` instead of `name/device.png`)
- `--delete-old` -- clean output directory before generating

### `list`

Shows configured entries by regex-parsing the Dart config file. No Dart execution -- it pattern-matches `page()`, `widget()`, `pages()`, `widgets()`, and `state()` calls. Also shows project settings from `print_widget.yaml`.

### `config`

Views or modifies `print_widget.yaml` settings:
- `--device=<name>` -- change default device
- `--output=<dir>` -- change output directory
- `--flat` / `--no-flat` -- toggle flat mode
- `--manifest` / `--no-manifest` -- toggle manifest generation

### `skills`

Installs AI assistant skills. See the [AI Skills System](#ai-skills-system) section.

### `--llm-guide`

A global flag (not a subcommand) that prints a compact LLM reference with project-specific paths interpolated from `print_widget.yaml`. Designed to be piped to an AI assistant as context.

---

## VS Code Extension

**Name**: Print Widget Preview (`print-widget-preview`)
**Location**: `extensions/vscode/`
**Requires**: VS Code 1.85+, Node.js 18+ (to build from source)

The extension provides a visual UI for browsing, previewing, and comparing screenshots directly in VS Code.

### Features

#### 1. Sidebar Tree View

A dedicated "Print Widget" panel in the Activity Bar. Reads `manifest.json` and displays:

```
Print Widget
  +-- login_page (page)                    [FeatureNode]
  |   +-- iPhone 15 Pro  393x852           [DeviceNode]
  +-- sign_in (page)                       [FeatureNode]
  |   +-- empty                            [StateNode]
  |   |   +-- iPhone 15 Pro  393x852       [DeviceNode]
  |   |   +-- Pixel 7  412x915            [DeviceNode]
  |   +-- error                            [StateNode]
  |       +-- iPhone 15 Pro  393x852       [DeviceNode]
  +-- product_card (widget)                [FeatureNode]
      +-- iPhone 15 Pro  393x852           [DeviceNode]
```

Three-level hierarchy: **FeatureNode** (entry name) > **StateNode** (if grouped states) > **DeviceNode** (individual screenshot).

Single-device entries without states are clickable directly at the feature level.

#### 2. Preview Panel (`PreviewPanel`)

Click any device node to open a webview showing the screenshot. Displays device info (name, dimensions, physical pixels, type, state). Click the image to toggle between fit-to-width and actual-size views.

#### 3. Multi-Device Comparison (`ComparisonPanel`)

Right-click a feature or state node and select "Compare Devices". Opens a responsive grid of all device screenshots side by side. Each card shows device name, state badge, dimensions, and the screenshot.

#### 4. Before/After Diff (`DiffPanel`)

Right-click a device node and select "Diff with Previous". The extension:
1. First tries to extract the previous version from git (`git show HEAD:"<file>"`)
2. If not in git, prompts for a file to compare against
3. Opens a slider overlay: left side shows the old image, right side shows the current image. Drag the slider to compare.

#### 5. Figma Design Comparison (`FigmaComparisonPanel`)

Right-click a device node and select "Compare with Figma Design". The extension:
1. Checks for a `.reference/` directory next to the screenshot
2. If found, auto-loads the reference image
3. If not found, prompts user to select a design image
4. Shows a three-column view: **Screenshot | Design Reference | Differences**
5. Performs pixel-level comparison using an inline pixelmatch implementation
6. Shows a **similarity percentage** with color coding (green >= 95%, yellow >= 80%, red < 80%)
7. Includes a **threshold slider** to adjust comparison sensitivity
8. Warns if images have different dimensions (scales automatically)

#### 6. Source Linker (`SourceLinker`)

Right-click a feature node and select "Go to Definition". The extension:
1. Reads `print_widget.yaml` to find the config file path
2. Regex-searches the config file for the entry's `page('name')` / `widget('name')` call
3. Opens the file at the matching line

#### 7. Other Commands

- **Refresh** -- reloads manifest and updates the tree
- **Select Manifest** -- manually choose a different manifest.json
- **Open in Finder** -- opens the screenshot's directory in the OS file manager
- **Copy Path** -- copies the absolute path to clipboard

### How .reference/ Works

The `.reference/` directory is a convention used by both the AI skills and the VS Code extension:

```
print_widget/output/
  +-- login_page/
  |   +-- iphone_15_pro.png           <-- generated screenshot
  |   +-- .reference/
  |       +-- iphone_15_pro.png       <-- design target (from Figma export, etc.)
```

When the AI skill saves a Figma export or design image to `.reference/`, the VS Code extension:
- Shows "(ref)" next to device nodes that have a reference image
- Auto-loads the reference for Figma comparison (no file picker needed)
- The `FigmaComparisonPanel` provides pixel-level diff with similarity percentage

The `.reference/` lookup logic:
1. Check for exact filename match: `.reference/<device>.png`
2. If the `.reference/` directory exists with exactly one image, use that

### Manifest Watcher

The extension watches the output directory for changes to `manifest.json` and `.png` files. When changes are detected (debounced by 500ms), it refreshes the tree and all open preview panels.

### Activation

The extension activates when:
- The workspace contains `**/prints/output/manifest.json`
- The workspace contains `**/print_widget/output/manifest.json`
- The user explicitly triggers a command

### Build and Install

```bash
cd extensions/vscode
npm install
npm run build
npx @vscode/vsce package
code --install-extension print-widget-preview-0.1.0.vsix
```

---

## AI Skills System

The `skills` command installs AI assistant skill files that teach AI tools how to use print_widget for Figma-to-Flutter workflows.

### Supported AI Tools

| Tool | Detection | Project scope path | User scope path |
|------|-----------|-------------------|-----------------|
| Claude Code | `~/.claude/` or `.claude/` exists | `.claude/skills/print-widget/SKILL.md` | `~/.claude/skills/print-widget/SKILL.md` |
| Cursor | `.cursor/` or `~/.cursor/` exists | `.cursor/rules/print-widget.mdc` | N/A |
| Codex | `AGENTS.md`, `.agents/`, or `~/.codex/` exists | `.agents/skills/print-widget/SKILL.md` | `~/.agents/skills/print-widget/SKILL.md` |

### Available Skills

Currently one skill: **figma**

The `figma` skill teaches AI assistants the full Figma-to-Flutter workflow:
1. Get a Figma design (URL via Figma MCP, screenshot, or description)
2. Save a reference image to `.reference/` for VS Code comparison
3. Analyze the design (layout, colors, typography, spacing)
4. Build the Flutter widget
5. Add it to the print_widget config
6. Generate a screenshot
7. Compare with the design
8. Iterate until it matches

### Bundled Reference Files

The figma skill installs four additional reference files alongside the main skill:

| File | Purpose |
|------|---------|
| `conventions.md` | Widget structure rules: 3-level rule, 4+ children rule, no `_buildXxx()` methods, always extract to `StatelessWidget`, const constructors |
| `screen.md` | Screen patterns: callbacks over hardcoded logic, screen-provider separation, mock data best practices |
| `review.md` | Visual review checklist: layout, typography, colors, states, responsiveness |
| `iterate.md` | Visual iteration loop steps: generate, review, fix, regenerate |

These files are read automatically by the AI assistant when the skill is invoked. After installation, users are encouraged to customize them with project-specific tokens, component libraries, and team conventions.

### Tool-Specific Templates

Each AI tool gets a different template format:

- **Claude Code**: A SKILL.md with YAML frontmatter (`name`, `description`, `argument-hint`). Invoked as `/print-widget <figma-url> [instructions]`. References bundled files by relative path.
- **Cursor**: A `.mdc` rule file with glob triggers for config files and page/screen files.
- **Codex**: Similar to Claude but adapted for Codex's AGENTS.md format.

### Installation Modes

```bash
# Interactive (detects tools, prompts for selection)
print_widget skills

# Non-interactive
print_widget skills --install=figma
print_widget skills --install=figma --scope=user --tool=claude
print_widget skills --list
```

---

## MCP Integration

**Location**: `extensions/mcp/`

The MCP (Model Context Protocol) server provides structured resources and prompts that any MCP-compatible AI tool can consume.

### Configuration (`config.yaml`)

```yaml
name: print_widget
description: Capture Flutter widgets as PNG screenshots for LLM visual verification.
```

### Resources (read-only reference material)

| Resource | What it provides |
|----------|-----------------|
| `guide` | Quick reference: CLI commands, config format, entry syntax, device list, limitations |
| `api_reference` | Full public API: all classes, functions, types, and their signatures |
| `architecture` | Internal design: pipeline, rendering modes, font loading, config relationship |

### Prompts (step-by-step workflows)

| Prompt | Workflow |
|--------|----------|
| `setup_project` | Full init sequence: install CLI, run init, configure AppWrapper with theme/providers, add entries, generate |
| `add_entry` | How to add pages and widgets to printList with device and size options, plus the Printable mixin |
| `generate_and_compare` | Generate screenshots, find PNGs via manifest, compare with design, iterate until matching, multi-device verification |

### Usage

MCP resources and prompts can be consumed by any AI tool with MCP support. The AI tool queries the MCP server for the resource/prompt by name, receives the content, and uses it as context for completing tasks.

---

## The Complete User Workflow

### Phase 1: Project Setup

```
Developer                          CLI                         Project Files
    |                               |                               |
    |--- print_widget init -------->|                               |
    |                               |--- flutter pub add --dev ---->| pubspec.yaml
    |                               |--- create ------------------->| print_widget.yaml
    |                               |--- create ------------------->| print_widget/config.dart
    |                               |--- create ------------------->| test/flutter_test_config.dart
    |                               |--- create ------------------->| print_widget/output/
    |                               |--- create ------------------->| PRINT_WIDGET.md
    |                               |--- update ------------------->| .gitignore
    |<-- "Setup complete!" ---------|                               |
```

### Phase 2: Configure Entries

The developer (or AI assistant) edits `print_widget/config.dart`:

```dart
final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: AppTheme.light,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
);

final printList = <PrintEntry>[
  page('login_page', const LoginPage()),
  widget('product_card', ProductCard(data: mockProduct), size: Size(350, 420)),
  pages('onboarding', states: [
    state('step1', OnboardingScreen(step: 1)),
    state('step2', OnboardingScreen(step: 2)),
    state('step3', OnboardingScreen(step: 3)),
  ]),
];
```

### Phase 3: Generate Screenshots

```
Developer                          CLI                      Flutter Test        File System
    |                               |                            |                   |
    |--- generate ----------------->|                            |                   |
    |                               |--- read ------------------>| print_widget.yaml |
    |                               |--- write temp test ------->| .dart_tool/...    |
    |                               |--- flutter test ---------->|                   |
    |                               |                            |--- pumpWidget --->|
    |                               |                            |--- golden PNG --->| output/*.png
    |                               |<-- test complete ----------|                   |
    |                               |--- scan output dir ------->|                   |
    |                               |--- write manifest -------->| manifest.json     |
    |<-- "Done!" -------------------|                            |                   |
```

### Phase 4: Browse in VS Code

```
VS Code Extension                  manifest.json              Output Directory
    |                                   |                          |
    |--- findManifest() --------------->|                          |
    |<-- parse, group by feature -------|                          |
    |                                                              |
    |--- [user clicks device node] --->|                          |
    |--- PreviewPanel.show() ----------|--- read PNG ------------->|
    |                                  |                          |
    |--- [user: Compare Devices] ----->|                          |
    |--- ComparisonPanel.show() -------|--- read multiple PNGs -->|
    |                                  |                          |
    |--- [user: Compare with Figma] -->|                          |
    |--- FigmaComparisonPanel.show() --|--- read PNG + .reference/|
    |<-- similarity: 94.2% ------------|                          |
```

### Phase 5: Figma Design Iteration (AI-Assisted)

This is the flagship workflow, powered by the installed AI skill:

```
AI Assistant                        CLI                       VS Code Extension
    |                                |                              |
    |--- /print-widget <figma-url>   |                              |
    |                                |                              |
    |--- [fetch Figma design via MCP]|                              |
    |--- [analyze layout, colors]    |                              |
    |--- [build Flutter widget]      |                              |
    |--- [add to printList]          |                              |
    |                                |                              |
    |--- generate --name=login ----->|                              |
    |<-- PNGs generated -------------|                              |
    |                                |                              |
    |--- [save reference to .reference/]                            |
    |                                |                              |
    |--- [read generated PNG]        |                              |
    |--- [compare with design]       |                              |
    |                                |              [user opens VS Code]
    |                                |                              |
    |                                |              |--- tree shows (ref) badge
    |                                |              |--- Figma Compare: 87.3%
    |                                |              |--- highlights red pixels
    |                                |                              |
    |--- [user says "fix spacing"]   |                              |
    |--- [update widget code]        |                              |
    |--- generate --name=login ----->|                              |
    |<-- PNGs regenerated -----------|                              |
    |--- [compare again: 96.1%]      |                              |
    |                                |              |--- auto-refresh
    |                                |              |--- similarity: 96.1%
    |                                |                              |
    |--- "Looks good! Ship it."      |                              |
```

---

## How Everything Connects

### Full Ecosystem Diagram

```
+---------------------------------------------------------------------+
|  DEVELOPER'S FLUTTER PROJECT                                        |
|                                                                     |
|  pubspec.yaml                                                       |
|    dev_dependencies:                                                |
|      print_widget_flutter: ^0.1.0                                   |
|                                                                     |
|  print_widget.yaml ------+                                          |
|    config_file  ----------+---> print_widget/config.dart            |
|    output_dir   ----------+       printSession (AppWrapper, device) |
|    default_device         |       printList (entries to capture)     |
|    manifest: true         |                                         |
|    flat: false            |                                         |
|                           |                                         |
|                           v                                         |
|  .dart_tool/print_widget/print_test.dart  <-- generated by CLI      |
|    imports config.dart                                              |
|    runs in flutter test                                             |
|                           |                                         |
|                           v                                         |
|  print_widget/output/ --------+                                     |
|    login_page/                |                                     |
|      iphone_15_pro.png        |                                     |
|      .reference/              |--- VS Code Extension reads these    |
|        iphone_15_pro.png      |    for Figma comparison             |
|    product_card/              |                                     |
|      iphone_15_pro.png        |                                     |
|    manifest.json  <-----------+--- VS Code Extension reads this     |
|                                    for tree view & preview          |
|                                                                     |
|  .claude/skills/print-widget/ <-- installed by "skills" command     |
|    SKILL.md                       AI reads this for workflows       |
|    conventions.md                                                   |
|    screen.md                                                        |
|    review.md                                                        |
|    iterate.md                                                       |
|                                                                     |
|  PRINT_WIDGET.md  <-- created by "init", LLM reference guide       |
|  test/flutter_test_config.dart  <-- font loading                    |
+---------------------------------------------------------------------+

+---------------------------------------------------------------------+
|  EXTERNAL CONNECTIONS                                                |
|                                                                     |
|  Figma MCP Server                                                   |
|    |                                                                |
|    +-- AI fetches design frames via MCP                             |
|    +-- Exports PNG, saved to .reference/                            |
|                                                                     |
|  print_widget MCP Server (extensions/mcp/)                          |
|    |                                                                |
|    +-- Resources: guide, api_reference, architecture                |
|    +-- Prompts: setup_project, add_entry, generate_and_compare      |
|    +-- Any MCP-compatible tool can query these                      |
|                                                                     |
|  AI Assistants (Claude Code / Cursor / Codex)                       |
|    |                                                                |
|    +-- Read SKILL.md for Figma workflow instructions                |
|    +-- Read bundled reference files (conventions, screen, etc.)     |
|    +-- Execute CLI commands (generate, list, config)                |
|    +-- Read manifest.json to find generated PNGs                    |
|    +-- Read PNGs to visually verify output                          |
|    +-- Save reference images to .reference/                         |
+---------------------------------------------------------------------+
```

### Connection Points

**CLI <-> Flutter test framework**: The CLI generates a temp `.dart` test file that imports the user's config, then shells out to `flutter test --update-goldens`. Flutter test is the rendering engine.

**CLI <-> manifest.json <-> VS Code extension**: The CLI generates `manifest.json` after screenshots are created. The VS Code extension reads `manifest.json` to populate the tree view, resolve image paths, and determine feature/state/device groupings.

**AI skill <-> .reference/ <-> VS Code extension**: The AI skill instructs the assistant to save Figma exports or design images to `.reference/` directories. The VS Code extension auto-detects these for pixel comparison with similarity percentage. This creates a feedback loop: AI generates, VS Code shows the diff, human confirms.

**MCP server <-> AI tools**: The MCP server at `extensions/mcp/` provides structured resources (guide, API reference, architecture) and prompts (setup, add entry, generate-and-compare) that any MCP-compatible AI tool can query for context.

**Figma MCP <-> skill <-> reference images**: When the AI skill receives a Figma URL, it uses the Figma MCP to fetch the design frame, exports it as PNG, and saves it to `.reference/`. This reference image is then used by both the AI (for visual comparison) and the VS Code extension (for pixel diff).

**Source linker**: The VS Code extension's `SourceLinker` reads `print_widget.yaml` to find the config file path, then regex-searches for the entry definition. This bridges the gap between screenshot output and source code.

**Manifest watcher**: The `ManifestWatcher` monitors the output directory for file changes. When the CLI regenerates screenshots, the VS Code extension automatically refreshes the tree and all open preview panels within 500ms.

---

## File Map

### Dart Library (`lib/`)

| File | Purpose |
|------|---------|
| `lib/print_widget.dart` | Barrel export file -- exports all public API |
| `lib/src/app_wrapper.dart` | `AppWrapper` typedef + `appWrapperFromMaterialApp` helper |
| `lib/src/device_frame.dart` | `DeviceFrame` class with 16 presets + 3 groups |
| `lib/src/font_loader.dart` | `loadPrintWidgetFonts()`, `loadCustomFonts()`, `loadPackageFonts()` |
| `lib/src/print_config.dart` | `PrintConfig` -- standalone API configuration |
| `lib/src/print_entry.dart` | `PrintEntry` class + `page()`, `widget()`, `pages()`, `widgets()` helpers |
| `lib/src/print_manifest.dart` | `PrintManifest` / `PrintManifestEntry` data classes |
| `lib/src/print_session.dart` | `PrintSession` -- top-level session configuration |
| `lib/src/print_state.dart` | `PrintState` class, `state()` helper, `StateOutputMode` enum |
| `lib/src/print_widget_runner.dart` | All rendering functions: `printEntry()`, `printAllEntries()`, `printWidget()`, etc. |
| `lib/src/printable.dart` | `Printable` mixin + `PrintType` enum |

### CLI (`lib/src/cli/`)

| File | Purpose |
|------|---------|
| `cli_runner.dart` | Entry point, `--llm-guide` handler, banner display |
| `commands/init_command.dart` | `print_widget init` -- project scaffolding |
| `commands/generate_command.dart` | `print_widget generate` -- temp test generation + flutter test execution + manifest writing |
| `commands/list_command.dart` | `print_widget list` -- regex-based config parsing |
| `commands/config_command.dart` | `print_widget config` -- YAML settings viewer/editor |
| `commands/skills_command.dart` | `print_widget skills` -- AI tool detection, skill installation, template generation |

### VS Code Extension (`extensions/vscode/src/`)

| File | Purpose |
|------|---------|
| `extension.ts` | Activation, manifest discovery, watcher setup |
| `manifest/manifest-parser.ts` | Parse `manifest.json`, group entries by feature/state |
| `manifest/manifest-watcher.ts` | Watch output directory for file changes |
| `tree/screenshot-tree-provider.ts` | TreeDataProvider for the sidebar tree view |
| `tree/tree-items.ts` | `FeatureNode`, `StateNode`, `DeviceNode` tree item classes |
| `commands/commands.ts` | All registered VS Code commands (preview, compare, diff, source link, etc.) |
| `webview/preview-panel.ts` | Single image preview with zoom toggle |
| `webview/comparison-panel.ts` | Multi-device comparison grid |
| `webview/diff-panel.ts` | Before/after slider overlay (git-based or manual) |
| `webview/figma-comparison-panel.ts` | Three-panel design comparison with pixelmatch and similarity score |
| `webview/utils.ts` | Shared utilities: escapeHtml, formatDevice, getNonce, cspMeta |
| `source-linker/source-linker.ts` | Find entry definition in config file by regex |

### MCP Server (`extensions/mcp/`)

| File | Purpose |
|------|---------|
| `config.yaml` | Server name, description, resource/prompt declarations |
| `resources/guide.md` | Quick reference: CLI, config, entries, devices |
| `resources/api_reference.md` | Full public API with signatures and tables |
| `resources/architecture.md` | Pipeline, rendering, fonts, config relationship |
| `prompts/setup_project.md` | Step-by-step project initialization workflow |
| `prompts/add_entry.md` | How to add pages, widgets, multi-device, Printable mixin |
| `prompts/generate_and_compare.md` | Generate, find PNGs, compare with design, iterate |

### Documentation (`doc/`)

| File | Purpose |
|------|---------|
| `architecture.md` | Internal design decisions, constraints, pipeline |
| `standalone-api.md` | Lower-level test API reference |

### Key Generated Files (in user's project)

| File | Created by | Purpose |
|------|-----------|---------|
| `print_widget.yaml` | `init` | Project-level settings |
| `print_widget/config.dart` | `init` | Runtime config (printSession + printList) |
| `test/flutter_test_config.dart` | `init` | Font loading before tests |
| `PRINT_WIDGET.md` | `init` | LLM reference guide |
| `.dart_tool/print_widget/print_test.dart` | `generate` | Temporary test file (auto-generated, not committed) |
| `print_widget/output/manifest.json` | `generate` | Machine-readable index of all screenshots |
| `print_widget/output/<name>/<device>.png` | `generate` | Actual screenshot images |
| `print_widget/output/<name>/.reference/<device>.png` | AI skill | Design reference images for comparison |
