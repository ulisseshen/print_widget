import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget_flutter/src/cli/commands/generate_command.dart';

void main() {
  group('matchDeviceSuffix', () {
    test('splits login_page_iphone_15_pro correctly', () {
      final result = matchDeviceSuffix('login_page_iphone_15_pro');
      expect(result, isNotNull);
      expect(result!.$1, equals('login_page'));
      expect(result.$2, equals('iphone_15_pro'));
    });

    test('splits card_pixel_7 correctly', () {
      final result = matchDeviceSuffix('card_pixel_7');
      expect(result, isNotNull);
      expect(result!.$1, equals('card'));
      expect(result.$2, equals('pixel_7'));
    });

    test('splits my_widget_samsung_s24_ultra correctly', () {
      final result = matchDeviceSuffix('my_widget_samsung_s24_ultra');
      expect(result, isNotNull);
      expect(result!.$1, equals('my_widget'));
      expect(result.$2, equals('samsung_s24_ultra'));
    });

    test('falls back to last underscore for unknown device', () {
      final result = matchDeviceSuffix('no_device_match');
      expect(result, isNotNull);
      // Falls back to splitting at last underscore
      expect(result!.$1, equals('no_device'));
      expect(result.$2, equals('match'));
    });

    test('returns null for single word without underscore', () {
      final result = matchDeviceSuffix('button');
      expect(result, isNull);
    });
  });
}
