import 'package:flutter/material.dart';

typedef AppWrapper = Widget Function(Widget child);

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
