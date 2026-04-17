import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Runs the Playwright-backed design extractor (`extract.mjs`) transparently.
///
/// The CLI owns the Playwright runtime — users never need to set up a Node
/// project, install `playwright`, or copy scripts around. First invocation
/// downloads Chromium (~60s); subsequent runs reuse the cached install
/// under `.dart_tool/print_widget/extract-runtime/`.
class ExtractCommand extends Command<void> {
  ExtractCommand() {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to states.json. '
            'If omitted, --url is required to generate a minimal inline config.',
      )
      ..addOption(
        'url',
        abbr: 'u',
        help: 'Base URL to capture. Used when --config is omitted '
            'to generate a minimal single-state config.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output directory. '
            'CLI flag > config.output > print_widget/output/extract-<host>-<ts>.',
      )
      ..addOption(
        'viewport',
        help: 'Viewport as WxH (e.g. 1440x2400).',
        defaultsTo: '1440x2400',
      )
      ..addOption(
        'dpr',
        help: 'Device pixel ratio.',
        defaultsTo: '2',
      )
      ..addOption(
        'theme',
        help: 'Path to theme-ref.json for token mapping.',
      )
      ..addOption(
        'runtime-dir',
        help: 'Playwright cache directory.',
        defaultsTo: '.dart_tool/print_widget/extract-runtime',
      )
      ..addMultiOption(
        'chrome-purge',
        help: 'CSS selector removed from DOM before screenshots. Repeatable.',
      )
      ..addMultiOption(
        'force-font',
        help: 'Google Fonts spec to force-load '
            '(e.g. "Inter:wght@400;500;600;700"). Repeatable.',
      )
      ..addFlag(
        'skip-install',
        help: 'Skip Playwright install check '
            '(faster startup; fails if node_modules/playwright is missing).',
        negatable: false,
      );
  }

  @override
  String get name => 'extract';

  @override
  String get description => 'Extract design tokens, screenshots, and '
      'per-element structural specs from a rendered web page (Playwright).';

  @override
  Future<void> run() async {
    final args = argResults!;
    final configPath = args['config'] as String?;
    final url = args['url'] as String?;
    final outputOverride = args['output'] as String?;
    final viewport = args['viewport'] as String;
    final dpr = args['dpr'] as String;
    final themePath = args['theme'] as String?;
    final runtimeDir = args['runtime-dir'] as String;
    final chromePurge = args['chrome-purge'] as List<String>;
    final forceFont = args['force-font'] as List<String>;
    final skipInstall = args['skip-install'] as bool;

    if (configPath == null && url == null) {
      stderr.writeln(
        'extract: requires --config <path> or --url <url>\n'
        'Example: print_widget extract --url=https://example.com \\\n'
        '                              --output=print_widget/output/example',
      );
      exitCode = 2;
      return;
    }

    final scriptPath = await _resolveExtractScript();
    if (scriptPath == null) {
      stderr.writeln(
        'extract: could not locate extract.mjs inside the print_widget package.\n'
        'This is a packaging bug — please file an issue.',
      );
      exitCode = 2;
      return;
    }

    final Map<String, dynamic> config;
    if (configPath != null) {
      final f = File(configPath);
      if (!f.existsSync()) {
        stderr.writeln('extract: config not found: $configPath');
        exitCode = 2;
        return;
      }
      try {
        config = (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
      } catch (e) {
        stderr.writeln('extract: invalid JSON in $configPath: $e');
        exitCode = 2;
        return;
      }
    } else {
      config = <String, dynamic>{};
    }

    if (url != null) config['url'] = url;
    config.putIfAbsent('states', () => [
          {'name': 'initial', 'steps': const [], 'settleMs': 2000},
        ]);

    final vpMatch = RegExp(r'^(\d+)x(\d+)$').firstMatch(viewport);
    if (vpMatch == null) {
      stderr.writeln('extract: --viewport must be WxH (got "$viewport")');
      exitCode = 2;
      return;
    }
    config['viewport'] = {
      'width': int.parse(vpMatch.group(1)!),
      'height': int.parse(vpMatch.group(2)!),
    };
    config['deviceScaleFactor'] = double.tryParse(dpr) ?? 2;

    if (chromePurge.isNotEmpty) config['chromePurge'] = chromePurge;
    if (forceFont.isNotEmpty) config['forceFonts'] = forceFont;

    final resolvedOutput = outputOverride ??
        (config['output'] as String?) ??
        _defaultOutputFor(config['url'] as String?);
    config['output'] = resolvedOutput;

    final rtDir = Directory(runtimeDir);
    rtDir.createSync(recursive: true);

    if (!skipInstall) {
      final installed = await _ensurePlaywright(rtDir);
      if (!installed) {
        exitCode = 2;
        return;
      }
    }

    final rtScript = File(p.join(rtDir.path, 'extract.mjs'));
    rtScript.writeAsStringSync(File(scriptPath).readAsStringSync());

    final runConfigFile = File(p.join(rtDir.path, 'states.run.json'));
    runConfigFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    stdout.writeln('print_widget extract → $resolvedOutput');
    final process = await Process.start(
      'node',
      [
        rtScript.path,
        runConfigFile.path,
        if (themePath != null) '--theme=$themePath',
      ],
      workingDirectory: rtDir.path,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  }

  Future<String?> _resolveExtractScript() async {
    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:print_widget_flutter/src/tools/extract.mjs'),
      );
      if (uri != null) {
        final file = File.fromUri(uri);
        if (file.existsSync()) return file.path;
      }
    } catch (_) {
      // fall through
    }
    final here = Platform.script.toFilePath();
    final candidates = [
      p.join(p.dirname(here), 'extract.mjs'),
      p.join(p.dirname(here), '..', 'lib', 'src', 'tools', 'extract.mjs'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  String _defaultOutputFor(String? url) {
    final host = url == null
        ? 'local'
        : (Uri.tryParse(url)?.host ?? 'local')
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join('print_widget', 'output', 'extract-$host-$ts');
  }

  Future<bool> _ensurePlaywright(Directory rtDir) async {
    final nodeModules = Directory(
      p.join(rtDir.path, 'node_modules', 'playwright'),
    );
    if (nodeModules.existsSync()) return true;

    stdout.writeln(
      'print_widget extract: installing Playwright (first run, ~60s)...',
    );

    final pkgJson = File(p.join(rtDir.path, 'package.json'));
    if (!pkgJson.existsSync()) {
      final init = await Process.run(
        'npm',
        ['init', '-y'],
        workingDirectory: rtDir.path,
      );
      if (init.exitCode != 0) {
        stderr.writeln(
          'extract: npm init failed in ${rtDir.path}:\n${init.stderr}',
        );
        return false;
      }
    }

    final install = await Process.start(
      'npm',
      ['install', 'playwright', '--silent'],
      workingDirectory: rtDir.path,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await install.exitCode != 0) {
      stderr.writeln(
        'extract: npm install playwright failed. '
        'Is Node.js installed and reachable on PATH?',
      );
      return false;
    }

    final browser = await Process.start(
      'npx',
      ['playwright', 'install', 'chromium'],
      workingDirectory: rtDir.path,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await browser.exitCode != 0) {
      stderr.writeln('extract: playwright install chromium failed.');
      return false;
    }
    return true;
  }
}
