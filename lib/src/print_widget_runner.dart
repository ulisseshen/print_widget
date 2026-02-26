import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_frame.dart';
import 'print_config.dart';
import 'print_entry.dart';
import 'print_manifest.dart';
import 'print_session.dart';
import 'print_state.dart';
import 'printable.dart';

/// Captures a single widget as a golden PNG file.
///
/// You can optionally pass a [device] to render at that device's size and
/// pixel ratio. The PNG will be saved under `<outputDir>/<name>/<device>.png`.
///
/// ```dart
/// testWidgets('print my button', (tester) async {
///   await printWidget(
///     tester,
///     name: 'my_button',
///     widget: ElevatedButton(onPressed: () {}, child: Text('Click')),
///     device: DeviceFrame.iPhone15Pro,
///   );
/// });
/// ```
Future<void> printWidget(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  DeviceFrame? device,
  PrintConfig config = const PrintConfig(),
}) async {
  if (device != null) {
    final deviceConfig = config.copyWith(
      size: device.size,
      pixelRatio: device.pixelRatio,
    );
    await _renderAndCapture(
      tester,
      name: '$name/${device.name}',
      widget: widget,
      config: deviceConfig,
    );
  } else {
    await _renderAndCapture(tester, name: name, widget: widget, config: config);
  }
}

/// Captures the same widget across multiple device frames.
///
/// Generates one PNG per device, e.g. `prints/my_card/iphone_15_pro.png`.
///
/// ```dart
/// await printWidgetOnDevices(
///   tester,
///   name: 'login_form',
///   widget: LoginForm(),
///   devices: DeviceFrame.popular,
/// );
/// ```
Future<void> printWidgetOnDevices(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  required List<DeviceFrame> devices,
  PrintConfig config = const PrintConfig(),
}) async {
  for (final device in devices) {
    final deviceConfig = config.copyWith(
      size: device.size,
      pixelRatio: device.pixelRatio,
    );
    await _renderAndCapture(
      tester,
      name: '$name/${device.name}',
      widget: widget,
      config: deviceConfig,
    );
  }
}

/// Captures a list of widgets, each with its own name.
///
/// Useful for generating a "catalog" of widgets in one test run.
Future<void> printWidgets(
  WidgetTester tester, {
  required Map<String, Widget> widgets,
  DeviceFrame? device,
  PrintConfig config = const PrintConfig(),
}) async {
  for (final entry in widgets.entries) {
    if (device != null) {
      final deviceConfig = config.copyWith(
        size: device.size,
        pixelRatio: device.pixelRatio,
      );
      await _renderAndCapture(
        tester,
        name: '${entry.key}/${device.name}',
        widget: entry.value,
        config: deviceConfig,
      );
    } else {
      await _renderAndCapture(
        tester,
        name: entry.key,
        widget: entry.value,
        config: config,
      );
    }
  }
}

/// Captures light and dark variants of a widget.
Future<void> printWidgetThemed(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  ThemeData? lightTheme,
  ThemeData? darkTheme,
  DeviceFrame? device,
  PrintConfig config = const PrintConfig(),
}) async {
  final effectiveConfig = device != null
      ? config.copyWith(size: device.size, pixelRatio: device.pixelRatio)
      : config;

  final suffix = device != null ? '/${device.name}' : '';

  final light = lightTheme ?? ThemeData.light(useMaterial3: true);
  final dark = darkTheme ?? ThemeData.dark(useMaterial3: true);

  await _renderAndCapture(
    tester,
    name: '${name}_light$suffix',
    widget: widget,
    config: effectiveConfig.copyWith(theme: light, background: Colors.white),
  );

  await _renderAndCapture(
    tester,
    name: '${name}_dark$suffix',
    widget: widget,
    config: effectiveConfig.copyWith(theme: dark, background: Colors.black),
  );
}

