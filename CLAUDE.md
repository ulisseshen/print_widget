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
        compare_command.dart       # print_widget compare (pixelmatch per-region diff via Node)
        skills_command.dart        # print_widget skills (install AI skills for Claude/Cursor/Codex)
    tools/
      pixelmatch_batch.mjs         # Node helper — batched pixelmatch runner, heatmap output
      extract.mjs                  # Playwright-based token extractor (used by smart-extract skill)
    print_entry.dart               # PrintEntry class + page/widget/pages/widgets helpers (with crops)
    print_session.dart             # PrintSession (appWrapper, defaultDevice, stateOutputMode, flat)
    print_state.dart               # PrintState, state() helper, StateOutputMode enum
    device_frame.dart              # DeviceFrame definitions + preset groups
    print_widget_runner.dart       # Standalone test API (printWidget, printEntry, etc.)
    print_manifest.dart            # PrintManifest / PrintManifestEntry data classes
    printable.dart                 # Printable mixin + PrintType enum
    font_loader.dart               # loadPrintWidgetFonts, loadCustomFonts, loadPackageFonts
    crops.dart                     # CropRegion, loadCropsFromJson, writeCropsToDisk, processEntryCrops
doc/
  architecture.md                  # Internal design decisions
  standalone-api.md                # Lower-level test API reference
extensions/mcp/                    # MCP server resources and prompts
extensions/vscode/                 # VS Code preview extension (sidebar, comparison, Figma diff)
example/                           # Example Flutter project
```

## CLI commands

```bash
print_widget init                        # Set up in a Flutter project
print_widget generate                    # Generate all screenshots
print_widget generate --name=login_page  # Generate one entry
print_widget generate --device=pixel_7   # Override device
print_widget generate --all-devices      # All popular devices (iPhone 15 Pro, Pixel 7, iPad Pro 11)
print_widget generate --flat              # Flat output: name_device.png (no subfolders)
print_widget generate --delete-old       # Delete old screenshots before generating
print_widget compare                     # Diff generated vs reference (pixelmatch, per-region)
print_widget compare --name=login_page   # Diff one entry
print_widget compare --threshold=0.98    # Override per-region threshold (default 0.95)
print_widget compare --json              # Machine-readable output
print_widget list                        # Show configured entries (static parse)
print_widget config                      # View current settings
print_widget config --device=pixel_7     # Change default device
print_widget config --flat               # Enable flat output permanently
print_widget config --no-flat            # Disable flat output
print_widget config --reference-dir=.reference     # Change reference images dir
print_widget config --compare-threshold=0.95        # Change compare gate
print_widget skills                      # Interactive: detect AI tools, select and install skills
print_widget skills --install=figma      # Install specific skill (non-interactive)
print_widget skills --only=extract       # Install smart-extract-design (Lovable/web capture)
print_widget skills --install=figma,iterate --scope=user  # Install to user scope
print_widget skills --update             # Update installed skills to latest version
print_widget skills --list               # List available skills
print_widget skills --tool=claude        # Target specific AI tool (claude/cursor/codex/antigravity)
print_widget --llm-guide                 # Print compact LLM reference with project-specific paths
```

## Skills system

The `skills` command installs AI assistant skills for Claude Code, Cursor, and Codex.

### How it works

1. Auto-detects which AI tools are installed (checks `~/.claude/`, `.cursor/`, `AGENTS.md`, `.agents/`)
2. Shows available skills with descriptions
3. User selects skills and scope (project or user)
4. Installs skill files to the correct location per tool

### Available skills

| Command | What it does |
|---------|-------------|
| `/print-widget figma <url> [instructions]` | Convert Figma designs to Flutter widgets with screenshot comparison loop |
| `/print-widget stitch <description> [instructions]` | Generate UI with Stitch (Google AI), implement in Flutter, verify with screenshots |
| `/print-widget update` | Update print_widget CLI and skill files to the latest version |

The figma skill bundles internal reference files that the AI reads automatically:
- `conventions.md` — Widget structure rules (composition, extraction, const constructors)
- `screen.md` — Screen patterns (callbacks, screen-provider separation, mock data)
- `review.md` — Visual review checklist
- `iterate.md` — Visual iteration loop

After installation, users are encouraged to edit these files to add project-specific tokens, component libraries, and team conventions.

### Installation paths

| Tool | Project scope | User scope |
|------|--------------|------------|
| Claude Code | `.claude/skills/print-widget-<skill>/SKILL.md` | `~/.claude/skills/print-widget-<skill>/SKILL.md` |
| Cursor | `.cursor/rules/print-widget-<skill>.mdc` | N/A |
| Codex | `.agents/skills/print-widget-<skill>/SKILL.md` | `~/.agents/skills/print-widget-<skill>/SKILL.md` |
| Antigravity | `.agent/skills/print-widget-<skill>/SKILL.md` | `~/.gemini/antigravity/skills/print-widget-<skill>/SKILL.md` |

## How generation works

1. CLI reads `print_widget.yaml` for paths and settings
2. If `--delete-old`, deletes all contents of the output directory
3. Generates a temp test file at `.dart_tool/print_widget/print_test.dart`
4. Runs `flutter test --update-goldens` on that temp file
5. For entries with `crops` or `cropsFrom`, extracts named regions into `<entry>/crops/<name>.png`
6. Generates `manifest.json` in the output directory (skipping `.reference/` and `crops/` sidecars)

## How compare works

1. `print_widget compare --name=<entry>` reads `print_widget.yaml` for `reference_dir` (default `.reference`) and `compare_threshold` (default 0.95)
2. Locates reference crops at `<outputDir>/<entry>/<reference_dir>/crops/*.png` (or top-level PNG fallback)
3. Pairs each reference crop with a matching generated crop at `<outputDir>/<entry>/crops/*.png`
4. Resolves `lib/src/tools/pixelmatch_batch.mjs` via `Isolate.resolvePackageUri` — works after `dart pub global activate` and in local dev
5. Spawns `node pixelmatch_batch.mjs`, pipes a JSON payload of pair paths via stdin
6. The Node helper uses pixelmatch v7 with `includeAA: false` (suppresses AA false positives on Flutter text), writes heatmap PNGs next to the generated crops as `<region>_diff.png`, returns per-pair similarity
7. Dart parses results, prints human or JSON output, exits 0 if all regions ≥ threshold else 1

## Key conventions

- **Composition over nesting**: Prefer flat widget trees with extracted private `StatelessWidget` classes. No `_buildXxx()` methods — always extract to `_WidgetName extends StatelessWidget`. Max 3 levels deep before extraction.
- The user's config file exports `printSession` (a `PrintSession`) and `printList` (a `List<PrintEntry>`)
- `page()` / `widget()` for single entries; `pages()` / `widgets()` with `state()` for grouped states
- Output PNGs go to `<output_dir>/<name>/<device>.png` (or with state prefixes/suffixes/folders). With `--flat`: `<output_dir>/<name>_<device>.png`
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
| `print_widget.yaml` | YAML | Project-level settings (paths, default device, manifest, flat toggle) |
| `print_widget/config.dart` | Dart | Runtime config (`printSession` + `printList`) |

## Constraints

- Requires Flutter SDK on host machine
- No animations (captures settled state after `pumpAndSettle()`)
- No network images without internet during generate
- No platform channels (use mocks)
