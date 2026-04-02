## 0.5.2

- **`update` skill**: `/print-widget-update` — updates CLI tool + all skill files in one command (Claude Code, Cursor, Codex)

## 0.5.1

- **`update` skill**: New `/print-widget-update` skill that updates both the CLI tool (`dart pub global activate`) and all installed skill files in one command
- **`skills --update`**: New flag to update all installed skills to the latest version after upgrading print_widget

## 0.5.0

### Skills overhaul (based on real-world Figma-to-Flutter feedback)

#### Figma skill (main template)
- **Color extraction workflow**: Extract ALL colors from Figma, create mapping table to DS tokens BEFORE writing code
- **DS token enforcement**: Never use hardcoded `Color()` — always map to project tokens, flag missing ones
- **Completeness check**: List ALL Figma sections, verify each exists in implementation before coding
- **Reference image mandatory**: Saving reference image is no longer optional
- **Padding extraction**: Systematic extraction of gap/padding values from design context
- **Exact character matching**: Copy exact chars from Figma (separators, symbols) — don't retype
- **Positive/negative coloring**: Red for negative values, green for positive (financial UI pattern)
- **SVG icon consistency**: Guide for matching stroke weights between MaterialIcons and SVGs
- **Large context warning**: Suggests fetching sub-nodes for 100K+ char Figma responses
- **Save novel patterns**: Persist new workarounds to CLAUDE.md for future sessions
- Updated Cursor and Codex templates with same core principles (shorter form)

#### Review checklist (review.md)
- Complete layer-by-layer verification: backgrounds (outside-in), text colors, padding, borders, icons, typography, layout
- 30+ individual checkpoints covering all visual aspects
- Rules: enumerate every element, track verified vs unchecked, never skip

#### Conventions (conventions.md)
- **IntrinsicHeight**: Cards in same Row need IntrinsicHeight + CrossAxisAlignment.stretch
- **No wrapper guessing**: Never add Container/Card unless it exists as a Figma node
- **Scoped fixes**: Each change scoped to specific component, verify siblings unaffected
- **Verify, don't guess**: Always check Figma context for actual values
- **Copy-paste node names**: Don't retype Figma node names
- **No removing functionality**: Find alternatives instead of removing features
- **Ask before uncertain changes**: Show user planned color changes when ambiguous
- **Generate after each change**: One change, one verify — don't batch visual changes

#### Screen patterns (screen.md)
- **Provider tracing**: How to grep for context.read/watch/ref.read to find dependencies
- **DS customization options**: (a) add parameter, (b) wrap, (c) fork — with recommendations
- **Toggle state pattern**: pages() with state() + setup callback for expanded/collapsed

#### Iterate loop (iterate.md)
- Systematic checklist-driven loop (not ad-hoc)
- Section-by-section verification against Figma reference
- List ALL differences before fixing, batch fixes, regenerate once
- Autonomous — no user interaction between iterations

### CLI improvements
- **`skills --update`**: Update all installed skills to latest version after upgrading print_widget
- **Auto-create google_fonts/ dir**: Created automatically when pubspec declares it as asset
- **Network image error hints**: Summarized guidance instead of raw stacktraces
- **AnimatedDefaultTextStyle warning**: Hint suggesting TweenAnimationBuilder alternative
- **Web project detection on init**: Auto-detects web projects and uses `web_1440` as default device
- **Fix-all-squares workflow**: Guidance to fix ALL font issues at once instead of one-by-one

## 0.4.0

### Font loading
- **Package font prefix**: Fonts from packages now registered with `packages/<name>/<family>` prefix — fixes icons from `material_symbols_icons`, `cupertino_icons`, and any package using `fontPackage`
- **Relative path support**: `loadCustomFonts()` now resolves paths relative to project root
- **Bundled MaterialIcons prefix**: Also registered as `packages/print_widget_flutter/MaterialIcons`

### PrintSession
- **`setup` callback**: New parameter for global initialization before rendering (Firebase, AppFlavor, etc.)
- **Timer pending fix**: Exit code 0 when only error is "Timer is still pending" and screenshots were generated successfully

### Skills
- **Mock patterns**: Skills now teach progressive mock (noSuchMethod → overrides), async-safe mock for Future methods, and full page shell with GoRouter + MultiProvider + Scaffold
- **GoRouter guidance**: Skills document `MaterialApp.router` requirement for navigation-using widgets

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
