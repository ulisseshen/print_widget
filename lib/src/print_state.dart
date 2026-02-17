import 'package:flutter/widgets.dart';

/// How state names are placed in the output file path.
///
/// Given entry `sign_in_screen`, state `empty`, device `iphone_15_pro`:
///
/// - [prefix]: `sign_in_screen/empty_iphone_15_pro.png`
/// - [suffix]: `sign_in_screen/iphone_15_pro_empty.png`
/// - [folder]: `sign_in_screen/empty/iphone_15_pro.png`
enum StateOutputMode { prefix, suffix, folder }

class PrintState {
  const PrintState({
    required this.name,
    required this.widget,
  });

  final String name;
  final Widget widget;
}

PrintState state(String name, Widget widget) =>
    PrintState(name: name, widget: widget);
