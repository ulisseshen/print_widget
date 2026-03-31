import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';

import 'package:print_widget_example/theme.dart';
import 'package:print_widget_example/pages/login_page.dart';
import 'package:print_widget_example/pages/home_page.dart';
import 'package:print_widget_example/widgets/product_card.dart';
import 'package:print_widget_example/widgets/stats_card.dart';
import 'package:print_widget_example/widgets/user_avatar.dart';
import 'package:print_widget_example/widgets/custom_font_card.dart';
import 'package:print_widget_example/widgets/missing_font_card.dart';

final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
  outputDir: 'test/prints/output',
);

final printList = <PrintEntry>[
  // Pages (full screen)
  page('login_page', const LoginPage()),
  page('home_page', const HomePage()),

  // Widgets (centered in scaffold)
  widget(
    'product_card',
    ProductCard(
      title: 'Flutter Widget Kit',
      description: 'A collection of beautiful widgets for your app.',
      price: 'R\$ 49,90',
      rating: 4.8,
      onTap: () {},
    ),
    size: const Size(350, 420),
  ),
  widget(
    'stats_card',
    const StatsCard(
      icon: Icons.shopping_bag,
      label: 'Orders',
      value: '128',
      color: Colors.blue,
    ),
    size: const Size(200, 180),
  ),
  widget(
    'user_avatar_online',
    const UserAvatar(
      name: 'Maria Silva',
      role: 'Flutter Developer',
      isOnline: true,
    ),
    size: const Size(300, 120),
  ),
  widget(
    'user_avatar_offline',
    const UserAvatar(
      name: 'João Santos',
      role: 'Backend Engineer',
      isOnline: false,
    ),
    size: const Size(300, 120),
  ),

  // Custom font widget (non-Google font declared in pubspec.yaml)
  widget(
    'custom_font_card',
    const CustomFontCard(
      title: 'Custom Font Test',
      subtitle: 'This text uses a custom font family.',
    ),
    size: const Size(350, 140),
  ),

  // Missing font widget (triggers font warning in CLI output)
  widget(
    'missing_font_card',
    const MissingFontCard(),
    size: const Size(400, 200),
  ),

  // Multi-device: product card on popular devices
  widget(
    'product_card_responsive',
    ProductCard(
      title: 'Responsive Test',
      description: 'Same widget on different screens.',
      price: 'R\$ 99,90',
      rating: 4.5,
      onTap: () {},
    ),
    devices: DeviceFrame.popular,
  ),

  // Grouped states: user avatar with different statuses
  widgets(
    'user_avatar_states',
    states: [
      state(
        'online',
        const UserAvatar(
          name: 'Maria Silva',
          role: 'Flutter Developer',
          isOnline: true,
        ),
      ),
      state(
        'offline',
        const UserAvatar(
          name: 'João Santos',
          role: 'Backend Engineer',
          isOnline: false,
        ),
      ),
    ],
    size: const Size(300, 120),
  ),
];
