import 'package:flutter/material.dart';

class DeviceFrame {
  const DeviceFrame({
    required this.name,
    required this.size,
    this.pixelRatio = 1.0,
  });

  final String name;
  final Size size;
  final double pixelRatio;

  // -- Apple --

  static const iPhoneSE = DeviceFrame(
    name: 'iphone_se',
    size: Size(375, 667),
    pixelRatio: 2.0,
  );

  static const iPhone14 = DeviceFrame(
    name: 'iphone_14',
    size: Size(390, 844),
    pixelRatio: 3.0,
  );

  static const iPhone15Pro = DeviceFrame(
    name: 'iphone_15_pro',
    size: Size(393, 852),
    pixelRatio: 3.0,
  );

  static const iPhone16ProMax = DeviceFrame(
    name: 'iphone_16_pro_max',
    size: Size(440, 956),
    pixelRatio: 3.0,
  );

  static const iPadMini = DeviceFrame(
    name: 'ipad_mini',
    size: Size(744, 1133),
    pixelRatio: 2.0,
  );

  static const iPadAir = DeviceFrame(
    name: 'ipad_air',
    size: Size(820, 1180),
    pixelRatio: 2.0,
  );

  static const iPadPro11 = DeviceFrame(
    name: 'ipad_pro_11',
    size: Size(834, 1194),
    pixelRatio: 2.0,
  );

  static const iPadPro13 = DeviceFrame(
    name: 'ipad_pro_13',
    size: Size(1024, 1366),
    pixelRatio: 2.0,
  );

  // -- Android --

  static const pixel7 = DeviceFrame(
    name: 'pixel_7',
    size: Size(412, 915),
    pixelRatio: 2.625,
  );

  static const pixel8Pro = DeviceFrame(
    name: 'pixel_8_pro',
    size: Size(448, 998),
    pixelRatio: 3.0,
  );

  static const samsungS24 = DeviceFrame(
    name: 'samsung_s24',
    size: Size(360, 780),
    pixelRatio: 3.0,
  );

  static const samsungS24Ultra = DeviceFrame(
    name: 'samsung_s24_ultra',
    size: Size(412, 915),
    pixelRatio: 3.0,
  );

  // -- Generic sizes --

  static const small = DeviceFrame(
    name: 'small',
    size: Size(320, 480),
  );

  static const medium = DeviceFrame(
    name: 'medium',
    size: Size(400, 800),
  );

  static const large = DeviceFrame(
    name: 'large',
    size: Size(600, 1000),
  );

  static const compact = DeviceFrame(
    name: 'compact',
    size: Size(300, 300),
  );

  // -- Preset groups --

  static const List<DeviceFrame> allPhones = [
    iPhoneSE,
    iPhone14,
    iPhone15Pro,
    iPhone16ProMax,
    pixel7,
    pixel8Pro,
    samsungS24,
    samsungS24Ultra,
  ];

  static const List<DeviceFrame> allTablets = [
    iPadMini,
    iPadAir,
    iPadPro11,
    iPadPro13,
  ];

  static const List<DeviceFrame> popular = [
    iPhone15Pro,
    pixel7,
    iPadPro11,
  ];

  @override
  String toString() => 'DeviceFrame($name, ${size.width}x${size.height}, ${pixelRatio}x)';
}
