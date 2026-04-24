import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Downloads fonts referenced by `_fonts.json` reports into the project.
///
/// Closes the loop exposed by the extract pipeline: the browser renders crops
/// with Inter/etc via Google Fonts, but the Flutter project has no local copy,
/// so `TextStyle(fontFamily: 'Inter')` silently falls back to Roboto/Ahem and
/// pixelmatch misleads. This command reads the `(family, weight)` pairs that
/// `extract.mjs` recorded and fetches matching TTFs from Google Fonts into
/// `google_fonts/` (default) or `assets/fonts/`.
///
/// Scanning strategy:
///   • `--source=<path>` — explicit single `_fonts.json` OR directory root to
///     walk recursively for `_fonts.json` files.
///   • Default (no flag) — reads `print_widget.yaml` `output_dir` and walks it.
///     All reports are merged (union of weights per family) before downloading.
class FontsCommand extends Command<void> {
  FontsCommand() {
    argParser
      ..addOption(
        'source',
        abbr: 's',
        help: 'Path to a `_fonts.json` file, or a directory to scan '
            'recursively for `_fonts.json` files. '
            'Defaults to the configured `output_dir`.',
      )
      ..addOption(
        'dest',
        abbr: 'd',
        help: 'Destination directory for downloaded fonts. '
            '`google_fonts/` is auto-detected by loadPrintWidgetFonts '
            'without touching pubspec.yaml.',
        allowed: ['google_fonts', 'assets/fonts'],
        defaultsTo: 'google_fonts',
      )
      ..addFlag(
        'dry-run',
        help: 'Print what would be downloaded without fetching anything.',
        negatable: false,
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Overwrite existing TTF files.',
        negatable: false,
      )
      ..addFlag(
        'json',
        help: 'Emit structured result on stdout.',
        negatable: false,
      )
      ..addFlag(
        'pubspec',
        help: 'When --dest=assets/fonts, append a `flutter.fonts` block to '
            'pubspec.yaml. Ignored for google_fonts/ which is auto-detected.',
        defaultsTo: true,
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to print_widget.yaml config file.',
        defaultsTo: 'print_widget.yaml',
      );
  }

  @override
  String get name => 'fonts';

  @override
  String get description =>
      'Sync fonts referenced by `_fonts.json` reports into the project '
      '(downloads TTFs from Google Fonts).';

  @override
  Future<void> run() async {
    final args = argResults!;
    final sourceArg = args['source'] as String?;
    final dest = args['dest'] as String;
    final dryRun = args['dry-run'] as bool;
    final force = args['force'] as bool;
    final jsonMode = args['json'] as bool;
    final updatePubspec = args['pubspec'] as bool;
    final configPath = args['config'] as String;

    final result = <String, dynamic>{
      'dest': dest,
      'dryRun': dryRun,
      'reports': <String>[],
      'downloads': <Map<String, dynamic>>[],
      'skipped': <Map<String, dynamic>>[],
      'errors': <String>[],
    };

    // 1. Resolve the source set of _fonts.json reports.
    final reportPaths = await _collectReports(
      sourceArg: sourceArg,
      configPath: configPath,
      errors: result['errors'] as List<String>,
    );
    result['reports'] = reportPaths;

    if (reportPaths.isEmpty) {
      _emit(result, jsonMode, error: 'No _fonts.json found. '
          'Run `print_widget extract` first, or pass --source=<path>.');
      exitCode = 2;
      return;
    }

    // 2. Merge all reports into family -> Set<weight>.
    final merged = _mergeReports(reportPaths);
    if (merged.isEmpty) {
      _emit(result, jsonMode,
          error: 'All reports list only system fonts or are empty.');
      exitCode = 2;
      return;
    }

    // 3. Ensure destination dir exists.
    final destDir = Directory(dest);
    if (!dryRun) destDir.createSync(recursive: true);

    // 4. For each family, fetch the CSS with a TTF-forcing UA and download.
    for (final entry in merged.entries) {
      final family = entry.key;
      final weights = entry.value.toList()..sort();

      try {
        final urls = dryRun
            ? {for (final w in weights) w: '<dry-run>'}
            : await _resolveTtfUrls(family, weights);

        for (final w in weights) {
          final url = urls[w];
          final filename = '$family-${_weightName(w)}.ttf';
          final outPath = p.join(destDir.path, filename);
          final outFile = File(outPath);

          if (outFile.existsSync() && !force) {
            (result['skipped'] as List).add({
              'family': family,
              'weight': w,
              'file': outPath,
              'reason': 'exists (pass --force to overwrite)',
            });
            continue;
          }

          if (url == null) {
            (result['errors'] as List).add(
              '$family weight $w: not returned by Google Fonts CSS2 API',
            );
            continue;
          }

          if (dryRun) {
            (result['downloads'] as List).add({
              'family': family,
              'weight': w,
              'file': outPath,
              'url': url,
              'status': 'would-download',
            });
            continue;
          }

          final bytes = await _fetchBytes(url);
          outFile.writeAsBytesSync(bytes);
          (result['downloads'] as List).add({
            'family': family,
            'weight': w,
            'file': outPath,
            'url': url,
            'status': 'downloaded',
            'bytes': bytes.length,
          });
        }
      } catch (e) {
        (result['errors'] as List).add('$family: $e');
      }
    }

    // 5. Update pubspec.yaml if asked (only meaningful for assets/fonts).
    if (!dryRun && dest == 'assets/fonts' && updatePubspec) {
      final change = _upsertPubspecFonts(
        pubspecPath: 'pubspec.yaml',
        merged: merged,
        dest: dest,
      );
      if (change != null) {
        result['pubspecUpdated'] = change;
      }
    }

    final errs = (result['errors'] as List).length;
    _emit(result, jsonMode);
    exitCode = errs > 0 ? 1 : 0;
  }

