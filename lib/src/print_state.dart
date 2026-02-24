import 'package:flutter/widgets.dart';

/// How state names are placed in the output file path.
///
/// Given entry `sign_in_screen`, state `empty`, device `iphone_15_pro`:
///
/// - [prefix]: `sign_in_screen/empty_iphone_15_pro.png`
/// - [suffix]: `sign_in_screen/iphone_15_pro_empty.png`
/// - [folder]: `sign_in_screen/empty/iphone_15_pro.png`
enum StateOutputMode {
  /// State name before the device name: `<state>_<device>.png`.
  prefix,

  /// State name after the device name: `<device>_<state>.png`.
  suffix,

  /// State name as a subdirectory: `<state>/<device>.png`.
  folder,
}

/// A named visual state of a widget or page.
///
/// Used with [pages] and [widgets] to capture multiple variants of the same
/// screen or component.
class PrintState {
  /// Creates a print state with the given [name] and [widget].
  const PrintState({
    required this.name,
    required this.widget,
  });

  /// Identifier used in the output file name.
  final String name;

  /// The widget to render for this state.
  final Widget widget;
}

/// Creates a [PrintState] with the given [name] and [widget].
///
/// ```dart
/// state('empty', SignInScreen())
/// ```
PrintState state(String name, Widget widget) =>
    PrintState(name: name, widget: widget);
