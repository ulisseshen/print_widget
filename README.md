# print_widget

Capture Flutter widgets as PNG screenshots. Built for LLMs to see what they build.

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/login_page.png" width="200" alt="Login Page" />
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/home_page.png" width="200" alt="Home Page" />
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/product_card.png" width="200" alt="Product Card" />
  <img src="https://raw.githubusercontent.com/ulisseshen/print_widget/main/doc/screenshots/stats_card.png" width="200" alt="Stats Card" />
</p>

## What it does

You define widgets. It generates PNGs. LLMs read the PNGs and iterate on the UI.

```
You write code → print_widget generates screenshots → LLM sees the result → fixes UI → repeat
```

## Two things in one

| What | Purpose | Install |
|------|---------|---------|
| **CLI** | Run `generate`, `list`, `config` | `dart pub global activate print_widget_flutter` |
| **Dev dependency** | Use `PrintSession`, `PrintEntry`, `Printable` in code | Added by `print_widget init` |

The CLI runs commands. The dev dependency gives you the Dart classes. `print_widget init` sets up both.

## Quick start

### 1. Install CLI (once)

```bash
dart pub global activate print_widget_flutter
```

> **Not yet on pub.dev?** Install directly from GitHub:
> ```bash
> dart pub global activate --source git https://github.com/ulisseshen/print_widget.git
> ```

### 2. Set up your project

```bash
cd my_flutter_app
print_widget init
```

### 3. Edit the config

Open `test/prints/print_config.dart`:

```dart
final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: MyAppTheme.light,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
);

final printList = <PrintEntry>[
  page('login_page', const LoginPage()),
  widget('product_card', ProductCard(title: 'Demo'), size: Size(350, 420)),

  // Multiple states of the same screen
  pages('sign_in', states: [
    state('empty', SignInScreen()),
    state('error', SignInScreen(initialError: 'Invalid email')),
  ]),
];
```

### 4. Generate

```bash
print_widget generate
```

Done. PNGs + `manifest.json` in your output directory.

## AI Assistant Onboarding

If you are an AI assistant (Claude Code, Cursor, Codex) setting up print_widget in a Flutter project, follow this complete onboarding flow:

### Step 1: Install the CLI globally

```bash
dart pub global activate --source git https://github.com/ulisseshen/print_widget.git
```

**Do NOT** add print_widget to the project's `pubspec.yaml`. It is a CLI tool, not a library dependency.

### Step 2: Run init and follow the onboarding output

```bash
cd <flutter_project>
print_widget init
```

The `init` command creates all needed files and prints **onboarding instructions specifically for you**. Read and follow them — they guide you through:
- Editing the config file with the project's theme and widgets
- Running `print_widget generate`
- Installing the AI skill (`print_widget skills --install=figma`)
- Detecting VS Code/Cursor and offering to install the preview extension

### Step 3: Read the compact reference

```bash
print_widget --llm-guide
```

This prints a condensed guide with project-specific paths, all CLI commands, entry types, device list, and the VS Code extension install instructions.

### Step 4: Add widgets to capture

Edit the config file (path shown in `init` output) and add the project's widgets:

```dart
final printList = <PrintEntry>[
  page('login_page', const LoginPage()),
  widget('product_card', ProductCard(data: mock), size: Size(350, 420)),
];
```

### Step 5: Generate and verify

```bash
print_widget generate
```

Read `manifest.json` in the output directory to find generated PNG paths. Read the PNGs to visually verify your UI work. Iterate until the screenshots match the design.

### What happens after onboarding

Once set up, you can:
- `/print-widget <figma-url>` — convert a Figma design to Flutter with screenshot comparison loop
- `print_widget generate --name=<entry>` — regenerate a single screenshot after code changes
- `print_widget generate --all-devices` — test responsive layouts across iPhone, Pixel, iPad
- Compare screenshots with design references in the VS Code extension sidebar

## CLI commands

