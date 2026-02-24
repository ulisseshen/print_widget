/// Capture Flutter widgets and pages as PNG screenshots for visual
/// verification.
///
/// This library provides two APIs:
///
/// **Session API** (recommended for CLI usage):
/// - [PrintSession] + [PrintEntry] for configuring captures
/// - [page], [widget], [pages], [widgets] helpers
/// - [state] for defining visual states
///
/// **Standalone test API** (for direct use in Flutter tests):
/// - [printWidget], [printWidgetOnDevices], [printWidgets]
/// - [printEntry], [printAllEntries]
/// - [printWidgetThemed] for light/dark variants
library;

export 'src/device_frame.dart';
export 'src/font_loader.dart';
export 'src/print_config.dart';
export 'src/print_widget_runner.dart';
export 'src/printable.dart';
export 'src/app_wrapper.dart';
export 'src/print_session.dart';
export 'src/print_entry.dart';
export 'src/print_manifest.dart';
export 'src/print_state.dart';
