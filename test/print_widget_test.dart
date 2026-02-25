import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget_flutter/print_widget.dart';

void main() {
  group('printWidget', () {
    testWidgets('captures a simple container', (tester) async {
      await printWidget(
        tester,
        name: 'simple_container',
        widget: Container(
          width: 200,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text(
              'Hello, LLM!',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ),
      );
    });

    testWidgets('captures for a specific device', (tester) async {
      await printWidget(
        tester,
        name: 'button',
        device: DeviceFrame.iPhone15Pro,
        widget: ElevatedButton(onPressed: () {}, child: const Text('Press me')),
      );
    });
  });

  group('printWidgetOnDevices', () {
    testWidgets('captures on popular devices', (tester) async {
      await printWidgetOnDevices(
        tester,
        name: 'card',
        widget: const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 48, color: Colors.green),
                SizedBox(height: 16),
                Text('Success!', style: TextStyle(fontSize: 24)),
              ],
            ),
          ),
        ),
        devices: DeviceFrame.popular,
      );
    });
  });

  group('printWidgetThemed', () {
    testWidgets('captures light and dark on device', (tester) async {
      await printWidgetThemed(
        tester,
        name: 'profile',
        device: DeviceFrame.pixel7,
        widget: const Card(
          child: ListTile(
            leading: Icon(Icons.person),
            title: Text('John Doe'),
            subtitle: Text('john@example.com'),
          ),
        ),
        config: const PrintConfig(size: Size(400, 150)),
      );
    });
  });
}
