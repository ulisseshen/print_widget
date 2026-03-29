// ignore_for_file: depend_on_referenced_packages

/// Example showing how to set up print_widget in a Flutter project.
///
/// ## 1. Define a session and entries
///
/// Create `test/prints/print_config.dart`:
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:print_widget_flutter/print_widget.dart';
///
/// final printSession = PrintSession(
///   appWrapper: (child) => MaterialApp(
///     theme: ThemeData(colorSchemeSeed: Colors.indigo),
///     home: child,
///   ),
///   defaultDevice: DeviceFrame.iPhone15Pro,
/// );
///
/// final printList = <PrintEntry>[
///   // Full-screen pages
///   page('login_page', const Scaffold(body: Center(child: Text('Login')))),
///
///   // Centered widgets with custom size
///   widget(
///     'my_button',
///     ElevatedButton(onPressed: () {}, child: const Text('Click me')),
///     size: const Size(200, 60),
///   ),
///
///   // Multiple visual states
///   pages('greeting', states: [
///     state('english', const Scaffold(body: Center(child: Text('Hello')))),
///     state('spanish', const Scaffold(body: Center(child: Text('Hola')))),
///   ]),
/// ];
/// ```
///
/// ## 2. Generate screenshots
///
/// ```bash
/// print_widget generate
/// ```
///
/// ## 3. Use the standalone test API
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:flutter_test/flutter_test.dart';
/// import 'package:print_widget_flutter/print_widget.dart';
///
/// void main() {
///   testWidgets('capture a widget', (tester) async {
///     await printWidget(
///       tester,
///       name: 'my_button',
///       widget: ElevatedButton(
///         onPressed: () {},
///         child: const Text('Click'),
///       ),
///       device: DeviceFrame.iPhone15Pro,
///     );
///   });
/// }
/// ```
library;
