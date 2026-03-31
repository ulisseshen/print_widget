import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_wrapper.dart';
import 'device_frame.dart';
import 'print_state.dart';
import 'printable.dart';

/// A single screenshot entry defining what to capture.
///
/// Each entry has a [name] (used for the output directory), a [widget] to
/// render, and a [type] that determines layout (full-screen page vs centered
/// widget).
///
/// Use the convenience functions [page], [widget], [pages], and [widgets]
/// instead of constructing this directly.
class PrintEntry {
  /// Creates a print entry with the given parameters.
  const PrintEntry({
    required this.name,
    required this.widget,
    required this.type,
    this.size,
    this.devices,
    this.states,
    this.setup,
    this.scrollExtent,
    this.scrollTo,
    this.appWrapper,
  });

  /// Identifier used for the output directory name.
  final String name;

  /// The widget to render. Ignored when [states] is provided.
  final Widget widget;

  /// Whether this entry renders as a full-screen page or a centered widget.
  final PrintType type;

  /// Optional size constraints for the widget inside the device frame.
  ///
  /// When set, the widget is wrapped in a `SizedBox` of this size and centered
  /// within a `Scaffold`. The screenshot output is always the full device frame
  /// dimensions — this parameter only constrains the widget itself.
  ///
  /// When null, the widget fills the entire device frame (for pages) or is
  /// unconstrained inside the centered `Scaffold` (for widgets).
  ///
  /// Example: with a [DeviceFrame] of 1440x900 and a [size] of 1100x280,
  /// the widget is constrained to 1100x280 logical pixels and centered in the
  /// 1440x900 viewport. The output PNG is 1440x900 (times [DeviceFrame.pixelRatio]).
  final Size? size;

  /// Devices to render on. If null, uses the session's default device.
  final List<DeviceFrame>? devices;

  /// Multiple visual states to capture. When provided, each state is rendered
  /// as a separate screenshot.
  final List<PrintState>? states;

  /// Callback that runs after the widget is pumped but before the screenshot
  /// is captured. Use this to interact with the widget — tap buttons, switch
  /// tabs, scroll to a position, enter text, etc.
  ///
  /// The callback receives a [WidgetTester] and should call
  /// `tester.pumpAndSettle()` after any interactions.
  ///
  /// ```dart
  /// page('orders_tab', OrdersScreen(),
  ///   setup: (tester) async {
  ///     await tester.tap(find.text('Orders'));
  ///     await tester.pumpAndSettle();
  ///   },
  /// )
  /// ```
  final Future<void> Function(WidgetTester tester)? setup;

  /// Height to use for capturing scrollable content.
  ///
  /// When set, overrides the device frame height for this entry, allowing
  /// capture of content that extends beyond a single viewport. The width
  /// still comes from the device frame.
  ///
  /// For example, to capture a page that scrolls to 3000px:
  /// ```dart
  /// page('long_page', LongPage(), scrollExtent: 3000)
  /// ```
  ///
  /// The output PNG will be [DeviceFrame.size.width] x [scrollExtent].
  final double? scrollExtent;

  /// Vertical scroll offset applied before capturing.
  ///
  /// Scrolls the first [Scrollable] found in the widget tree to this offset
  /// before taking the screenshot. Useful for capturing specific sections of
  /// a long page:
  ///
  /// ```dart
  /// page('page_bottom', LongPage(), scrollTo: 1500)
  /// ```
  final double? scrollTo;

  /// Optional per-entry app wrapper that overrides the session-level wrapper.
  ///
  /// Use this to provide different providers or theme for specific entries:
  ///
  /// ```dart
  /// page('admin_dashboard', AdminDashboard(),
  ///   appWrapper: (child) => MultiProvider(
  ///     providers: [
  ///       ChangeNotifierProvider.value(value: mockAdminProvider),
  ///     ],
  ///     child: MaterialApp(home: child),
  ///   ),
  /// )
  /// ```
  ///
  /// When null, the session's [PrintSession.appWrapper] is used.
  final AppWrapper? appWrapper;
}

