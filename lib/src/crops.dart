import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A named rectangular region to extract from a screenshot, in logical pixels.
class CropRegion {
  const CropRegion({
    required this.name,
    required this.rect,
  });

  /// Name used to derive the crop filename (e.g. 'header' → 'header.png').
  final String name;

  /// Region to extract, in **logical pixels** relative to the full screenshot.
  final ui.Rect rect;
}

/// Loads crop regions from a JSON file.
///
/// Accepts the `_index.json` format produced by the `smart-extract-design`
/// skill:
///
/// ```json
/// [
///   { "file": "01-header.png", "x": 0, "y": 0, "w": 1440, "h": 80 },
///   { "file": "02-cards.png",  "x": 60, "y": 80, "w": 1320, "h": 350 }
/// ]
/// ```
///
/// The crop name is derived from `file` by stripping the extension. If the
/// file contains only a single object (not a list), it's wrapped into a
/// single-element list.
///
/// Throws [FileSystemException] if the file is missing and [FormatException]
/// if the JSON shape is invalid.
List<CropRegion> loadCropsFromJson(String jsonPath) {
  final file = File(jsonPath);
  if (!file.existsSync()) {
    throw FileSystemException('Crops file not found', jsonPath);
  }
  final raw = jsonDecode(file.readAsStringSync());
  final list = raw is List ? raw : [raw];
  final regions = <CropRegion>[];
  for (final entry in list) {
    if (entry is! Map) {
      throw FormatException('Expected object in crops JSON, got ${entry.runtimeType}');
    }
    final file = entry['file'];
    final x = entry['x'];
    final y = entry['y'];
    final w = entry['w'] ?? entry['width'];
    final h = entry['h'] ?? entry['height'];
    if (file is! String || x is! num || y is! num || w is! num || h is! num) {
      throw FormatException('Invalid crop entry: $entry');
    }
    final name = p.basenameWithoutExtension(file);
    regions.add(
      CropRegion(
        name: name,
        rect: ui.Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          w.toDouble(),
          h.toDouble(),
        ),
      ),
    );
  }
  return regions;
}

/// Converts a `Map<String, Rect>` into the list form used internally.
List<CropRegion> cropsFromMap(Map<String, ui.Rect> crops) {
  return crops.entries
      .map((e) => CropRegion(name: e.key, rect: e.value))
      .toList();
}

/// Crops a source PNG into per-region PNGs.
///
/// Reads [sourcePngPath], extracts each [regions] entry at the given
/// [pixelRatio] (logical-to-physical conversion), and writes each crop to
/// `<outputDir>/<name>.png`.
///
/// Rects that extend beyond the image bounds are clamped. Zero-area regions
/// after clamping are skipped with a warning printed to stderr.
///
/// Returns the list of successfully written file paths.
Future<List<String>> writeCropsToDisk({
  required String sourcePngPath,
  required List<CropRegion> regions,
  required String outputDir,
  required double pixelRatio,
}) async {
  final source = File(sourcePngPath);
  if (!source.existsSync()) {
    throw FileSystemException('Source PNG not found', sourcePngPath);
  }
  final bytes = await source.readAsBytes();
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    throw FormatException('Failed to decode PNG: $sourcePngPath');
  }

  await Directory(outputDir).create(recursive: true);

  final written = <String>[];
  for (final region in regions) {
    // Convert logical pixels to physical pixels.
    final physX = (region.rect.left * pixelRatio).round();
    final physY = (region.rect.top * pixelRatio).round();
    final physW = (region.rect.width * pixelRatio).round();
    final physH = (region.rect.height * pixelRatio).round();

    // Clamp to image bounds.
    final clampedX = physX.clamp(0, decoded.width - 1);
    final clampedY = physY.clamp(0, decoded.height - 1);
    final clampedW = (physX + physW).clamp(0, decoded.width) - clampedX;
    final clampedH = (physY + physH).clamp(0, decoded.height) - clampedY;

    if (clampedW <= 0 || clampedH <= 0) {
      stderr.writeln(
        '  ⚠ crop "${region.name}" is entirely outside image bounds — skipped',
      );
      continue;
    }

    final cropped = img.copyCrop(
      decoded,
      x: clampedX,
      y: clampedY,
      width: clampedW,
      height: clampedH,
    );
    final outPath = p.join(outputDir, '${region.name}.png');
    await File(outPath).writeAsBytes(img.encodePng(cropped));
    written.add(outPath);
  }
  return written;
}

/// Convenience: resolves an entry's crops (inline or from JSON) and writes
/// them to `<goldenDir>/crops/` next to the golden PNG.
///
/// Returns the output directory where crops were written, or null if the
/// entry has no crops defined.
Future<String?> processEntryCrops({
  required String goldenPath,
  required Map<String, ui.Rect>? inlineCrops,
  required String? cropsFromJson,
  required double pixelRatio,
  String cropSubdir = 'crops',
}) async {
  List<CropRegion> regions;
  if (cropsFromJson != null && cropsFromJson.isNotEmpty) {
    regions = loadCropsFromJson(cropsFromJson);
  } else if (inlineCrops != null && inlineCrops.isNotEmpty) {
    regions = cropsFromMap(inlineCrops);
  } else {
    return null;
  }
  if (regions.isEmpty) return null;

  final goldenDir = p.dirname(goldenPath);
  final outputDir = p.join(goldenDir, cropSubdir);
  await writeCropsToDisk(
    sourcePngPath: goldenPath,
    regions: regions,
    outputDir: outputDir,
    pixelRatio: pixelRatio,
  );
  return outputDir;
}
