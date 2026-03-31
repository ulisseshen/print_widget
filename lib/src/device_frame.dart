import 'package:flutter/material.dart';

/// A device specification that controls the viewport and output dimensions of
/// a screenshot.
///
/// The [size] defines the logical viewport in density-independent pixels, and
/// [pixelRatio] determines the final PNG resolution:
/// **output pixels = logical size x pixelRatio**. For example, a 393x852
/// device at 3x produces a 1179x2556 pixel image.
///
/// **Layout behavior by entry type:**
///
/// - **Pages** ([PrintType.page]): the widget fills the entire device frame as
///   the `home:` of the app wrapper. The device frame size IS the page size.
/// - **Widgets** ([PrintType.widget]): the widget is placed inside
///   `Scaffold > Center > SizedBox(entry.size)`. The device frame defines the
///   background viewport, and the optional `size` on [PrintEntry] constrains
///   the widget within it. The output screenshot is always the full device
///   frame size, not the widget size.
///
/// Use the built-in presets or create custom ones:
///
/// ```dart
/// const myDevice = DeviceFrame(
///   name: 'my_device',
///   size: Size(400, 800),
///   pixelRatio: 2.0,
/// );
/// ```
class DeviceFrame {
  /// Creates a device frame with the given [name], [size], and [pixelRatio].
  const DeviceFrame({
    required this.name,
    required this.size,
    this.pixelRatio = 1.0,
  });

  /// Identifier used in output file names (e.g. `iphone_15_pro`).
  final String name;

  /// Logical screen size in density-independent pixels.
  ///
  /// This is the viewport size used during rendering. The actual output PNG
  /// dimensions are `size * pixelRatio`.
  final Size size;

  /// Device pixel ratio (e.g. 3.0 for Retina displays).
  ///
  /// Multiplied by [size] to determine the output PNG resolution. A 393x852
  /// frame at 3.0x produces a 1179x2556 pixel image.
  final double pixelRatio;

  // -- Apple --

  /// iPhone SE (375x667 @2x).
  static const iPhoneSE = DeviceFrame(
    name: 'iphone_se',
    size: Size(375, 667),
    pixelRatio: 2.0,
  );

  /// iPhone 14 (390x844 @3x).
  static const iPhone14 = DeviceFrame(
    name: 'iphone_14',
    size: Size(390, 844),
    pixelRatio: 3.0,
  );

  /// iPhone 15 Pro (393x852 @3x).
  static const iPhone15Pro = DeviceFrame(
    name: 'iphone_15_pro',
    size: Size(393, 852),
    pixelRatio: 3.0,
  );

  /// iPhone 16 Pro Max (440x956 @3x).
  static const iPhone16ProMax = DeviceFrame(
    name: 'iphone_16_pro_max',
    size: Size(440, 956),
    pixelRatio: 3.0,
  );

  /// iPad Mini (744x1133 @2x).
  static const iPadMini = DeviceFrame(
    name: 'ipad_mini',
    size: Size(744, 1133),
    pixelRatio: 2.0,
  );

  /// iPad Air (820x1180 @2x).
  static const iPadAir = DeviceFrame(
    name: 'ipad_air',
    size: Size(820, 1180),
    pixelRatio: 2.0,
  );

  /// iPad Pro 11-inch (834x1194 @2x).
  static const iPadPro11 = DeviceFrame(
    name: 'ipad_pro_11',
    size: Size(834, 1194),
    pixelRatio: 2.0,
  );

  /// iPad Pro 13-inch (1024x1366 @2x).
  static const iPadPro13 = DeviceFrame(
    name: 'ipad_pro_13',
    size: Size(1024, 1366),
    pixelRatio: 2.0,
  );

  // -- Android --

  /// Google Pixel 7 (412x915 @2.625x).
  static const pixel7 = DeviceFrame(
    name: 'pixel_7',
    size: Size(412, 915),
    pixelRatio: 2.625,
  );

  /// Google Pixel 8 Pro (448x998 @3x).
  static const pixel8Pro = DeviceFrame(
    name: 'pixel_8_pro',
    size: Size(448, 998),
    pixelRatio: 3.0,
  );

  /// Samsung Galaxy S24 (360x780 @3x).
  static const samsungS24 = DeviceFrame(
    name: 'samsung_s24',
    size: Size(360, 780),
    pixelRatio: 3.0,
  );

  /// Samsung Galaxy S24 Ultra (412x915 @3x).
  static const samsungS24Ultra = DeviceFrame(
    name: 'samsung_s24_ultra',
    size: Size(412, 915),
    pixelRatio: 3.0,
  );

  // -- Web / Desktop --

  /// Web browser at 1366x768 (most common laptop resolution @1x).
  static const web1366 = DeviceFrame(
    name: 'web_1366',
    size: Size(1366, 768),
  );

  /// Web browser at 1440x900 (common desktop resolution @1x).
  static const web1440 = DeviceFrame(
    name: 'web_1440',
    size: Size(1440, 900),
  );

  /// Web browser at 1920x1080 (Full HD @1x).
  static const web1920 = DeviceFrame(
    name: 'web_1920',
    size: Size(1920, 1080),
  );

  /// Desktop at 2560x1440 (QHD / 1440p @2x).
  static const desktop1440p = DeviceFrame(
    name: 'desktop_1440p',
    size: Size(2560, 1440),
    pixelRatio: 2.0,
  );

  // -- Generic sizes --

  /// Generic small device (320x480 @1x).
  static const small = DeviceFrame(name: 'small', size: Size(320, 480));

  /// Generic medium device (400x800 @1x).
  static const medium = DeviceFrame(name: 'medium', size: Size(400, 800));

  /// Generic large device (600x1000 @1x).
  static const large = DeviceFrame(name: 'large', size: Size(600, 1000));

  /// Generic compact square device (300x300 @1x).
  static const compact = DeviceFrame(name: 'compact', size: Size(300, 300));

  // -- Preset groups --

  /// All phone-sized devices (8 devices).
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

  /// All tablet-sized devices (4 devices).
  static const List<DeviceFrame> allTablets = [
    iPadMini,
    iPadAir,
    iPadPro11,
    iPadPro13,
  ];

  /// Popular devices: iPhone 15 Pro, Pixel 7, iPad Pro 11.
  static const List<DeviceFrame> popular = [iPhone15Pro, pixel7, iPadPro11];

  /// All web/desktop-sized devices (4 devices).
  static const List<DeviceFrame> allWeb = [
    web1366,
    web1440,
    web1920,
    desktop1440p,
  ];

  /// All built-in device presets, sorted by name length (longest first).
  ///
  /// Useful for matching device suffixes in flat-mode filenames where
  /// device names contain underscores (e.g., `login_page_iphone_15_pro`).
  static final List<DeviceFrame> allPresets = _buildAllPresets();

  static List<DeviceFrame> _buildAllPresets() {
    const presets = <DeviceFrame>[
      iPhoneSE,
      iPhone14,
      iPhone15Pro,
      iPhone16ProMax,
      iPadMini,
      iPadAir,
      iPadPro11,
      iPadPro13,
      pixel7,
      pixel8Pro,
      samsungS24,
      samsungS24Ultra,
      web1366,
      web1440,
      web1920,
      desktop1440p,
      small,
      medium,
      large,
      compact,
    ];
    final sorted = List<DeviceFrame>.from(presets)
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    return sorted;
  }

  @override
  String toString() =>
      'DeviceFrame($name, ${size.width}x${size.height}, ${pixelRatio}x)';
}