  // ---------------------------------------------------------------------------
  // Source resolution
  // ---------------------------------------------------------------------------

  Future<List<String>> _collectReports({
    required String? sourceArg,
    required String configPath,
    required List<String> errors,
  }) async {
    final roots = <String>[];
    if (sourceArg != null) {
      roots.add(sourceArg);
    } else {
      final yamlFile = File(configPath);
      if (yamlFile.existsSync()) {
        try {
          final y = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
          roots.add(y['output_dir'] as String? ?? 'print_widget/output');
        } catch (e) {
          errors.add('Failed to parse $configPath: $e');
          roots.add('print_widget/output');
        }
      } else {
        roots.add('print_widget/output');
      }
    }

    final found = <String>{};
    for (final r in roots) {
      final f = File(r);
      if (f.existsSync()) {
        if (p.basename(r) == '_fonts.json') found.add(p.normalize(r));
        continue;
      }
      final d = Directory(r);
      if (!d.existsSync()) continue;
      for (final e in d.listSync(recursive: true, followLinks: false)) {
        if (e is File && p.basename(e.path) == '_fonts.json') {
          found.add(p.normalize(e.path));
        }
      }
    }
    return found.toList()..sort();
  }

  Map<String, Set<int>> _mergeReports(List<String> paths) {
    final merged = <String, Set<int>>{};
    for (final path in paths) {
      try {
        final data = jsonDecode(File(path).readAsStringSync());
        if (data is! Map) continue;
        final families = data['families'];
        if (families is! List) continue;
        for (final fam in families) {
          if (fam is! Map) continue;
          final name = fam['family'] as String?;
          final weights = fam['weights'];
          if (name == null || weights is! List) continue;
          final set = merged.putIfAbsent(name, () => <int>{});
          for (final w in weights) {
            if (w is int) set.add(w);
            if (w is String) {
              final n = int.tryParse(w);
              if (n != null) set.add(n);
            }
          }
        }
      } catch (_) {
        // Skip malformed reports silently; errors surface via _emit.
      }
    }
    return merged;
  }

  // ---------------------------------------------------------------------------
  // Google Fonts CSS2 → TTF URL resolution
  // ---------------------------------------------------------------------------

  /// Requests the CSS2 stylesheet with a User-Agent old enough that Google
  /// Fonts responds with TTF URLs (modern UAs get woff2, which Flutter's
  /// FontLoader doesn't accept).
  static const _ttfUserAgent =
      'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.10) '
      'Gecko/2009042523 Ubuntu/9.04 (jaunty) Firefox/3.0.10';

