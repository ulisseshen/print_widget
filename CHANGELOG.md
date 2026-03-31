## 0.3.2

### Skills
- **Autonomous visual validation loop**: Skills now instruct the AI to read screenshots, compare with designs, and iterate autonomously (max 5 rounds) — no user confirmation needed
- Updated all 6 skill templates (figma + stitch × Claude/Cursor/Codex)

### Docs
- README and `--llm-guide` updated for all v0.3.1 features (font loading, skills, diagnose, --json)

## 0.3.1

### Font loading (major overhaul)
- **google_fonts support**: Auto-detect `google_fonts` dependency and register variant-qualified names (`Roboto_regular`, `Roboto_bold`, etc.) — fixes Ahem black rectangles for all google_fonts projects
- **Package font auto-detection**: Scans all dependency packages for font declarations — design system packages that bundle fonts work automatically
- **google_fonts/ directory scan**: Auto-loads fonts from `google_fonts/` directory at project root
- **Fallback directory scan**: Scans `assets/fonts/`, `assets/font/`, `fonts/` for undeclared fonts
- **`loadFonts` callback**: New parameter on `PrintSession` — escape hatch for fonts auto-detection can't find
- **Font loading summary**: CLI output shows all loaded font registrations and warns when fonts are missing
- **flutter_test_config.dart shadowing fix**: Deletes stale config from `.dart_tool/print_widget/` before generation

### Skills
- **Stitch skill**: New `print-widget-stitch` skill for Google AI UI (Stitch MCP) workflow
- **Auto-install on init**: `print_widget init` automatically installs all skills (figma + stitch)
- **Simplified install flag**: `--install` installs all skills, `--only=figma` for specific ones
- **Git root resolution**: Skills install to git root for monorepo support
- **Re-run feedback**: `[ok] ✓` instead of ambiguous `[skip]` on re-install
- **Scope documentation**: Clear explanation in `--list` and interactive prompt

## 0.3.0

### New features
- **Web/desktop device presets**: `DeviceFrame.web1366`, `web1440`, `web1920`, `desktop1440p` + `DeviceFrame.allWeb` group
- **Custom device sizes via CLI**: `--device=1440x900`, `--device=name:WxH@ratio`
- **Setup callback**: `setup:` parameter on `page()`/`widget()`/`pages()`/`widgets()` and `state()` — interact with widgets (tap tabs, scroll, enter text) before capture
- **Per-entry app wrapper**: `appWrapper:` override on entries for different providers per widget
- **Scroll capture**: `scrollExtent:` for tall page capture, `scrollTo:` for scroll offset before capture
- **JSON output**: `print_widget generate --json` for structured programmatic output
- **Diagnose command**: `print_widget diagnose` — static analysis of widget constructors, required params, provider dependencies, mock data suggestions
- **Overflow error hints**: Actionable suggestions when widgets overflow (suggests larger devices, `size:` changes, `--name` for fast iteration)
- **Pre-validation**: Warns before golden tests if widget `size` exceeds device frame dimensions

### Improved
- **Font loading**: rootBundle fallback when filesystem resolution fails (pub cache, hosted deps), robust symlink handling
- **Dartdoc**: Comprehensive documentation on `size` vs `DeviceFrame` relationship, `pixelRatio` effect on output resolution, layout behavior per entry type
- **README**: Entry types reference table, advanced features section (setup, scroll, providers), custom device docs, font loading guide
- **LLM guide**: Entry types table, all new features documented, advanced examples

## 0.2.1

### Documentation
- Add MCP integrations section to README (Figma MCP + Stitch by Google)
- Link to official Figma MCP server guide and Stitch MCP setup docs

## 0.2.0

### VS Code Extension
- Sidebar tree view for browsing screenshots by feature, state, and device
- Single image preview with click-to-toggle zoom
- Multi-device comparison grid
- Before/after diff with draggable slider and git-based auto-diff
- Design reference comparison with pixelmatch (similarity %, adjustable threshold)
- Auto-detect `.reference/` images saved by AI skills
- Source linker (Go to Definition with Alt+F12)
- Auto-refresh with debouncing, welcome view, Open in Finder, Copy Path

### CLI
- `print_widget skills` — install AI assistant skills (Claude Code, Cursor, Codex)
- Post-init AI onboarding guidance (skill install, VS Code detection)
- `--llm-guide` now includes VS Code extension install instructions
- Fix flat mode manifest parsing for multi-underscore device names
- `DeviceFrame.allPresets` for programmatic device access

### Package
- Fix CLI binary to run with plain `dart` (decoupled from Flutter imports)
- `lib/print_widget_flutter.dart` barrel re-export matching package name
- SDK constraint lowered to `^3.0.0` for wider adoption
- `example/example.dart` for pub.dev conventions
- Platform support declared (Android, iOS, Linux, macOS, Windows)
- Screenshots, funding, homepage in pubspec.yaml
- pub.dev pana score: 160/160

### Testing
- CLI integration tests (init, generate, list, config, --llm-guide)
- Guard test preventing Flutter imports in CLI code
- Device name sync test (CLI list vs DeviceFrame.allPresets)
- TypeScript tests for manifest parser (vitest)

### Documentation
- Big-picture ecosystem overview (`doc/big-picture.md`)
- AI Assistant Onboarding section in README
- Cross-platform VS Code install instructions

## 0.1.0

Initial release.

### CLI

- `print_widget init` — set up a Flutter project for screenshot capture.
- `print_widget generate` — generate PNG screenshots from configured entries.
- `print_widget list` — show configured entries.
- `print_widget config` — read/write project settings.
- `--name`, `--device`, `--all-devices`, `--delete-old` flags.
- `--llm-guide` — print compact LLM reference with project-specific paths.

### API

- `PrintSession` — configure app wrapper, default device, output mode.
- `PrintEntry` with `page()`, `widget()`, `pages()`, `widgets()` helpers.
- `state()` for grouped visual states.
- `StateOutputMode` (prefix, suffix, folder).
- `DeviceFrame` presets for 12 iOS/Android devices + preset groups.
- `Printable` mixin for self-describing widgets.
- `loadPrintWidgetFonts()` — automatic font loading from project and packages.
- JSON manifest generation for LLM consumption.
- Standalone test API (`printWidget`, `printEntry`, `printAllEntries`).
- `appWrapperFromMaterialApp` helper.