/// Renders a single [PrintEntry] using a [PrintSession].
///
/// For pages ([PrintType.page]): the widget is passed directly to
/// `session.appWrapper` as a full-screen child.
///
/// For widgets ([PrintType.widget]): the widget is wrapped in a Scaffold
/// with Center for proper layout.
///
/// If the entry has [PrintEntry.states], each state is rendered as a
/// separate screenshot. The file naming depends on [PrintSession.stateOutputMode]:
/// prefix → `<name>/<state>_<device>.png`, suffix → `<name>/<device>_<state>.png`,
/// folder → `<name>/<state>/<device>.png`.
Future<List<PrintManifestEntry>> printEntry(
  WidgetTester tester, {
  required PrintEntry entry,
  required PrintSession session,
  DeviceFrame? deviceOverride,
  PrintConfig? config,
}) async {
  final effectiveConfig = config ?? const PrintConfig();
  final devices =
      entry.devices ??
      [deviceOverride ?? session.defaultDevice ?? DeviceFrame.iPhone15Pro];
  final manifestEntries = <PrintManifestEntry>[];

  // Build the list of (stateName, widget) pairs to render.
  final renderTargets = <(String?, Widget)>[];
  if (entry.states != null && entry.states!.isNotEmpty) {
    for (final s in entry.states!) {
      renderTargets.add((s.name, s.widget));
    }
  } else {
    renderTargets.add((null, entry.widget));
  }

  for (final (stateName, targetWidget) in renderTargets) {
    for (final device in devices) {
      final deviceConfig = effectiveConfig.copyWith(
        size: entry.size ?? device.size,
        pixelRatio: device.pixelRatio,
      );

      // Configure surface size.
      await tester.binding.setSurfaceSize(deviceConfig.size);
      tester.view.physicalSize = deviceConfig.size * deviceConfig.pixelRatio;
      tester.view.devicePixelRatio = deviceConfig.pixelRatio;

      // Build widget tree based on print type.
      final Widget child;
      if (entry.type == PrintType.page) {
        child = session.appWrapper(targetWidget);
      } else {
        child = session.appWrapper(
          Scaffold(
            body: Center(
              child: Padding(
                padding: deviceConfig.padding,
                child: targetWidget,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(child);
      await tester.pumpAndSettle();
      await _precacheAllImages(tester);

      final String fileName;
      if (stateName != null) {
        switch (session.stateOutputMode) {
          case StateOutputMode.prefix:
            fileName =
                '${session.outputDir}/${entry.name}/${stateName}_${device.name}.png';
          case StateOutputMode.suffix:
            fileName =
                '${session.outputDir}/${entry.name}/${device.name}_$stateName.png';
          case StateOutputMode.folder:
            fileName =
                '${session.outputDir}/${entry.name}/$stateName/${device.name}.png';
        }
      } else {
        fileName = '${session.outputDir}/${entry.name}/${device.name}.png';
      }

      await expectLater(find.byType(MaterialApp), matchesGoldenFile(fileName));

      manifestEntries.add(
        PrintManifestEntry(
          name: entry.name,
          type: entry.type == PrintType.page ? 'page' : 'widget',
          file: fileName,
          device: device.name,
          state: stateName,
          width: deviceConfig.size.width,
          height: deviceConfig.size.height,
          widthPx: (deviceConfig.size.width * deviceConfig.pixelRatio).round(),
          heightPx: (deviceConfig.size.height * deviceConfig.pixelRatio)
              .round(),
        ),
      );

      // Reset surface size.
      await tester.binding.setSurfaceSize(null);
    }
  }

  return manifestEntries;
}

/// Renders all entries from a print list and returns manifest entries.
Future<List<PrintManifestEntry>> printAllEntries(
  WidgetTester tester, {
  required List<PrintEntry> entries,
  required PrintSession session,
  PrintConfig? config,
}) async {
  final allManifestEntries = <PrintManifestEntry>[];

  for (final entry in entries) {
    final manifestEntries = await printEntry(
      tester,
      entry: entry,
      session: session,
      config: config,
    );
    allManifestEntries.addAll(manifestEntries);
  }

  return allManifestEntries;
}

// ---------------------------------------------------------------------------
// Internal
// ---------------------------------------------------------------------------

Future<void> _renderAndCapture(
  WidgetTester tester, {
  required String name,
  required Widget widget,
  required PrintConfig config,
}) async {
  // Configure surface size.
  await tester.binding.setSurfaceSize(config.size);
  tester.view.physicalSize = config.size * config.pixelRatio;
  tester.view.devicePixelRatio = config.pixelRatio;

  Widget body = Padding(
    padding: config.padding,
    child: Center(child: widget),
  );

  if (config.background != null) {
    body = ColoredBox(color: config.background!, child: body);
  }

  final wrappedWidget = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: config.theme ?? ThemeData.light(useMaterial3: true),
    locale: config.locale,
    home: Directionality(textDirection: config.textDirection, child: body),
  );

  await tester.pumpWidget(wrappedWidget);
  await tester.pumpAndSettle();
  await _precacheAllImages(tester);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('${config.outputDir}/$name.png'),
  );

  // Reset surface size to avoid leaking between tests.
  await tester.binding.setSurfaceSize(null);
}

Future<void> _precacheAllImages(WidgetTester tester) async {
  final imageWidgets = find.byType(Image);
  if (imageWidgets.evaluate().isEmpty) return;

  await tester.runAsync(() async {
    for (final element in imageWidgets.evaluate()) {
      final Image imageWidget = element.widget as Image;
      await precacheImage(imageWidget.image, element);
    }
  });
  await tester.pumpAndSettle();
}
