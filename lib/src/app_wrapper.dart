import 'package:flutter/material.dart';

/// A function that wraps a widget in a top-level app shell.
///
/// Typically returns a [MaterialApp] with your theme, locale, and the
/// given [child] as `home:`.
typedef AppWrapper = Widget Function(Widget child);

/// Creates an [AppWrapper] from common [MaterialApp] parameters.
///
/// A convenience helper so you don't have to write the full lambda:
///
/// ```dart
/// final printSession = PrintSession(
///   appWrapper: appWrapperFromMaterialApp(
///     theme: ThemeData(colorSchemeSeed: Colors.indigo),
///     locale: Locale('pt', 'BR'),
///   ),
/// );
/// ```
AppWrapper appWrapperFromMaterialApp({
  ThemeData? theme,
  ThemeData? darkTheme,
  Locale? locale,
  Iterable<LocalizationsDelegate>? localizationsDelegates,
}) {
  return (Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    darkTheme: darkTheme,
    locale: locale,
    localizationsDelegates: localizationsDelegates,
    home: child,
  );
}
