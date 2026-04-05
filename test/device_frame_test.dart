import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget_flutter/print_widget.dart';
import 'package:print_widget_flutter/src/cli/commands/generate_command.dart'
    show knownDeviceNames;

void main() {
  group('DeviceFrame.allPresets', () {
    test('contains all known device presets', () {
      const expectedDevices = <DeviceFrame>[
        DeviceFrame.iPhoneSE,
        DeviceFrame.iPhone14,
        DeviceFrame.iPhone15Pro,
        DeviceFrame.iPhone16ProMax,
        DeviceFrame.iPadMini,
        DeviceFrame.iPadAir,
        DeviceFrame.iPadPro11,
        DeviceFrame.iPadPro13,
        DeviceFrame.pixel7,
        DeviceFrame.pixel8Pro,
        DeviceFrame.samsungS24,
        DeviceFrame.samsungS24Ultra,
        DeviceFrame.web1366,
        DeviceFrame.web1440,
        DeviceFrame.web1920,
        DeviceFrame.desktop1440p,
        DeviceFrame.small,
        DeviceFrame.medium,
        DeviceFrame.large,
        DeviceFrame.compact,
      ];

      final presetNames = DeviceFrame.allPresets.map((d) => d.name).toSet();
      for (final device in expectedDevices) {
        expect(
          presetNames,
          contains(device.name),
          reason: '${device.name} should be in allPresets',
        );
      }

      expect(DeviceFrame.allPresets.length, equals(expectedDevices.length));
    });

    test('CLI knownDeviceNames matches allPresets', () {
      final presetNames = DeviceFrame.allPresets.map((d) => d.name).toSet();
      final cliNames = knownDeviceNames.toSet();

      expect(cliNames, equals(presetNames),
          reason: 'CLI _knownDevices list must match DeviceFrame.allPresets. '
              'If you add a new device, update both.');
    });

    test('is sorted by name length descending (longest first)', () {
      for (var i = 1; i < DeviceFrame.allPresets.length; i++) {
        final prev = DeviceFrame.allPresets[i - 1].name.length;
        final curr = DeviceFrame.allPresets[i].name.length;
        expect(
          prev >= curr,
          isTrue,
          reason:
              'allPresets[${i - 1}] (${DeviceFrame.allPresets[i - 1].name}, '
              'len=$prev) should be >= allPresets[$i] '
              '(${DeviceFrame.allPresets[i].name}, len=$curr)',
        );
      }
    });
  });
}
