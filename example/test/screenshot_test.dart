import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget/print_widget.dart';

/// Run this to generate widget screenshots:
///
///   cd example
///   flutter test --update-goldens
///
/// PNGs will be saved to: example/test/prints/
void main() {
  group('Widget catalog', () {
    testWidgets('login form', (tester) async {
      await printWidget(
        tester,
        name: 'login_form',
        widget: SizedBox(
          width: 350,
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Welcome back',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text('Sign In'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        config: const PrintConfig(size: Size(420, 550)),
      );
    });

    testWidgets('product card', (tester) async {
      await printWidget(
        tester,
        name: 'product_card',
        widget: SizedBox(
          width: 300,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 150,
                  color: Colors.blueGrey.shade100,
                  child: const Center(
                    child: Icon(Icons.image, size: 64, color: Colors.grey),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flutter Widget Kit',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'A collection of beautiful widgets',
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'R\$ 49,90',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        config: const PrintConfig(size: Size(350, 400)),
      );
    });

    testWidgets('user profile - light and dark', (tester) async {
      await printWidgetThemed(
        tester,
        name: 'user_profile',
        widget: const SizedBox(
          width: 350,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    child: Icon(Icons.person, size: 32),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maria Silva',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('Flutter Developer'),
                        SizedBox(height: 4),
                        Text(
                          'Online',
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        config: const PrintConfig(size: Size(400, 150)),
      );
    });
  });
}