  Future<Map<int, String>> _resolveTtfUrls(
    String family,
    List<int> weights,
  ) async {
    final fam = Uri.encodeComponent(family).replaceAll('%20', '+');
    final weightAxis = weights.join(';');
    final url = 'https://fonts.googleapis.com/css2?'
        'family=$fam:wght@$weightAxis&display=swap';

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _ttfUserAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw StateError('Google Fonts CSS2 returned HTTP ${res.statusCode} '
            'for $family (weights: $weights)');
      }
      final css = await res.transform(utf8.decoder).join();
      return _parseCssForTtfUrls(css, weights);
    } finally {
      client.close(force: true);
    }
  }

  /// Parses CSS @font-face blocks, mapping `font-weight: N` to the `url(...)`
  /// of the `.ttf` src. Only returns entries whose weight is in the requested
  /// set (Google sometimes returns adjacent weights).
  Map<int, String> _parseCssForTtfUrls(String css, List<int> requested) {
    final out = <int, String>{};
    final blockRe = RegExp(
      r'@font-face\s*\{([^}]*)\}',
      multiLine: true,
      dotAll: true,
    );
    final weightRe = RegExp(r'font-weight:\s*(\d+)');
    final urlRe = RegExp(r'url\(([^)]+\.ttf)\)');
    for (final m in blockRe.allMatches(css)) {
      final body = m.group(1) ?? '';
      final wM = weightRe.firstMatch(body);
      final uM = urlRe.firstMatch(body);
      if (wM == null || uM == null) continue;
      final w = int.parse(wM.group(1)!);
      final u = uM.group(1)!.trim();
      if (requested.contains(w) && !out.containsKey(w)) {
        out[w] = u;
      }
    }
    return out;
  }

  Future<List<int>> _fetchBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _ttfUserAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw StateError('HTTP ${res.statusCode} fetching $url');
      }
      final out = <int>[];
      await for (final chunk in res) {
        out.addAll(chunk);
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }

  static String _weightName(int w) {
    switch (w) {
      case 100:
        return 'Thin';
      case 200:
        return 'ExtraLight';
      case 300:
        return 'Light';
      case 400:
        return 'Regular';
      case 500:
        return 'Medium';
      case 600:
        return 'SemiBold';
      case 700:
        return 'Bold';
      case 800:
        return 'ExtraBold';
      case 900:
        return 'Black';
      default:
        return w.toString();
    }
  }

  // ---------------------------------------------------------------------------
  // pubspec.yaml font declaration (only for --dest=assets/fonts)
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _upsertPubspecFonts({
    required String pubspecPath,
    required Map<String, Set<int>> merged,
    required String dest,
  }) {
    final file = File(pubspecPath);
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    // loadPrintWidgetFonts already scans assets/fonts/ as fallback, so the
    // pubspec block is only needed when the consumer wants fonts available
    // in app runtime (not just tests). Append — do not rewrite.
    final block = StringBuffer()
      ..writeln('# Added by print_widget fonts sync:')
      ..writeln('flutter:')
      ..writeln('  fonts:');
    for (final entry in merged.entries) {
      block.writeln('    - family: ${entry.key}');
      block.writeln('      fonts:');
      final weights = entry.value.toList()..sort();
      for (final w in weights) {
        block.writeln('        - asset: $dest/${entry.key}-${_weightName(w)}.ttf');
        if (w != 400) block.writeln('          weight: $w');
      }
    }
    if (content.contains('# Added by print_widget fonts sync:')) {
      return {'action': 'skipped', 'reason': 'already present'};
    }
    file.writeAsStringSync('$content\n${block.toString()}');
    return {
      'action': 'appended',
      'families': merged.keys.toList(),
    };
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  void _emit(Map<String, dynamic> result, bool jsonMode, {String? error}) {
    if (error != null) {
      (result['errors'] as List).add(error);
    }
    if (jsonMode) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
      return;
    }

    final downloads = (result['downloads'] as List).cast<Map<String, dynamic>>();
    final skipped = (result['skipped'] as List).cast<Map<String, dynamic>>();
    final errors = (result['errors'] as List).cast<String>();
    final reports = (result['reports'] as List).cast<String>();

    if (reports.isNotEmpty) {
      stdout.writeln(
        'print_widget fonts: merged ${reports.length} report(s)',
      );
    }
    for (final d in downloads) {
      final status = d['status'];
      final icon = status == 'downloaded' ? '✓' : '·';
      final bytes = d['bytes'];
      final tail = bytes != null ? ' ($bytes bytes)' : '';
      stdout.writeln('$icon ${d['family']} ${d['weight']} → ${d['file']}$tail');
    }
    for (final s in skipped) {
      stdout.writeln('· ${s['family']} ${s['weight']} → ${s['file']}: '
          '${s['reason']}');
    }
    for (final e in errors) {
      stderr.writeln('✗ $e');
    }
    if (result['pubspecUpdated'] != null) {
      stdout.writeln('pubspec.yaml: ${result['pubspecUpdated']}');
    }
    stdout.writeln('\nfonts: ${downloads.length} download(s), '
        '${skipped.length} skipped, ${errors.length} error(s).');
  }
}
