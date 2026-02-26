import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';

import '../widgets/product_card.dart';
import '../widgets/stats_card.dart';

class HomePage extends StatelessWidget with Printable {
  const HomePage({super.key});

  @override
  String get printName => 'home_page';

  @override
  PrintType get printType => PrintType.page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () {},
          ),
          IconButton(icon: const Icon(Icons.person_outline), onPressed: () {}),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashboardHeader(),
            SizedBox(height: 16),
            _StatsRow(),
            SizedBox(height: 24),
            _ProductsSection(),
          ],
        ),
      ),
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Dashboard',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: StatsCard(
            icon: Icons.shopping_bag,
            label: 'Orders',
            value: '128',
            color: Colors.blue,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: StatsCard(
            icon: Icons.attach_money,
            label: 'Revenue',
            value: 'R\$ 12.4k',
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}

class _ProductsSection extends StatelessWidget {
  const _ProductsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Popular Products',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ProductCard(
          title: 'Flutter Widget Kit',
          description: 'A collection of beautiful widgets for your app.',
          price: 'R\$ 49,90',
          rating: 4.8,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        ProductCard(
          title: 'Dart Masterclass',
          description: 'Learn advanced Dart patterns and techniques.',
          price: 'R\$ 89,90',
          rating: 4.9,
          onTap: () {},
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        NavigationDestination(
          icon: Icon(Icons.favorite_outline),
          selectedIcon: Icon(Icons.favorite),
          label: 'Favorites',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
