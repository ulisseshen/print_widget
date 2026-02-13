import 'dart:convert';

class PrintManifestEntry {
  const PrintManifestEntry({
    required this.name,
    required this.type,
    required this.file,
    required this.device,
    required this.width,
    required this.height,
    required this.widthPx,
    required this.heightPx,
  });

  final String name;
  final String type;
  final String file;
  final String device;
  final double width;
  final double height;
  final int widthPx;
  final int heightPx;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'file': file,
        'device': device,
        'width': width,
        'height': height,
        'widthPx': widthPx,
        'heightPx': heightPx,
      };
}

class PrintManifest {
  PrintManifest({
    required this.generatedAt,
    required this.screenshots,
  });

  final DateTime generatedAt;
  final List<PrintManifestEntry> screenshots;

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'screenshots': screenshots.map((e) => e.toJson()).toList(),
      };

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}
