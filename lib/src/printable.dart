import 'package:flutter/widgets.dart';

/// The rendering mode for a printable widget.
enum PrintType {
  /// Renders as a full-screen page (passed directly as `home:`).
  page,

  /// Renders centered inside a Scaffold.
  widget,
}

/// A mixin that allows a widget to describe its own screenshot metadata.
///
/// Widgets that mix in [Printable] can be automatically discovered and
/// rendered without manual [PrintEntry] configuration.
///
/// ```dart
/// class LoginPage extends StatelessWidget with Printable {
///   const LoginPage({super.key});
///
///   @override
///   String get printName => 'login_page';
///
///   @override
///   PrintType get printType => PrintType.page;
///
///   @override
///   Widget build(BuildContext context) => ...;
/// }
/// ```
mixin Printable on Widget {
  /// The output directory name for this widget's screenshots.
  String get printName;

  /// Whether this widget renders as a full-screen page or a centered widget.
  PrintType get printType;
}