```bash
print_widget init                        # Set up project
print_widget generate                    # Generate all screenshots
print_widget generate --name=login_page  # Generate one entry
print_widget generate --device=pixel_7   # Override device
print_widget generate --all-devices      # All popular devices
print_widget generate --delete-old       # Clean regenerate
print_widget list                        # Show configured entries
print_widget config                      # View settings
print_widget config --device=pixel_7     # Change default device
print_widget skills                      # Install AI assistant skills (Claude, Cursor, Codex)
print_widget skills --list               # List available skills
print_widget --llm-guide                 # Print LLM reference
```

## Page vs Widget

| | Page | Widget |
|---|---|---|
| Layout | Full screen | Centered in Scaffold |
| Use for | Screens, routes | Components, cards, buttons |
| Custom size | Uses device size | Optional `size:` parameter |

## Grouped states

Capture multiple visual states of the same component:

```dart
pages('sign_in_screen', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(initialError: 'Invalid email')),
  state('filled', SignInScreen(initialEmail: 'user@test.com')),
])
```

Output naming via `StateOutputMode`:

| Mode | File path |
|------|-----------|
| `prefix` (default) | `sign_in_screen/empty_iphone_15_pro.png` |
| `suffix` | `sign_in_screen/iphone_15_pro_empty.png` |
| `folder` | `sign_in_screen/empty/iphone_15_pro.png` |

## Devices

```dart
DeviceFrame.iPhone15Pro   // 393x852 @3x
DeviceFrame.pixel7        // 412x915 @2.625x
DeviceFrame.iPadPro11     // 834x1194 @2x
DeviceFrame.popular       // [iPhone15Pro, pixel7, iPadPro11]
DeviceFrame.allPhones     // 8 phone devices
DeviceFrame.allTablets    // 4 tablet devices
```

## Manifest

Generated `manifest.json` for LLM consumption:

```json
{
  "generatedAt": "2026-02-13T15:00:00Z",
  "screenshots": [
    {
      "name": "login_page",
      "type": "page",
      "file": "test/prints/output/login_page/iphone_15_pro.png",
      "device": "iphone_15_pro",
      "width": 393.0,
      "height": 852.0
    }
  ]
}
```

## LLM workflow

```
1. LLM implements LoginPage
2. LLM adds to printList: page('login_page', LoginPage())
3. LLM runs: print_widget generate --name=login_page
4. LLM reads manifest.json → finds PNG → views screenshot
5. LLM compares with design → iterates until it matches
```

## Works great with MCP tools

print_widget is designed to work with AI design tools via MCP (Model Context Protocol):

### Figma MCP
Autonomous design-match loop — fetch a Figma frame, implement the Flutter widget, generate a screenshot, compare pixels, fix differences, repeat until it matches.

```
AI fetches Figma design → builds widget → print_widget generate → compare → iterate
```

Reference images from Figma are saved to `.reference/` for automatic comparison in the VS Code extension.

- [Figma MCP Server](https://github.com/nicokosi/figma-mcp)

### Stitch (Google AI UI)
Generate UI screens with Stitch, then verify the Flutter implementation matches with print_widget screenshots. Stitch creates design screens from text prompts or code, and print_widget captures what the Flutter code actually renders — compare both to ensure pixel-perfect implementation.

```
Stitch generates design → AI implements in Flutter → print_widget generate → compare
```

- [Stitch MCP](https://developers.google.com/stitch)

## VS Code Extension

Preview and compare screenshots directly in VS Code.

- Sidebar tree view grouped by feature, state, and device
- Multi-device comparison grid
- Before/after diff with slider overlay
- Design reference comparison with similarity percentage (auto-detects `.reference/` images)

Requires Node.js 18+ to build from source:

```bash
cd extensions/vscode && npm install && npm run build && npx @vscode/vsce package
code --install-extension print-widget-preview-*.vsix
```

See [extensions/vscode/README.md](extensions/vscode/README.md) for full installation instructions (macOS, Linux, Windows).

## Docs

- [Architecture](doc/architecture.md)
- [Standalone test API](doc/standalone-api.md)
