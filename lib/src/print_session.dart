import 'app_wrapper.dart';
import 'device_frame.dart';
import 'print_state.dart';

/// Configuration for a screenshot capture session.
///
/// Defines the app wrapper (theme, locale, etc.), default device, output
/// directory, and how state names appear in file paths.
///
/// ```dart
/// final printSession = PrintSession(
///   appWrapper: (child) => MaterialApp(
///     theme: MyTheme.light,
///     home: child,
///   ),
///   defaultDevice: DeviceFrame.iPhone15Pro,
/// );
/// ```
class PrintSession {
  /// Creates a session with the given configuration.
  PrintSession({
    required this.appWrapper,
    this.defaultDevice,
    this.outputDir = 'print_widget/output',
    this.generateManifest = true,
    this.stateOutputMode = StateOutputMode.prefix,
    this.flat = false,
  });

  /// Wraps each widget in a top-level app (typically a [MaterialApp]).
  final AppWrapper appWrapper;

  /// Fallback device used when a [PrintEntry] does not specify its own
  /// [PrintEntry.devices] list.
  ///
  /// When null, the runner defaults to [DeviceFrame.iPhone15Pro]. Individual
  /// entries can override this by providing their own `devices` parameter in
  /// [page], [widget], [pages], or [widgets].
  final DeviceFrame? defaultDevice;

  /// Output directory relative to the test file.
  final String outputDir;

  /// Whether to generate a `manifest.json` alongside the screenshots.
  final bool generateManifest;

  /// Controls how state names appear in output paths.
  final StateOutputMode stateOutputMode;

  /// When true, all PNGs are saved in the output directory root with
  /// `<name>_<device>.png` naming instead of `<name>/<device>.png` subfolders.
  final bool flat;
}
