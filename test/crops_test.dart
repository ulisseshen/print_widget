import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:print_widget_flutter/print_widget.dart';

void main() {
  group('crops', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pw_crops_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    /// Creates a 200x100 PNG at the given path. Top half is red, bottom half
    /// is blue. Used as a synthetic source for crop extraction.
    File createSourcePng(String path) {
      final image = img.Image(width: 200, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 0, 0)); // full red
      img.fillRect(
        image,
        x1: 0,
        y1: 50,
        x2: 199,
        y2: 99,
        color: img.ColorRgb8(0, 0, 255), // bottom half blue
      );
      final file = File(path);
      file.writeAsBytesSync(img.encodePng(image));
      return file;
    }

    test('writeCropsToDisk extracts regions at pixelRatio=1', () async {
      final source = createSourcePng(p.join(tmpDir.path, 'source.png'));
      final outDir = p.join(tmpDir.path, 'out');

      final written = await writeCropsToDisk(
        sourcePngPath: source.path,
        regions: [
          CropRegion(name: 'top', rect: ui.Rect.fromLTWH(0, 0, 200, 50)),
          CropRegion(name: 'bottom', rect: ui.Rect.fromLTWH(0, 50, 200, 50)),
        ],
        outputDir: outDir,
        pixelRatio: 1.0,
      );

      expect(written.length, 2);
      expect(File(p.join(outDir, 'top.png')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'bottom.png')).existsSync(), isTrue);

      // Verify top crop is red, bottom crop is blue.
      final topBytes = File(p.join(outDir, 'top.png')).readAsBytesSync();
      final topImg = img.decodePng(topBytes)!;
      expect(topImg.width, 200);
      expect(topImg.height, 50);
      final topPixel = topImg.getPixel(100, 25);
      expect(topPixel.r, 255);
      expect(topPixel.g, 0);
      expect(topPixel.b, 0);

      final botBytes = File(p.join(outDir, 'bottom.png')).readAsBytesSync();
      final botImg = img.decodePng(botBytes)!;
      expect(botImg.width, 200);
      expect(botImg.height, 50);
      final botPixel = botImg.getPixel(100, 25);
      expect(botPixel.r, 0);
      expect(botPixel.g, 0);
      expect(botPixel.b, 255);
    });

    test('writeCropsToDisk applies pixelRatio scaling', () async {
      final source = createSourcePng(p.join(tmpDir.path, 'source.png'));
      final outDir = p.join(tmpDir.path, 'out');

      // Source is 200x100 physical. At pixelRatio=2, logical is 100x50.
      // Logical rect (0, 0, 100, 50) → physical (0, 0, 200, 100) — the whole image.
      final written = await writeCropsToDisk(
        sourcePngPath: source.path,
        regions: [
          CropRegion(name: 'full', rect: ui.Rect.fromLTWH(0, 0, 100, 50)),
        ],
        outputDir: outDir,
        pixelRatio: 2.0,
      );

      expect(written.length, 1);
      final fullImg =
          img.decodePng(File(p.join(outDir, 'full.png')).readAsBytesSync())!;
      expect(fullImg.width, 200);
      expect(fullImg.height, 100);
    });

    test('writeCropsToDisk clamps regions that extend beyond bounds', () async {
      final source = createSourcePng(p.join(tmpDir.path, 'source.png'));
      final outDir = p.join(tmpDir.path, 'out');

      // Request a 400x200 region from a 200x100 source — must be clamped.
      final written = await writeCropsToDisk(
        sourcePngPath: source.path,
        regions: [
          CropRegion(name: 'oversize', rect: ui.Rect.fromLTWH(0, 0, 400, 200)),
        ],
        outputDir: outDir,
        pixelRatio: 1.0,
      );

      expect(written.length, 1);
      final clampedImg = img.decodePng(
        File(p.join(outDir, 'oversize.png')).readAsBytesSync(),
      )!;
      expect(clampedImg.width, 200);
      expect(clampedImg.height, 100);
    });

    test('writeCropsToDisk skips regions entirely outside bounds', () async {
      final source = createSourcePng(p.join(tmpDir.path, 'source.png'));
      final outDir = p.join(tmpDir.path, 'out');

      final written = await writeCropsToDisk(
        sourcePngPath: source.path,
        regions: [
          // Well outside 200x100 bounds.
          CropRegion(name: 'offscreen', rect: ui.Rect.fromLTWH(500, 500, 100, 100)),
          CropRegion(name: 'valid', rect: ui.Rect.fromLTWH(0, 0, 50, 50)),
        ],
        outputDir: outDir,
        pixelRatio: 1.0,
      );

      expect(written.length, 1, reason: 'offscreen crop should be skipped');
      expect(File(p.join(outDir, 'offscreen.png')).existsSync(), isFalse);
      expect(File(p.join(outDir, 'valid.png')).existsSync(), isTrue);
    });

    test('loadCropsFromJson parses smart-extract _index.json format', () {
      final jsonPath = p.join(tmpDir.path, '_index.json');
      File(jsonPath).writeAsStringSync('''[
  {"file": "01-header.png", "x": 0, "y": 0, "w": 1440, "h": 80},
  {"file": "02-cards.png", "x": 60, "y": 80, "w": 1320, "h": 350}
]''');

      final regions = loadCropsFromJson(jsonPath);
      expect(regions.length, 2);
      expect(regions[0].name, '01-header');
      expect(regions[0].rect.left, 0);
      expect(regions[0].rect.top, 0);
      expect(regions[0].rect.width, 1440);
      expect(regions[0].rect.height, 80);

      expect(regions[1].name, '02-cards');
      expect(regions[1].rect.left, 60);
      expect(regions[1].rect.top, 80);
      expect(regions[1].rect.width, 1320);
      expect(regions[1].rect.height, 350);
    });

    test('loadCropsFromJson accepts width/height aliases', () {
      final jsonPath = p.join(tmpDir.path, '_index.json');
      File(jsonPath).writeAsStringSync('''[
  {"file": "section.png", "x": 0, "y": 0, "width": 100, "height": 50}
]''');

      final regions = loadCropsFromJson(jsonPath);
      expect(regions.length, 1);
      expect(regions[0].rect.width, 100);
      expect(regions[0].rect.height, 50);
    });

    test('loadCropsFromJson throws on missing file', () {
      expect(
        () => loadCropsFromJson(p.join(tmpDir.path, 'nonexistent.json')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('loadCropsFromJson throws on malformed JSON', () {
      final jsonPath = p.join(tmpDir.path, 'bad.json');
      File(jsonPath).writeAsStringSync('[{"file": 123}]');

      expect(
        () => loadCropsFromJson(jsonPath),
        throwsA(isA<FormatException>()),
      );
    });

    test('processEntryCrops uses cropsFrom over inline crops', () async {
      final source = createSourcePng(p.join(tmpDir.path, 'golden.png'));
      final jsonPath = p.join(tmpDir.path, '_index.json');
      File(jsonPath).writeAsStringSync(
        '[{"file": "from_json.png", "x": 0, "y": 0, "w": 100, "h": 50}]',
      );

      final outDir = await processEntryCrops(
        goldenPath: source.path,
        inlineCrops: {'from_inline': ui.Rect.fromLTWH(0, 0, 200, 100)},
        cropsFromJson: jsonPath,
        pixelRatio: 1.0,
      );

      expect(outDir, isNotNull);
      expect(File(p.join(outDir!, 'from_json.png')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'from_inline.png')).existsSync(), isFalse);
    });

    test('processEntryCrops returns null when no crops defined', () async {
      final source = createSourcePng(p.join(tmpDir.path, 'golden.png'));

      final outDir = await processEntryCrops(
        goldenPath: source.path,
        inlineCrops: null,
        cropsFromJson: null,
        pixelRatio: 1.0,
      );

      expect(outDir, isNull);
    });
  });
}
