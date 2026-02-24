import 'dart:convert';

/// A single entry in the screenshot manifest.
///
/// Each entry describes one generated PNG: its name, type, file path,
/// device used, and the logical/physical dimensions.
class PrintManifestEntry {
  /// Creates a manifest entry.
  const PrintManifestEntry({
    required this.name,
    required this.type,
    required this.file,
    required this.device,
    required this.width,
    required this.height,
    required this.widthPx,
    required this.heightPx,
    this.state,
  });

  /// The entry name (matches [PrintEntry.name]).
  final String name;

  /// Either `'page'` or `'widget'`.
  final String type;

  /// Relative path to the generated PNG file.
  final String file;

  /// Device name used for rendering.
  final String device;

  /// Logical width in density-independent pixels.
  final double width;

  /// Logical height in density-independent pixels.
  final double height;

  /// Physical width in pixels (`width * pixelRatio`).
  final int widthPx;

  /// Physical height in pixels (`height * pixelRatio`).
  final int heightPx;

  /// The state name, if this entry was generated from a grouped state.
  final String? state;

  /// Converts this entry to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (state != null) 'state': state,
        'file': file,
        'device': device,
        'width': width,
        'height': height,
        'widthPx': widthPx,
        'heightPx': heightPx,
      };
}

/// The full manifest generated alongside screenshots.
///
/// Contains a timestamp and a list of all [PrintManifestEntry] items.
/// Designed for LLM consumption — the manifest tells the LLM where each
/// screenshot is and what it contains.
class PrintManifest {
  /// Creates a manifest with the given timestamp and entries.
  PrintManifest({
    required this.generatedAt,
    required this.screenshots,
  });

  /// When the screenshots were generated.
  final DateTime generatedAt;

  /// All screenshot entries in this manifest.
  final List<PrintManifestEntry> screenshots;

  /// Converts this manifest to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'screenshots': screenshots.map((e) => e.toJson()).toList(),
      };

  /// Returns a pretty-printed JSON string of this manifest.
  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}
