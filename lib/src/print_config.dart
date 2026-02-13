import 'package:flutter/material.dart';

class PrintConfig {
  const PrintConfig({
    this.size = const Size(400, 800),
    this.pixelRatio = 1.0,
    this.theme,
    this.darkTheme,
    this.outputDir = 'prints',
    this.background,
    this.padding = EdgeInsets.zero,
    this.locale,
    this.textDirection = TextDirection.ltr,
    this.wrapInScaffold = false,
  });

  /// Size of the render surface in logical pixels.
  final Size size;

  /// Device pixel ratio. Higher = more resolution.
  final double pixelRatio;

  /// Light theme. If null, uses default MaterialApp theme.
  final ThemeData? theme;

  /// Dark theme. If provided, a second screenshot is generated.
  final ThemeData? darkTheme;

  /// Output directory relative to the test file (used in golden path).
  final String outputDir;

  /// Background color behind the widget. If null, no background is applied.
  final Color? background;

  /// Padding around the widget.
  final EdgeInsets padding;

  /// Locale for the widget.
  final Locale? locale;

  /// Text direction.
  final TextDirection textDirection;

  /// Whether to wrap the widget in a Scaffold.
  final bool wrapInScaffold;

  PrintConfig copyWith({
    Size? size,
    double? pixelRatio,
    ThemeData? theme,
    ThemeData? darkTheme,
    String? outputDir,
    Color? background,
    EdgeInsets? padding,
    Locale? locale,
    TextDirection? textDirection,
    bool? wrapInScaffold,
  }) {
    return PrintConfig(
      size: size ?? this.size,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      theme: theme ?? this.theme,
      darkTheme: darkTheme ?? this.darkTheme,
      outputDir: outputDir ?? this.outputDir,
      background: background ?? this.background,
      padding: padding ?? this.padding,
      locale: locale ?? this.locale,
      textDirection: textDirection ?? this.textDirection,
      wrapInScaffold: wrapInScaffold ?? this.wrapInScaffold,
    );
  }
}
