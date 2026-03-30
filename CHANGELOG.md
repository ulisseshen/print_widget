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
