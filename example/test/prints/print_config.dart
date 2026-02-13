import 'package:flutter/material.dart';
import 'package:print_widget/print_widget.dart';

import '../../lib/theme.dart';
import '../../lib/pages/login_page.dart';
import '../../lib/pages/home_page.dart';
import '../../lib/widgets/product_card.dart';
import '../../lib/widgets/stats_card.dart';
import '../../lib/widgets/user_avatar.dart';

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
    size: const Size(300, 100),
  ),
  widget(
    'user_avatar_offline',
    const UserAvatar(
      name: 'João Santos',
      role: 'Backend Engineer',
      isOnline: false,
    ),
    size: const Size(300, 100),
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
];
