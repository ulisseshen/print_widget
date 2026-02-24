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
