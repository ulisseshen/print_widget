import 'dart:async';

import 'package:print_widget/print_widget.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadPrintWidgetFonts();
  return testMain();
}
