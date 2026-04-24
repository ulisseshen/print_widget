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
print_widget extract --url=<url>         # Capture design + per-element _spec.json (Playwright-backed)
print_widget extract --config=states.json --theme=theme-ref.json  # Multi-state capture
print_widget snapshot --name=<entry>     # Promote generated to reference (Flutter-native baseline)
print_widget snapshot --all              # Snapshot every entry's generated output
print_widget scaffold --spec=<path>      # Mechanical codegen: _spec.json → Flutter widget (literals only)
print_widget scaffold --spec=<path> --stdout   # Print scaffold without writing
print_widget tokenize --input=<scaffold> --theme=theme-ref.json   # Swap literals → DS tokens
print_widget figma-spec --input=<figma.json> --output=<spec.json>  # Normalize Figma MCP response → spec v1
print_widget fonts                       # Download Google Fonts TTFs from _fonts.json into google_fonts/
print_widget fonts --source=<_fonts.json> --dest=assets/fonts       # Install to assets/fonts + update pubspec
print_widget fonts --dry-run --json      # Preview downloads without fetching (machine-readable)
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

1. `print_widget compare --name=<entry>` reads `print_widget.yaml` for `reference_dir` (default `.reference`), `compare_threshold` (default 0.95), `cross_engine_threshold` (default 0.88), and optional per-entry `thresholds:` map.
2. Threshold resolution priority per entry: CLI `--threshold` > `thresholds.<entry>` > `_origin.json` (`flutter` → compare_threshold, `browser`/missing → cross_engine_threshold).
3. Locates reference crops at `<outputDir>/<entry>/<reference_dir>/crops/*.png` (or top-level PNG fallback)
4. Pairs each reference crop with a matching generated crop at `<outputDir>/<entry>/crops/*.png`
5. Resolves `lib/src/tools/pixelmatch_batch.mjs` via `Isolate.resolvePackageUri` — works after `dart pub global activate` and in local dev
6. Spawns `node pixelmatch_batch.mjs`, pipes a JSON payload of pair paths via stdin
7. The Node helper uses pixelmatch v7 with `includeAA: false` (suppresses AA false positives on Flutter text), writes heatmap PNGs next to the generated crops as `<region>_diff.png`, returns per-pair similarity
8. Dart parses results, prints resolved threshold + source per entry, exits 0 if all regions ≥ threshold else 1

## Spec pipeline (extract → scaffold → tokenize → snapshot)

Closes the pixel-guessing gap by giving agents exact DOM values instead of forcing them to reverse-engineer from screenshots. Four new commands compose into a deterministic-when-possible pipeline. See `doc/pipeline-gaps/` for the full design + empirical baseline.

### extract

`print_widget extract --url=<URL>` owns Playwright end-to-end (installs Chromium under `.dart_tool/print_widget/extract-runtime/` on first run). Writes per-crop `_spec.json` alongside each PNG with per-element bounds, computed styles, typography, icon metadata, and full SVG markup. Also writes `_origin.json` with `{origin: "browser"}` so `compare` picks the right threshold downstream, and `_fonts.json` with `(family, weight)` pairs observed in the DOM so `fonts` can download them. Flags: `--config=<states.json>`, `--viewport=WxH`, `--output`, `--theme`, `--chrome-purge` (repeatable), `--force-font` (repeatable), `--runtime-dir`, `--skip-install`.

### snapshot

`print_widget snapshot --name=<entry>` promotes currently-generated PNGs into the reference position. Copies `<outputDir>/<entry>/<device>.png` + `crops/*.png` (excluding `_diff.png`) into `<outputDir>/<entry>/<referenceDir>/`, writes `_origin.json` with `{origin: "flutter"}`. Used once visual audit passes but pixelmatch is ceiling-capped on text glyphs — future compare runs are Flutter-to-Flutter at full threshold. Flags: `--name` / `--all`, `--device`, `--force`, `--json`.

### scaffold

`print_widget scaffold --spec=<path>` deterministically compiles a `_spec.json` into a Flutter widget with literal values — no tokens, no DS components, no AI. Pure JSON-tree-to-Dart mechanical translation. Output goes through every codegen rule in `doc/pipeline-gaps/scaffold.md` (flex → Row/Column, gap → SizedBox interleave, padding collapsing, circle vs borderRadius, typography with TextStyle, SvgPicture.string for SVGs, const propagation). Flags: `--spec`, `--class-name`, `--output`, `--stdout`, `--force`, `--json`.

### tokenize

`print_widget tokenize --input=<scaffold.dart> --theme=<theme-ref.json>` transforms scaffold literals into DS tokens via regex + brace-counting (AST upgrade path documented in tokenizer.dart). Substitutes `Color(0x...)` with `context.customColors.<token>`, `EdgeInsets.all(N)` with `EdgeInsets.all(YHAppSpacing.spN)`, `TextStyle(...)` with `interText(...)`, etc. Values that don't map get a `// FORCE:` comment flagging them for manual review. Flags: `--input`, `--theme`, `--output`, `--stdout`, `--strategy=exact|near`, `--tolerance=<deltaE>`, `--force`, `--json`.

### fonts

`print_widget fonts` closes the silent font-fallback trap. Reads every `_fonts.json` under the configured `output_dir` (or a path given via `--source`), merges the `(family, weight)` pairs, and downloads matching TTFs from the Google Fonts CSS2 endpoint (old User-Agent forces TTF instead of woff2, which Flutter's `FontLoader` rejects). Default destination `google_fonts/` is auto-detected by `loadPrintWidgetFonts` with no pubspec change. `--dest=assets/fonts` installs under assets and appends a `flutter.fonts` block to `pubspec.yaml` (skip with `--no-pubspec`). Flags: `--source`, `--dest=google_fonts|assets/fonts`, `--dry-run`, `--force`, `--json`, `--no-pubspec`. See `doc/fonts-setup.md` for the full contract + troubleshooting.

### Theme-ref.json shape

Tokenize consumes `.claude/skills/print-widget-extract/theme-ref.json` (shared with `extract` for aggregate token mapping). New keys for tokenize:
- `colors.tokenMap` — hex → token name
- `colors.accessor` — Dart expression to prepend (default `context.customColors`)
- `spacing.scale` — px → scale index
- `spacing.class` + `spacing.prefix` — emission class and prefix (e.g. `YHAppSpacing.sp`)
- `radius.scale` + `radius.class` + `radius.prefix`
- `typography.helper` — function name to emit (e.g. `interText`)
- `typography.import` — import path for the helper

Existing keys (`palette`, `semanticOverrides`, `spacingScale`, `typographyScale`, `fontWeightMap`) are unchanged — still used by `extract.mjs` for aggregate summary.

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
