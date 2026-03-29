import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// End-to-end integration tests for the print_widget CLI.
///
/// These tests simulate real user flows by running the actual CLI binary
/// against real Flutter projects. They verify that the full pipeline works
/// from command invocation to file output.
///
/// Some tests (init, generate) can take 30+ seconds due to `flutter create`
/// and `flutter test --update-goldens` subprocess calls.
void main() {
  /// Resolves the project root by walking up from the current directory
  /// until we find pubspec.yaml with name: print_widget_flutter.
  late final String projectRoot;

  setUpAll(() {
    var dir = Directory.current;
    while (!File('${dir.path}/pubspec.yaml').existsSync() ||
        !File('${dir.path}/pubspec.yaml')
            .readAsStringSync()
            .contains('name: print_widget_flutter')) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw StateError(
          'Could not find print_widget project root from ${Directory.current.path}',
        );
      }
      dir = parent;
    }
    projectRoot = dir.path;
  });

  group('Test 1: CLI binary compiles and runs with plain dart', () {
    // This catches the "dart:ui import" bug — if CLI imports Flutter types,
    // running with plain `dart` (not flutter) will fail.
    test('dart run bin/print_widget.dart --help outputs help text', () async {
      final result = await Process.run(
        'dart',
        ['run', 'bin/print_widget.dart', '--help'],
        workingDirectory: projectRoot,
      );

      final stdout = result.stdout as String;
      final stderr = result.stderr as String;

      expect(
        result.exitCode,
        equals(0),
        reason: 'CLI should exit 0 with --help.\nstderr: $stderr',
      );
      expect(
        stdout,
        contains('print_widget'),
        reason: 'Help output should mention print_widget',
      );
      // Verify it lists the available commands
      expect(stdout, contains('init'));
      expect(stdout, contains('generate'));
      expect(stdout, contains('list'));
      expect(stdout, contains('config'));
    });
  });

  group('Test 2: print_widget init in a fresh Flutter project', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('print_widget_init_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('init creates all expected files and shows guidance', () async {
      // Step 1: Create a fresh Flutter project
      final createResult = await Process.run(
        'flutter',
        ['create', '--project-name', 'test_app', '.'],
        workingDirectory: tempDir.path,
        runInShell: true,
      );

      expect(
        createResult.exitCode,
        equals(0),
        reason:
            'flutter create should succeed.\nstderr: ${createResult.stderr}',
      );

      // Step 2: Run print_widget init (skip dep to avoid pub.dev dependency)
      final initResult = await Process.run(
        'dart',
        ['run', '$projectRoot/bin/print_widget.dart', 'init', '--skip-dep'],
        workingDirectory: tempDir.path,
      );

      final stdout = initResult.stdout as String;

      expect(
        initResult.exitCode,
        equals(0),
        reason:
            'init should exit 0.\nstdout: $stdout\nstderr: ${initResult.stderr}',
      );

      // Verify all expected files were created
      expect(
        File('${tempDir.path}/print_widget.yaml').existsSync(),
        isTrue,
        reason: 'print_widget.yaml should be created',
      );
      expect(
        File('${tempDir.path}/print_widget/config.dart').existsSync(),
        isTrue,
        reason: 'print_widget/config.dart should be created',
      );
      expect(
        File('${tempDir.path}/test/flutter_test_config.dart').existsSync(),
        isTrue,
        reason: 'test/flutter_test_config.dart should be created',
      );
      expect(
        File('${tempDir.path}/PRINT_WIDGET.md').existsSync(),
        isTrue,
        reason: 'PRINT_WIDGET.md should be created',
      );

      // Verify .gitignore contains the output directory
      final gitignoreContent =
          File('${tempDir.path}/.gitignore').readAsStringSync();
      expect(
        gitignoreContent,
        contains('print_widget/output/'),
        reason: '.gitignore should include print_widget/output/',
      );

      // Verify output contains setup complete and AI guidance
      expect(
        stdout,
        contains('Setup complete!'),
        reason: 'Output should show "Setup complete!"',
      );
      expect(
        stdout,
        contains('AI:'),
        reason: 'Output should contain AI guidance section',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('Test 3: print_widget generate produces screenshots', () {
    test('generate creates manifest.json and PNG files', () async {
      final exampleDir = '$projectRoot/example';

      // Run generate via the CLI binary
      final result = await Process.run(
        'dart',
        ['run', '$projectRoot/bin/print_widget.dart', 'generate'],
        workingDirectory: exampleDir,
      );

      final stdout = result.stdout as String;

      expect(
        result.exitCode,
        equals(0),
        reason:
            'generate should exit 0.\nstdout: $stdout\nstderr: ${result.stderr}',
      );

      // Verify manifest.json was created
      final manifestFile = File('$exampleDir/test/prints/output/manifest.json');
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'manifest.json should exist in output directory',
      );

      // Verify manifest.json has valid JSON with expected fields
      final manifestContent = manifestFile.readAsStringSync();
      final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;

      expect(
        manifest,
        containsPair('generatedAt', isA<String>()),
        reason: 'manifest.json should have generatedAt field',
      );
      expect(
        manifest,
        containsPair('screenshots', isA<List>()),
        reason: 'manifest.json should have screenshots array',
      );

      final screenshots = manifest['screenshots'] as List;
      expect(
        screenshots,
        isNotEmpty,
        reason: 'screenshots array should not be empty',
      );

      // Verify at least one PNG file exists in the output directory
      final outputDir = Directory('$exampleDir/test/prints/output');
      final pngFiles = outputDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'));

      expect(
        pngFiles,
        isNotEmpty,
        reason: 'At least one PNG file should exist in output directory',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('Test 4: print_widget list shows entries', () {
    test('list outputs entry names from example config', () async {
      final exampleDir = '$projectRoot/example';

      final result = await Process.run(
        'dart',
        ['run', '$projectRoot/bin/print_widget.dart', 'list'],
        workingDirectory: exampleDir,
      );

      final stdout = result.stdout as String;

      expect(
        result.exitCode,
        equals(0),
        reason: 'list should exit 0.\nstderr: ${result.stderr}',
      );

      // Verify it shows known entry names from the example config
      expect(stdout, contains('login_page'));
      expect(stdout, contains('home_page'));
      expect(stdout, contains('product_card'));
      expect(stdout, contains('stats_card'));
      expect(stdout, contains('user_avatar_online'));
      expect(stdout, contains('user_avatar_offline'));

      // Verify it shows entry count
      expect(
        stdout,
        contains('entry(ies) found'),
        reason: 'Output should show entry count',
      );
    });
  });

  group('Test 5: print_widget config reads settings', () {
    test('config shows current configuration values', () async {
      final exampleDir = '$projectRoot/example';

      final result = await Process.run(
        'dart',
        ['run', '$projectRoot/bin/print_widget.dart', 'config'],
        workingDirectory: exampleDir,
      );

      final stdout = result.stdout as String;

      expect(
        result.exitCode,
        equals(0),
        reason: 'config should exit 0.\nstderr: ${result.stderr}',
      );

      // Verify it shows config values from the example's print_widget.yaml
      expect(stdout, contains('print_widget configuration'));
      expect(stdout, contains('config_file'));
      expect(stdout, contains('output_dir'));
      expect(stdout, contains('default_device'));
      expect(stdout, contains('iphone_15_pro'));
    });
  });

  group('Test 6: print_widget --llm-guide outputs guide', () {
    test('--llm-guide outputs commands, devices, and VS Code section',
        () async {
      final exampleDir = '$projectRoot/example';

      final result = await Process.run(
        'dart',
        ['run', '$projectRoot/bin/print_widget.dart', '--llm-guide'],
        workingDirectory: exampleDir,
      );

      final stdout = result.stdout as String;

      expect(
        result.exitCode,
        equals(0),
        reason: '--llm-guide should exit 0.\nstderr: ${result.stderr}',
      );

      // Verify it outputs the guide with expected sections
      expect(
        stdout,
        contains('# print_widget'),
        reason: 'Guide should start with a header',
      );
      expect(
        stdout,
        contains('Commands'),
        reason: 'Guide should list commands',
      );
      expect(
        stdout,
        contains('generate'),
        reason: 'Guide should mention generate command',
      );
      expect(
        stdout,
        contains('Devices'),
        reason: 'Guide should list devices',
      );
      expect(
        stdout,
        contains('iphone_15_pro'),
        reason: 'Guide should list specific device names',
      );
      expect(
        stdout,
        contains('VS Code'),
        reason: 'Guide should contain VS Code section',
      );
    });
  });
}
