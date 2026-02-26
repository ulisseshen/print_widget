# print_widget

Capture Flutter widgets and pages as PNG screenshots for visual verification. Designed for LLMs to generate, compare, and iterate on UI during development.

## Project structure

```
lib/
  src/
    cli/
      cli_runner.dart              # Entry point, --llm-guide handler, banner
      commands/
        init_command.dart          # print_widget init
        generate_command.dart      # print_widget generate (runs flutter test --update-goldens)
        list_command.dart          # print_widget list (static regex parse of config)
        config_command.dart        # print_widget config (read/write print_widget.yaml)
        skills_command.dart        # print_widget skills (install AI skills for Claude/Cursor/Codex)
    print_entry.dart               # PrintEntry class + page/widget/pages/widgets helpers
    print_session.dart             # PrintSession (appWrapper, defaultDevice, stateOutputMode)
    print_state.dart               # PrintState, state() helper, StateOutputMode enum
    device_frame.dart              # DeviceFrame definitions + preset groups
    print_widget_runner.dart       # Standalone test API (printWidget, printEntry, etc.)
    print_manifest.dart            # PrintManifest / PrintManifestEntry data classes
    printable.dart                 # Printable mixin + PrintType enum
    font_loader.dart               # loadPrintWidgetFonts, loadCustomFonts, loadPackageFonts
doc/
  architecture.md                  # Internal design decisions
  standalone-api.md                # Lower-level test API reference
extensions/mcp/                    # MCP server resources and prompts
example/                           # Example Flutter project
```

## CLI commands

```bash
print_widget init                        # Set up in a Flutter project
print_widget generate                    # Generate all screenshots
print_widget generate --name=login_page  # Generate one entry
print_widget generate --device=pixel_7   # Override device
print_widget generate --all-devices      # All popular devices (iPhone 15 Pro, Pixel 7, iPad Pro 11)
print_widget generate --delete-old       # Delete old screenshots before generating
print_widget list                        # Show configured entries (static parse)
print_widget config                      # View current settings
print_widget config --device=pixel_7     # Change default device
print_widget skills                      # Interactive: detect AI tools, select and install skills
print_widget skills --install=figma      # Install specific skill (non-interactive)
print_widget skills --install=figma,iterate --scope=user  # Install to user scope
print_widget skills --list               # List available skills
print_widget skills --tool=claude        # Target specific AI tool
print_widget --llm-guide                 # Print compact LLM reference with project-specific paths
```

## Skills system

The `skills` command installs AI assistant skills for Claude Code, Cursor, and Codex.

### How it works

1. Auto-detects which AI tools are installed (checks `~/.claude/`, `.cursor/`, `AGENTS.md`)
2. Shows available skills with descriptions
3. User selects skills and scope (project or user)
4. Installs skill files to the correct location per tool

### Available skills

| Skill | What it does | Slash command |
|-------|-------------|---------------|
| `figma` | Convert Figma designs to Flutter widgets with screenshot comparison | `/print_widget:figma` |
| `iterate` | Visual iteration loop: generate, review, modify, regenerate | `/print_widget:iterate` |
| `conventions` | Widget conventions: composition over nesting, extraction rules, const constructors | `/print_widget:conventions` |
| `screen` | Screen patterns: callbacks for actions, mock data population, screen-provider separation | `/print_widget:screen` |
| `review` | Visual review: audit generated screenshots against design intent | `/print_widget:review` |

Each skill is a starting point. After installation, users are encouraged to edit the files directly to add project-specific tokens, component libraries, and team conventions.

### Installation paths

| Tool | Project scope | User scope |
|------|--------------|------------|
| Claude Code | `.claude/commands/print_widget:<skill>.md` | `~/.claude/commands/print_widget:<skill>.md` |
| Cursor | `.cursor/rules/print_widget:<skill>.mdc` | N/A |
| Codex | `.codex/skills/print_widget:<skill>.md` | N/A |

## How generation works

1. CLI reads `print_widget.yaml` for paths and settings
2. If `--delete-old`, deletes all contents of the output directory
3. Generates a temp test file at `.dart_tool/print_widget/print_test.dart`
4. Runs `flutter test --update-goldens` on that temp file
5. Generates `manifest.json` in the output directory

## Key conventions

- **Composition over nesting**: Prefer flat widget trees with extracted private `StatelessWidget` classes. No `_buildXxx()` methods — always extract to `_WidgetName extends StatelessWidget`. Max 3 levels deep before extraction.
- The user's config file exports `printSession` (a `PrintSession`) and `printList` (a `List<PrintEntry>`)
- `page()` / `widget()` for single entries; `pages()` / `widgets()` with `state()` for grouped states
- Output PNGs go to `<output_dir>/<name>/<device>.png` (or with state prefixes/suffixes/folders)
- `--update-goldens` is the Flutter mechanism that writes PNGs; there is no headless renderer outside tests

## Testing

```bash
# Run all tests
cd example && flutter test

# Run project analysis
dart analyze
```

## Config files

| File | Format | Purpose |
|------|--------|---------|
| `print_widget.yaml` | YAML | Project-level settings (paths, default device, manifest toggle) |
| `print_widget/config.dart` | Dart | Runtime config (`printSession` + `printList`) |

## Constraints

- Requires Flutter SDK on host machine
- No animations (captures settled state after `pumpAndSettle()`)
- No network images without internet during generate
- No platform channels (use mocks)
