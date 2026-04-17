import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Promotes currently-generated screenshots into the reference position.
///
/// After browser-to-Flutter iteration converges (visual audit passes), the
/// next comparisons should be Flutter-to-Flutter to eliminate the Skia vs
/// Chromium text-rendering gap. `snapshot` copies the generated PNG and its
/// crop sidecars into `<outputDir>/<name>/<referenceDir>/` and writes a
/// `_origin.json` marker so `compare` (Phase 3) can pick the right threshold.
class SnapshotCommand extends Command<void> {
  SnapshotCommand() {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Entry name to snapshot. Required unless --all is given.',
      )
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device name to snapshot. Defaults to the yaml default_device.',
      )
      ..addFlag(
        'all',
        help: 'Snapshot every entry that has a generated output.',
        negatable: false,
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite existing reference files.',
        negatable: false,
      )
      ..addFlag(
        'json',
        help: 'Output results as JSON.',
        negatable: false,
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to print_widget.yaml config file.',
        defaultsTo: 'print_widget.yaml',
      );
  }

  @override
  String get name => 'snapshot';

  @override
  String get description =>
      'Promote generated screenshots to reference images (Flutter-to-Flutter baseline).';

  @override
  Future<void> run() async {
    final args = argResults!;
    final filterName = args['name'] as String?;
    final deviceOverride = args['device'] as String?;
    final all = args['all'] as bool;
    final force = args['force'] as bool;
    final jsonMode = args['json'] as bool;
    final configPath = args['config'] as String;

    if (!all && filterName == null) {
      _reportError(
        'snapshot: specify --name=<entry> or --all.',
        jsonMode,
      );
      exitCode = 2;
      return;
    }

    final yamlFile = File(configPath);
    if (!yamlFile.existsSync()) {
      _reportError(
        'Config file not found: $configPath\nRun "print_widget init" first.',
        jsonMode,
      );
      exitCode = 1;
      return;
    }
    final yamlContent = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
    final outputDir =
        yamlContent['output_dir'] as String? ?? 'print_widget/output';
    final defaultDevice =
        yamlContent['default_device'] as String? ?? 'iphone_15_pro';
    final referenceDir =
        yamlContent['reference_dir'] as String? ?? '.reference';
    final device = deviceOverride ?? defaultDevice;

    final outDir = Directory(outputDir);
    if (!outDir.existsSync()) {
      _reportError(
        'Output directory does not exist: $outputDir\n'
        'Run "print_widget generate" first.',
        jsonMode,
      );
      exitCode = 1;
      return;
    }

    final entries = <String>[];
    if (filterName != null) {
      entries.add(filterName);
    } else {
      for (final e in outDir.listSync().whereType<Directory>()) {
        final n = p.basename(e.path);
        if (n.startsWith('.') || n == 'crops') continue;
        entries.add(n);
      }
      entries.sort();
    }

    final results = <_EntryResult>[];
    for (final entry in entries) {
      results.add(await _snapshotEntry(
        outputDir: outputDir,
        entry: entry,
        device: device,
        referenceDir: referenceDir,
        force: force,
      ));
    }

    _report(results, jsonMode: jsonMode);

    final hadError = results.any((r) => r.error != null);
    final anyPromoted = results.any((r) => r.promoted > 0);
    if (hadError) {
      exitCode = 1;
    } else if (!anyPromoted) {
      exitCode = 2;
    } else {
      exitCode = 0;
    }
  }

  Future<_EntryResult> _snapshotEntry({
    required String outputDir,
    required String entry,
    required String device,
    required String referenceDir,
    required bool force,
  }) async {
    final entryDir = Directory(p.join(outputDir, entry));
    if (!entryDir.existsSync()) {
      return _EntryResult(
        entry: entry,
        error: 'entry dir does not exist: ${entryDir.path}',
      );
    }

    final refDir = Directory(p.join(entryDir.path, referenceDir));
    refDir.createSync(recursive: true);

    final copied = <String>[];
    final skipped = <String>[];

    final fullPng = File(p.join(entryDir.path, '$device.png'));
    final refFullPng = File(p.join(refDir.path, '$device.png'));
    if (fullPng.existsSync()) {
      if (refFullPng.existsSync() && !force) {
        skipped.add(p.basename(fullPng.path));
      } else {
        fullPng.copySync(refFullPng.path);
        copied.add(p.basename(fullPng.path));
      }
    }

    final cropsDir = Directory(p.join(entryDir.path, 'crops'));
    if (cropsDir.existsSync()) {
      final refCropsDir = Directory(p.join(refDir.path, 'crops'));
      refCropsDir.createSync(recursive: true);
      for (final f in cropsDir.listSync().whereType<File>()) {
        final base = p.basename(f.path);
        if (!base.endsWith('.png')) continue;
        if (base.endsWith('_diff.png')) continue;
        final dst = File(p.join(refCropsDir.path, base));
        if (dst.existsSync() && !force) {
          skipped.add('crops/$base');
        } else {
          f.copySync(dst.path);
          copied.add('crops/$base');
        }
      }
    }

    if (copied.isNotEmpty) {
      final originFile = File(p.join(refDir.path, '_origin.json'));
      final originData = <String, dynamic>{
        'origin': 'flutter',
        'promoted_at': DateTime.now().toUtc().toIso8601String(),
        'device': device,
        'files': copied,
      };
      originFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(originData),
      );
    }

    return _EntryResult(
      entry: entry,
      promoted: copied.length,
      skipped: skipped.length,
      copiedFiles: copied,
      skippedFiles: skipped,
    );
  }

  void _report(List<_EntryResult> results, {required bool jsonMode}) {
    if (jsonMode) {
      stdout.writeln(jsonEncode({
        'entries': [
          for (final r in results)
            {
              'entry': r.entry,
              'promoted': r.promoted,
              'skipped': r.skipped,
              'copiedFiles': r.copiedFiles,
              'skippedFiles': r.skippedFiles,
              if (r.error != null) 'error': r.error,
            },
        ],
      }));
      return;
    }

    for (final r in results) {
      if (r.error != null) {
        stderr.writeln('✗ ${r.entry}: ${r.error}');
        continue;
      }
      if (r.promoted == 0 && r.skipped == 0) {
        stdout.writeln('· ${r.entry}: nothing to promote');
      } else if (r.promoted == 0) {
        stdout.writeln(
          '· ${r.entry}: ${r.skipped} existing reference(s) preserved '
          '(pass --force to overwrite)',
        );
      } else {
        final skipSuffix = r.skipped > 0
            ? ', ${r.skipped} kept (use --force to overwrite)'
            : '';
        stdout.writeln('✓ ${r.entry}: promoted ${r.promoted} file(s)$skipSuffix');
      }
    }

    final totalPromoted = results.fold<int>(0, (a, b) => a + b.promoted);
    final totalSkipped = results.fold<int>(0, (a, b) => a + b.skipped);
    final errors = results.where((r) => r.error != null).length;
    stdout.writeln(
      '\nsnapshot: ${results.length} entry(ies) processed, '
      '$totalPromoted promoted, $totalSkipped skipped, $errors error(s).',
    );
  }

  void _reportError(String msg, bool jsonMode) {
    if (jsonMode) {
      stdout.writeln(jsonEncode({'error': msg}));
    } else {
      stderr.writeln(msg);
    }
  }
}

class _EntryResult {
  _EntryResult({
    required this.entry,
    this.promoted = 0,
    this.skipped = 0,
    this.copiedFiles = const [],
    this.skippedFiles = const [],
    this.error,
  });

  final String entry;
  final int promoted;
  final int skipped;
  final List<String> copiedFiles;
  final List<String> skippedFiles;
  final String? error;
}
