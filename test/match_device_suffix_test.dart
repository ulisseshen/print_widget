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

  group('parseCustomDevice', () {
    test('parses WxH format', () {
      final result = parseCustomDevice('1440x900');
      expect(result, isNotNull);
      expect(result!.name, equals('custom'));
      expect(result.width, equals(1440));
      expect(result.height, equals(900));
      expect(result.pixelRatio, equals(1.0));
    });

    test('parses name:WxH format', () {
      final result = parseCustomDevice('my_web:1440x900');
      expect(result, isNotNull);
      expect(result!.name, equals('my_web'));
      expect(result.width, equals(1440));
      expect(result.height, equals(900));
      expect(result.pixelRatio, equals(1.0));
    });

    test('parses name:WxH@ratio format', () {
      final result = parseCustomDevice('retina:1920x1080@2');
      expect(result, isNotNull);
      expect(result!.name, equals('retina'));
      expect(result.width, equals(1920));
      expect(result.height, equals(1080));
      expect(result.pixelRatio, equals(2.0));
    });

    test('returns null for preset names', () {
      expect(parseCustomDevice('iphone_15_pro'), isNull);
      expect(parseCustomDevice('pixel_7'), isNull);
    });
  });
}
