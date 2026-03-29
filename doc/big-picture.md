# print_widget -- The Big Picture

A comprehensive overview of the print_widget ecosystem: what it is, how every piece connects, and how to use the full workflow from zero to production.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [What Is print_widget?](#what-is-print_widget)
3. [Complete Architecture](#complete-architecture)
4. [The Rendering Pipeline](#the-rendering-pipeline)
5. [VS Code Extension](#vs-code-extension)
6. [AI Skills System](#ai-skills-system)
7. [MCP Integration](#mcp-integration)
8. [The Complete User Workflow](#the-complete-user-workflow)
9. [How Everything Connects](#how-everything-connects)
10. [File Map](#file-map)

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

#### 2. Webview Panels

| Panel | Trigger | What it does |
|-------|---------|-------------|
| **PreviewPanel** | Click device node | Full screenshot preview with fit/actual-size toggle |
| **ComparisonPanel** | Right-click feature > Compare Devices | Side-by-side grid of all devices |
| **DiffPanel** | Right-click device > Diff with Previous | Slider overlay comparing git HEAD vs current (falls back to file picker) |
| **FigmaComparisonPanel** | Right-click device > Compare with Figma | Three-column view (screenshot, design, pixel diff) with similarity % and threshold slider |

#### 3. Other Commands

- **Go to Definition** -- regex-finds entry in config file via `SourceLinker`
- **Refresh** / **Select Manifest** / **Open in Finder** / **Copy Path**

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

See `CLAUDE.md` for MCP server files, documentation files, and generated file details.
| `print_widget/output/<name>/.reference/<device>.png` | AI skill | Design reference images for comparison |
