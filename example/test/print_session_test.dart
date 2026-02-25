import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget_flutter/print_widget.dart';

import 'package:print_widget_example/widgets/user_avatar.dart';
import 'prints/print_config.dart';

/// Run with:
///   cd example
///   flutter test --update-goldens test/print_session_test.dart
///
/// Screenshots saved to: example/test/prints/output/
void main() {
  group('PrintSession - generate all', () {
    testWidgets('generates screenshots for all entries', (tester) async {
      final manifestEntries = await printAllEntries(
        tester,
        entries: printList,
        session: printSession,
      );

      // Write manifest
      if (printSession.generateManifest) {
        final manifest = PrintManifest(
          generatedAt: DateTime.now(),
          screenshots: manifestEntries,
        );

        final manifestFile = File('${printSession.outputDir}/manifest.json');
        manifestFile.parent.createSync(recursive: true);
        manifestFile.writeAsStringSync(manifest.toJsonString());
      }

      // Verify all entries were captured
      expect(manifestEntries, isNotEmpty);

      // Print summary
      // ignore: avoid_print
      print('\n--- Print Summary ---');
      // ignore: avoid_print
      print('Generated ${manifestEntries.length} screenshot(s):');
      for (final entry in manifestEntries) {
        // ignore: avoid_print
        print(
          '  [${entry.type}] ${entry.name} @ ${entry.device} '
          '(${entry.width.toInt()}x${entry.height.toInt()})',
        );
      }
    });
  });

  group('PrintSession - individual entries', () {
    testWidgets('generates single page', (tester) async {
      final pageEntry = printList.firstWhere((e) => e.name == 'login_page');
      final entries = await printEntry(
        tester,
        entry: pageEntry,
        session: printSession,
      );

      expect(entries.length, 1);
      expect(entries.first.type, 'page');
      expect(entries.first.name, 'login_page');
    });

    testWidgets('generates single widget', (tester) async {
      final widgetEntry = printList.firstWhere((e) => e.name == 'product_card');
      final entries = await printEntry(
        tester,
        entry: widgetEntry,
        session: printSession,
      );

      expect(entries.length, 1);
      expect(entries.first.type, 'widget');
      expect(entries.first.name, 'product_card');
    });

    testWidgets('generates widget on multiple devices', (tester) async {
      final multiEntry = printList.firstWhere(
        (e) => e.name == 'product_card_responsive',
      );
      final entries = await printEntry(
        tester,
        entry: multiEntry,
        session: printSession,
      );

      // Should have one entry per popular device
      expect(entries.length, DeviceFrame.popular.length);
      for (final entry in entries) {
        expect(entry.type, 'widget');
        expect(entry.name, 'product_card_responsive');
      }
    });

    testWidgets('generates grouped states as nested folders', (tester) async {
      final statesEntry = printList.firstWhere(
        (e) => e.name == 'user_avatar_states',
      );
      final entries = await printEntry(
        tester,
        entry: statesEntry,
        session: printSession,
      );

      // Should have one manifest entry per state (2 states x 1 device)
      expect(entries.length, 2);

      // Verify state names are present
      expect(entries[0].state, 'online');
      expect(entries[1].state, 'offline');

      // Verify all share the same parent name
      for (final entry in entries) {
        expect(entry.name, 'user_avatar_states');
        expect(entry.type, 'widget');
      }

      // Verify file paths include state as filename prefix (default mode)
      expect(entries[0].file, contains('user_avatar_states/online_'));
      expect(entries[1].file, contains('user_avatar_states/offline_'));
    });

    testWidgets('generates states with suffix output mode', (tester) async {
      final suffixSession = PrintSession(
        appWrapper: printSession.appWrapper,
        defaultDevice: printSession.defaultDevice,
        outputDir: 'test/prints/output_suffix',
        stateOutputMode: StateOutputMode.suffix,
      );

      final statesEntry = PrintEntry(
        name: 'avatar_suffix',
        widget: const SizedBox.shrink(),
        type: PrintType.widget,
        size: const Size(300, 100),
        states: [
          state(
            'online',
            const UserAvatar(name: 'A', role: 'B', isOnline: true),
          ),
          state(
            'offline',
            const UserAvatar(name: 'C', role: 'D', isOnline: false),
          ),
        ],
      );

      final entries = await printEntry(
        tester,
        entry: statesEntry,
        session: suffixSession,
      );

      expect(entries.length, 2);
      // suffix mode: <device>_<state>.png
      expect(
        entries[0].file,
        contains('avatar_suffix/iphone_15_pro_online.png'),
      );
      expect(
        entries[1].file,
        contains('avatar_suffix/iphone_15_pro_offline.png'),
      );
    });

    testWidgets('generates states with folder output mode', (tester) async {
      final folderSession = PrintSession(
        appWrapper: printSession.appWrapper,
        defaultDevice: printSession.defaultDevice,
        outputDir: 'test/prints/output_folder',
        stateOutputMode: StateOutputMode.folder,
      );

      final statesEntry = PrintEntry(
        name: 'avatar_folder',
        widget: const SizedBox.shrink(),
        type: PrintType.widget,
        size: const Size(300, 100),
        states: [
          state(
            'online',
            const UserAvatar(name: 'A', role: 'B', isOnline: true),
          ),
          state(
            'offline',
            const UserAvatar(name: 'C', role: 'D', isOnline: false),
          ),
        ],
      );

      final entries = await printEntry(
        tester,
        entry: statesEntry,
        session: folderSession,
      );

      expect(entries.length, 2);
      // folder mode: <state>/<device>.png
      expect(
        entries[0].file,
        contains('avatar_folder/online/iphone_15_pro.png'),
      );
      expect(
        entries[1].file,
        contains('avatar_folder/offline/iphone_15_pro.png'),
      );
    });
  });
}
