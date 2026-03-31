import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';
import 'package:print_widget_example/theme.dart';

final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
  // How state names appear in output files:
  // StateOutputMode.prefix  → empty_iphone_15_pro.png  (default)
  // StateOutputMode.suffix  → iphone_15_pro_empty.png
  // StateOutputMode.folder  → empty/iphone_15_pro.png
  // stateOutputMode: StateOutputMode.prefix,
);

final printList = <PrintEntry>[
  // Single-state entries:
  // page('login_page', const LoginPage()),
  // widget('product_card', ProductCard(product: mockProduct)),
  //
  // Grouped states (multiple visual states of the same page):
  // pages('sign_in_screen', states: [
  //   state('empty', SignInScreen()),
  //   state('error', SignInScreen(initialError: 'Invalid email')),
  //   state('filled', SignInScreen(initialEmail: 'user@test.com')),
  // ]),
];
