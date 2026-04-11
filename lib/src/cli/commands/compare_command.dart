import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Compares generated screenshots against reference images using pixelmatch.
///
/// For a given entry `<name>`, expects:
/// - Generated:  `<outputDir>/<name>/crops/*.png`
/// - Reference:  `<outputDir>/<name>/<referenceDir>/crops/*.png`
///              (or `<outputDir>/<name>/<referenceDir>/*.png` if no crops/ subdir)
///
/// Falls back to the full-page image if the entry has no crops:
/// - Generated:  `<outputDir>/<name>/<device>.png`
/// - Reference:  `<outputDir>/<name>/<referenceDir>/<device>.png`
class CompareCommand extends Command<void> {
  CompareCommand() {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Entry name to compare. If omitted, compares all entries '
            'that have reference images.',
      )
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device name to compare. Defaults to the yaml default_device.',
      )
      ..addOption(
        'threshold',
        abbr: 't',
        help: 'Override the per-region similarity threshold (0.0–1.0).\n'
            'Defaults to compare_threshold in print_widget.yaml or 0.95.',
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
  String get name => 'compare';

  @override
  String get description =>
      'Compare generated screenshots against reference images using pixelmatch.';

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
    final filterName = argResults!['name'] as String?;
    final deviceOverride = argResults!['device'] as String?;
    final thresholdOverride = argResults!['threshold'] as String?;
    final jsonMode = argResults!['json'] as bool;

    // 1. Load yaml config
    final yamlFile = File(configPath);
    if (!yamlFile.existsSync()) {
      _reportError('Config file not found: $configPath\n'
          'Run "print_widget init" first.', jsonMode);
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
    final configThreshold =
        (yamlContent['compare_threshold'] as num?)?.toDouble() ?? 0.95;
    final threshold = thresholdOverride != null
        ? double.tryParse(thresholdOverride) ?? configThreshold
        : configThreshold;
    final device = deviceOverride ?? defaultDevice;

    // 2. Resolve pixelmatch_batch.mjs
    final scriptPath = await _resolvePixelmatchScript();
    if (scriptPath == null) {
      _reportError(
        'Could not locate pixelmatch_batch.mjs inside the print_widget package.\n'
        'This is likely a packaging bug — please file an issue.',
        jsonMode,
      );
      exitCode = 2;
      return;
    }

    // 3. Find entries to compare
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
        final entryName = p.basename(e.path);
        if (entryName.startsWith('.') || entryName == 'crops') continue;
        final refDir = Directory(p.join(e.path, referenceDir));
        if (refDir.existsSync()) entries.add(entryName);
      }
    }
    if (entries.isEmpty) {
      _reportError(
        'No entries with reference images found in $outputDir.\n'
        'Expected reference images under <entry>/$referenceDir/',
        jsonMode,
      );
      exitCode = 1;
      return;
    }

    // 4. Build the diff plan (pairs of actual/expected paths)
    final perEntryPairs = <String, List<_Pair>>{};
    final warnings = <String>[];
    for (final entry in entries) {
      final plan = _planComparisons(
        outputDir: outputDir,
        entryName: entry,
        referenceDir: referenceDir,
        device: device,
        warnings: warnings,
      );
      if (plan.isNotEmpty) perEntryPairs[entry] = plan;
    }
    if (perEntryPairs.isEmpty) {
      _reportError(
        'No comparable image pairs found. Ensure reference images exist at '
        '<outputDir>/<entry>/$referenceDir/ (either as crops/ or direct PNGs).',
        jsonMode,
      );
      for (final w in warnings) {
        stderr.writeln('  - $w');
      }
      exitCode = 1;
      return;
    }

    // 5. Invoke pixelmatch_batch.mjs once per entry (separate invocations so
    // we can cleanly attribute errors per entry in reports).
    final allResults = <String, List<_Result>>{};
    var allPassed = true;
    for (final entry in entries) {
      final pairs = perEntryPairs[entry];
      if (pairs == null) continue;
      final result = await _runPixelmatch(
        scriptPath: scriptPath,
        pairs: pairs,
      );
      allResults[entry] = result;
      for (final r in result) {
        if (r.error != null || r.similarity < threshold) allPassed = false;
      }
    }

    // 6. Report
    if (jsonMode) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'success': allPassed,
          'threshold': threshold,
          'entries': allResults.map(
            (entry, results) => MapEntry(entry, [
              for (final r in results)
                {
                  'name': r.name,
                  'similarity': r.similarity,
                  'mismatchedPixels': r.mismatchedPixels,
                  'totalPixels': r.totalPixels,
                  'diffPath': r.diffPath,
                  'error': r.error,
                  'passed': r.error == null && r.similarity >= threshold,
                },
            ]),
          ),
          'warnings': warnings,
        }),
      );
    } else {
      _printHumanReport(allResults, threshold);
      if (warnings.isNotEmpty) {
        stdout.writeln('');
        stdout.writeln('Warnings:');
        for (final w in warnings) {
          stdout.writeln('  ! $w');
        }
      }
    }

    exitCode = allPassed ? 0 : 1;
  }

  // --- helpers --------------------------------------------------------------

  void _reportError(String message, bool jsonMode) {
    if (jsonMode) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'success': false,
          'entries': <String, List<dynamic>>{},
          'errors': [message],
        }),
      );
    } else {
      stderr.writeln(message);
    }
  }

  Future<String?> _resolvePixelmatchScript() async {
    // Try to resolve the script via the package URI so it works after
    // `dart pub global activate` and in local dev alike.
    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse(
          'package:print_widget_flutter/src/tools/pixelmatch_batch.mjs',
        ),
      );
      if (uri != null) {
        final file = File.fromUri(uri);
        if (file.existsSync()) return file.path;
      }
    } catch (_) {
      // fall through
    }
    // Fallback: look next to the current script (useful for local dev).
    final here = Platform.script.toFilePath();
    final candidates = [
      p.join(p.dirname(here), 'pixelmatch_batch.mjs'),
      p.join(
        p.dirname(here),
        '..',
        'lib',
        'src',
        'tools',
        'pixelmatch_batch.mjs',
      ),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  List<_Pair> _planComparisons({
    required String outputDir,
    required String entryName,
    required String referenceDir,
    required String device,
    required List<String> warnings,
  }) {
    final entryDir = p.join(outputDir, entryName);
    final refRoot = p.join(entryDir, referenceDir);

    // Preferred layout: reference has a crops/ subdir and so does the generated.
    final refCropsDir = Directory(p.join(refRoot, 'crops'));
    final genCropsDir = Directory(p.join(entryDir, 'crops'));

    final pairs = <_Pair>[];

    if (refCropsDir.existsSync()) {
      if (!genCropsDir.existsSync()) {
        warnings.add(
          'Entry "$entryName": reference has crops/ but generated does not. '
          'Add a cropsFrom: to the PrintEntry and re-run generate.',
        );
        return pairs;
      }
      for (final file in refCropsDir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.png')) continue;
        final base = p.basename(file.path);
        final gen = File(p.join(genCropsDir.path, base));
        if (!gen.existsSync()) {
          warnings.add(
            'Entry "$entryName": generated crop missing for region "$base"',
          );
          continue;
        }
        pairs.add(
          _Pair(
            name: '$entryName/${p.basenameWithoutExtension(base)}',
            actual: gen.path,
            expected: file.path,
            diffOut: p.join(
              genCropsDir.path,
              '${p.basenameWithoutExtension(base)}_diff.png',
            ),
          ),
        );
      }
      return pairs;
    }

    // Sibling suffix layout (preferred for flat output):
    //   <entryDir>/<device>.png        (generated)
    //   <entryDir>/<device>.ref.png    (reference)
    //   <entryDir>/<device>.diff.png   (heatmap)
    // Removes the .reference/ subfolder — easier to browse in a file tree.
    final siblingRef = File(p.join(entryDir, '$device.ref.png'));
    final siblingGen = File(p.join(entryDir, '$device.png'));
    if (siblingRef.existsSync() && siblingGen.existsSync()) {
      pairs.add(
        _Pair(
          name: '$entryName/$device',
          actual: siblingGen.path,
          expected: siblingRef.path,
          diffOut: p.join(entryDir, '$device.diff.png'),
        ),
      );
      return pairs;
    }

    // Legacy layout: reference has top-level PNGs inside a .reference/ subdir.
    final refDirHandle = Directory(refRoot);
    if (!refDirHandle.existsSync()) return pairs;

    // Try the device-specific full page first.
    final refPng = File(p.join(refRoot, '$device.png'));
    final genPng = File(p.join(entryDir, '$device.png'));
    if (refPng.existsSync() && genPng.existsSync()) {
      pairs.add(
        _Pair(
          name: '$entryName/$device',
          actual: genPng.path,
          expected: refPng.path,
          diffOut: p.join(entryDir, '${device}_diff.png'),
        ),
      );
    }
    return pairs;
  }

  Future<List<_Result>> _runPixelmatch({
    required String scriptPath,
    required List<_Pair> pairs,
  }) async {
    final payload = jsonEncode({
      'threshold': 0.1,
      'includeAA': false,
      'pairs': [
        for (final pair in pairs)
          {
            'name': pair.name,
            'actual': pair.actual,
            'expected': pair.expected,
            'diffOut': pair.diffOut,
          },
      ],
    });

    final process = await Process.start(
      'node',
      [scriptPath],
      workingDirectory: Directory.current.path,
    );
    process.stdin.writeln(payload);
    await process.stdin.close();

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exit = await process.exitCode;
    final outStr = await stdoutFuture;
    final errStr = await stderrFuture;

    if (exit != 0) {
      return [
        _Result(
          name: 'pixelmatch-batch',
          similarity: 0,
          mismatchedPixels: 0,
          totalPixels: 0,
          diffPath: null,
          error: errStr.trim().isEmpty
              ? 'pixelmatch_batch exited with code $exit: ${outStr.trim()}'
              : errStr.trim(),
        ),
      ];
    }

    try {
      final decoded = jsonDecode(outStr) as Map<String, dynamic>;
      final results = (decoded['results'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      return results
          .map(
            (r) => _Result(
              name: r['name'] as String? ?? '?',
              similarity: (r['similarity'] as num?)?.toDouble() ?? 0.0,
              mismatchedPixels: (r['mismatchedPixels'] as num?)?.toInt() ?? 0,
              totalPixels: (r['totalPixels'] as num?)?.toInt() ?? 0,
              diffPath: r['diffPath'] as String?,
              error: r['error'] as String?,
            ),
          )
          .toList();
    } catch (e) {
      return [
        _Result(
          name: 'pixelmatch-batch',
          similarity: 0,
          mismatchedPixels: 0,
          totalPixels: 0,
          diffPath: null,
          error: 'Failed to parse pixelmatch_batch output: $e\n$outStr',
        ),
      ];
    }
  }

  void _printHumanReport(
    Map<String, List<_Result>> allResults,
    double threshold,
  ) {
    stdout.writeln('');
    stdout.writeln('print_widget compare');
    stdout.writeln('  threshold: ${(threshold * 100).toStringAsFixed(1)}%');
    stdout.writeln('');
    for (final entry in allResults.entries) {
      stdout.writeln('▸ ${entry.key}');
      for (final r in entry.value) {
        if (r.error != null) {
          stdout.writeln('    ✘ ${r.name}: ${r.error}');
          continue;
        }
        final score = (r.similarity * 100).toStringAsFixed(2);
        final passed = r.similarity >= threshold;
        final badge = passed ? '✓' : '✘';
        final tag = passed ? '' : '  (below ${(threshold * 100).toInt()}%)';
        final region = r.name.contains('/') ? r.name.split('/').last : r.name;
        stdout.writeln('    $badge $region: $score%$tag');
        if (!passed && r.diffPath != null) {
          stdout.writeln('      heatmap: ${r.diffPath}');
        }
      }
      stdout.writeln('');
    }
  }
}

class _Pair {
  const _Pair({
    required this.name,
    required this.actual,
    required this.expected,
    required this.diffOut,
  });

  final String name;
  final String actual;
  final String expected;
  final String diffOut;
}

class _Result {
  const _Result({
    required this.name,
    required this.similarity,
    required this.mismatchedPixels,
    required this.totalPixels,
    required this.diffPath,
    required this.error,
  });

  final String name;
  final double similarity;
  final int mismatchedPixels;
  final int totalPixels;
  final String? diffPath;
  final String? error;
}
