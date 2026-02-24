## 0.1.0

- Initial release.
- CLI commands: `init`, `generate`, `list`, `config`.
- `PrintSession` and `PrintEntry` API for configuring widget captures.
- `page()` / `widget()` helpers for single entries.
- `pages()` / `widgets()` with `state()` for grouped visual states.
- `StateOutputMode` (prefix, suffix, folder) for controlling output paths.
- `DeviceFrame` presets for popular iOS and Android devices.
- `Printable` mixin for self-describing widgets.
- Automatic font loading from project and package dependencies.
- JSON manifest generation for LLM consumption.
- Standalone test API (`printWidget`, `printEntry`, `printAllEntries`).
- `appWrapperFromMaterialApp` helper for quick setup.