/// Creates a full-screen page entry.
///
/// The widget is passed directly as the `home:` parameter of the app wrapper.
///
/// ```dart
/// page('login_page', const LoginPage())
/// ```
PrintEntry page(
  String name,
  Widget widget, {
  List<DeviceFrame>? devices,
  Future<void> Function(WidgetTester tester)? setup,
  double? scrollExtent,
  double? scrollTo,
  AppWrapper? appWrapper,
}) =>
    PrintEntry(
      name: name,
      widget: widget,
      type: PrintType.page,
      devices: devices,
      setup: setup,
      scrollExtent: scrollExtent,
      scrollTo: scrollTo,
      appWrapper: appWrapper,
    );

/// Creates a centered widget entry.
///
/// The widget is wrapped in `Scaffold > Center > SizedBox(size)` for layout.
/// The screenshot always covers the full device frame; [size] only constrains
/// the widget within that viewport.
///
/// If [size] is null, the widget is placed inside `Center` without explicit
/// size constraints, so it will use its intrinsic size or expand to fill the
/// available space depending on its own layout behavior.
///
/// Example: a `DeviceFrame` of 1440x900 with `size: Size(1100, 280)` produces
/// a 1440x900 screenshot (times pixel ratio) with the widget constrained to
/// 1100x280 and centered in the frame.
///
/// ```dart
/// widget('product_card', ProductCard(title: 'Demo'), size: Size(350, 420))
/// ```
PrintEntry widget(
  String name,
  Widget widget, {
  Size? size,
  List<DeviceFrame>? devices,
  Future<void> Function(WidgetTester tester)? setup,
  double? scrollExtent,
  double? scrollTo,
  AppWrapper? appWrapper,
}) =>
    PrintEntry(
      name: name,
      widget: widget,
      type: PrintType.widget,
      size: size,
      devices: devices,
      setup: setup,
      scrollExtent: scrollExtent,
      scrollTo: scrollTo,
      appWrapper: appWrapper,
    );

/// Creates a grouped page entry with multiple visual states.
///
/// Each [PrintState] in [states] is rendered as a separate full-screen
/// screenshot.
///
/// ```dart
/// pages('sign_in', states: [
///   state('empty', SignInScreen()),
///   state('error', SignInScreen(initialError: 'Invalid')),
/// ])
/// ```
PrintEntry pages(
  String name, {
  required List<PrintState> states,
  List<DeviceFrame>? devices,
  Future<void> Function(WidgetTester tester)? setup,
  double? scrollExtent,
  double? scrollTo,
  AppWrapper? appWrapper,
}) =>
    PrintEntry(
      name: name,
      widget: const SizedBox.shrink(),
      type: PrintType.page,
      devices: devices,
      states: states,
      setup: setup,
      scrollExtent: scrollExtent,
      scrollTo: scrollTo,
      appWrapper: appWrapper,
    );

/// Creates a grouped widget entry with multiple visual states.
///
/// Each [PrintState] in [states] is rendered as a separate centered
/// screenshot.
///
/// ```dart
/// widgets('status_badge', states: [
///   state('active', StatusBadge(status: Status.active)),
///   state('inactive', StatusBadge(status: Status.inactive)),
/// ], size: Size(120, 40))
/// ```
PrintEntry widgets(
  String name, {
  required List<PrintState> states,
  Size? size,
  List<DeviceFrame>? devices,
  Future<void> Function(WidgetTester tester)? setup,
  AppWrapper? appWrapper,
}) =>
    PrintEntry(
      name: name,
      widget: const SizedBox.shrink(),
      type: PrintType.widget,
      size: size,
      devices: devices,
      states: states,
      setup: setup,
      appWrapper: appWrapper,
    );
