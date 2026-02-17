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
    this.state,
  });

  final String name;
  final String type;
  final String file;
  final String device;
  final double width;
  final double height;
  final int widthPx;
  final int heightPx;
  final String? state;

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
