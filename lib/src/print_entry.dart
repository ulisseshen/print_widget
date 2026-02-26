import 'package:flutter/widgets.dart';

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
  });

  /// Identifier used for the output directory name.
  final String name;

  /// The widget to render. Ignored when [states] is provided.
  final Widget widget;

  /// Whether this entry renders as a full-screen page or a centered widget.
  final PrintType type;

  /// Custom render size. If null, uses the device's size.
  final Size? size;

  /// Devices to render on. If null, uses the session's default device.
  final List<DeviceFrame>? devices;

  /// Multiple visual states to capture. When provided, each state is rendered
  /// as a separate screenshot.
  final List<PrintState>? states;
}

/// Creates a full-screen page entry.
///
/// The widget is passed directly as the `home:` parameter of the app wrapper.
///
/// ```dart
/// page('login_page', const LoginPage())
/// ```
PrintEntry page(String name, Widget widget, {List<DeviceFrame>? devices}) =>
    PrintEntry(
      name: name,
      widget: widget,
      type: PrintType.page,
      devices: devices,
    );

/// Creates a centered widget entry.
///
/// The widget is wrapped in a `Scaffold` with `Center` for proper layout.
/// Use [size] to constrain the render area.
///
/// ```dart
/// widget('product_card', ProductCard(title: 'Demo'), size: Size(350, 420))
/// ```
PrintEntry widget(
  String name,
  Widget widget, {
  Size? size,
  List<DeviceFrame>? devices,
}) => PrintEntry(
  name: name,
  widget: widget,
  type: PrintType.widget,
  size: size,
  devices: devices,
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
}) => PrintEntry(
  name: name,
  widget: const SizedBox.shrink(),
  type: PrintType.page,
  devices: devices,
  states: states,
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
}) => PrintEntry(
  name: name,
  widget: const SizedBox.shrink(),
  type: PrintType.widget,
  size: size,
  devices: devices,
  states: states,
);
