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
    print_entry.dart               # PrintEntry class + page/widget/pages/widgets helpers
    print_session.dart             # PrintSession (appWrapper, defaultDevice, stateOutputMode)
    print_state.dart               # PrintState, state() helper, StateOutputMode enum
    device_frame.dart              # DeviceFrame definitions + preset groups
    print_widget_runner.dart       # Standalone test API (printWidget, printEntry, etc.)
    print_manifest.dart            # PrintManifest / PrintManifestEntry data classes
    printable.dart                 # Printable mixin + PrintType enum
    font_loader.dart               # loadPrintWidgetFonts, loadCustomFonts, loadPackageFonts
docs/
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
print_widget --llm-guide                 # Print compact LLM reference with project-specific paths
```

## How generation works

1. CLI reads `print_widget.yaml` for paths and settings
2. If `--delete-old`, deletes all contents of the output directory
3. Generates a temp test file at `.dart_tool/print_widget/print_test.dart`
4. Runs `flutter test --update-goldens` on that temp file
5. Generates `manifest.json` in the output directory

## Key conventions

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
