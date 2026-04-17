import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:print_widget_flutter/src/codegen/scaffold_generator.dart';

void main() {
  group('scaffold_generator — fixtures', () {
    for (final name in ['icon_badge', 'delta_indicator', 'status_badge']) {
      test('$name spec → expected.dart (after dart format)', () async {
        final actual = await _renderFixture(name);
        final expected = _readFixture('$name.expected.dart');
        expect(
          actual.trim(),
          equals(expected.trim()),
          reason: 'Scaffold output for $name does not match '
              'test/codegen/fixtures/$name.expected.dart.\n'
              'Update the fixture if the change is intentional.',
        );
      });
    }

    test('canary fixtures emit zero // TODO markers', () async {
      for (final name in ['icon_badge', 'delta_indicator', 'status_badge']) {
        final specFile = _fixtureFile('$name.spec.json');
        final spec = jsonDecode(specFile.readAsStringSync())
            as Map<String, dynamic>;
        final result = generateScaffold(
          spec,
          ScaffoldGeneratorOptions(
            className: '_X',
            specRelativePath: 'spec.json',
            generatedAt: '2026-04-17T00:00:00.000Z',
            regenerateCommand: 'print_widget scaffold --spec=spec.json',
          ),
        );
        expect(result.todoCount, 0,
            reason: '$name produced ${result.todoCount} TODO(s): ${result.source}');
      }
    });
  });

  group('scaffold_generator — color parsing', () {
    test('rgb(N,N,N) → Color(0xFFRRGGBB)', () {
      final src = _renderSingleColorNode('rgb(11, 162, 132)');
      expect(src, contains('Color(0xFF0BA284)'));
    });

    test('rgba alpha = round(0.12 * 255) = 0x1F (alpha first)', () {
      final src = _renderSingleColorNode('rgba(11, 162, 132, 0.12)');
      expect(src, contains('Color(0x1F0BA284)'));
    });

    test('#RRGGBB → Color(0xFFRRGGBB)', () {
      final src = _renderSingleColorNode('#0BA284');
      expect(src, contains('Color(0xFF0BA284)'));
    });

    test('#RRGGBBAA with 0xFF alpha moves alpha to front', () {
      final src = _renderSingleColorNode('#0BA284FF');
      expect(src, contains('Color(0xFF0BA284)'));
    });

    test('#RRGGBBAA with 50% alpha → Color(0x800BA284)', () {
      final src = _renderSingleColorNode('#0BA28480');
      expect(src, contains('Color(0x800BA284)'));
    });

    test('transparent / rgba(0,0,0,0) → background omitted', () {
      final src1 = _renderSingleColorNode('transparent');
      final src2 = _renderSingleColorNode('rgba(0,0,0,0)');
      expect(src1, isNot(contains('Color(')));
      expect(src2, isNot(contains('Color(')));
    });

    test('never emits Colors.white / Colors.black shortcuts', () {
      final src1 = _renderSingleColorNode('#FFFFFF');
      final src2 = _renderSingleColorNode('#000000');
      expect(src1, contains('Color(0xFFFFFFFF)'));
      expect(src1, isNot(contains('Colors.')));
      expect(src2, contains('Color(0xFF000000)'));
      expect(src2, isNot(contains('Colors.')));
    });
  });

  group('scaffold_generator — EdgeInsets collapsing', () {
    test('all sides equal → EdgeInsets.all(N)', () {
      final src = _renderPaddingNode(top: 12, right: 12, bottom: 12, left: 12);
      expect(src, contains('EdgeInsets.all(12)'));
    });

    test('top==bottom, left==right → EdgeInsets.symmetric', () {
      final src = _renderPaddingNode(top: 4, right: 10, bottom: 4, left: 10);
      expect(src, contains('EdgeInsets.symmetric(horizontal: 10, vertical: 4)'));
    });

    test('asymmetric → EdgeInsets.fromLTRB(l, t, r, b)', () {
      final src = _renderPaddingNode(top: 1, right: 2, bottom: 3, left: 4);
      expect(src, contains('EdgeInsets.fromLTRB(4, 1, 2, 3)'));
    });
  });

  group('scaffold_generator — FontWeight mapping', () {
    test('number 400 → FontWeight.w400', () {
      expect(_renderFontWeight(400), contains('FontWeight.w400'));
    });

    test('number 700 → FontWeight.w700', () {
      expect(_renderFontWeight(700), contains('FontWeight.w700'));
    });

    test('string "bold" → FontWeight.bold', () {
      expect(_renderFontWeight('bold'), contains('FontWeight.bold'));
    });

    test('string "normal" → FontWeight.w400', () {
      expect(_renderFontWeight('normal'), contains('FontWeight.w400'));
    });

    test('snaps 450 → 500', () {
      expect(_renderFontWeight(450), contains('FontWeight.w500'));
    });
  });

  group('scaffold_generator — gap interleaving', () {
    test('Row with gap: 8 → SizedBox(width: 8) between children', () {
      final src = _renderFlex(direction: 'row', gap: 8);
      expect(src, contains('SizedBox(width: 8)'));
      expect(src, isNot(contains('SizedBox(height: 8)')));
    });

    test('Column with gap: 12 → SizedBox(height: 12) between children', () {
      final src = _renderFlex(direction: 'column', gap: 12);
      expect(src, contains('SizedBox(height: 12)'));
      expect(src, isNot(contains('SizedBox(width: 12)')));
    });
  });

  group('scaffold_generator — shape', () {
    test('borderRadius: 50% → BoxShape.circle (no borderRadius emitted)', () {
      final src = _renderSingleColorNodeWithRadius(
        'rgba(11,162,132,0.12)',
        '50%',
      );
      expect(src, contains('shape: BoxShape.circle'));
      expect(src, isNot(contains('borderRadius:')));
    });

    test('borderRadius: 9999 → BorderRadius.circular(9999)', () {
      final src =
          _renderSingleColorNodeWithRadius('rgba(11,162,132,0.12)', 9999);
      expect(src, contains('BorderRadius.circular(9999)'));
      expect(src, isNot(contains('BoxShape.circle')));
    });
  });

  group('scaffold_generator — unknown-node fallback', () {
    test('empty div with bounds emits a fixed-size box', () {
      final spec = <String, dynamic>{
        'root': {
          'tag': 'div',
          'bounds': {'w': 120, 'h': 40},
        },
      };
      final result = generateScaffold(spec, _defaultOptions());
      // A shape-less leaf gets a Container with explicit w/h (SizedBox would
      // also be valid — we accept either).
      expect(
        result.source,
        anyOf(
          contains('SizedBox(width: 120, height: 40)'),
          allOf(contains('width: 120'), contains('height: 40')),
        ),
      );
    });

    test('const is dropped when tree contains SvgPicture.string', () {
      final spec = <String, dynamic>{
        'root': {
          'tag': 'svg',
          'bounds': {'w': 20, 'h': 20},
          'svgHtml': '<svg></svg>',
        },
      };
      final result = generateScaffold(spec, _defaultOptions());
      // Class constructor must NOT be const when SVGs are present.
      expect(result.source, contains('_XScaffold({super.key});'));
      expect(result.source, isNot(contains('const _XScaffold({super.key});')));
      expect(result.hasSvg, isTrue);
    });

    test('const is kept when no SVGs present', () {
      final spec = <String, dynamic>{
        'root': {
          'tag': 'span',
          'text': 'hi',
          'typography': {'fontSize': 12, 'fontWeight': 400},
        },
      };
      final result = generateScaffold(spec, _defaultOptions());
      expect(result.source, contains('const _XScaffold({super.key});'));
    });

    test('file header contains spec path and timestamp', () {
      final spec = <String, dynamic>{
        'root': {'tag': 'div', 'bounds': {'w': 10, 'h': 10}}
      };
      final result = generateScaffold(
        spec,
        ScaffoldGeneratorOptions(
          className: '_XScaffold',
          specRelativePath: 'path/to/foo_spec.json',
          generatedAt: '2026-04-17T12:34:56.000Z',
          regenerateCommand: 'print_widget scaffold --spec=path/to/foo_spec.json',
        ),
      );
      expect(result.source, contains('// AUTO-GENERATED by print_widget scaffold'));
      expect(result.source, contains('// Source spec: path/to/foo_spec.json'));
      expect(result.source, contains('// Generated: 2026-04-17T12:34:56.000Z'));
      expect(
        result.source,
        contains('// Regenerate: print_widget scaffold --spec=path/to/foo_spec.json'),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

File _fixtureFile(String name) {
  final here = File.fromUri(Platform.script).parent;
  // When run via `flutter test` the script is the test runner; reach the
  // fixtures relative to cwd instead.
  final candidates = [
    p.join(Directory.current.path, 'test', 'codegen', 'fixtures', name),
    p.join(here.path, 'fixtures', name),
  ];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f;
  }
  throw StateError('fixture not found: $name (tried: $candidates)');
}

String _readFixture(String name) => _fixtureFile(name).readAsStringSync();

Future<String> _renderFixture(String name) async {
  final specFile = _fixtureFile('$name.spec.json');
  final className = _defaultClass(name);
  final spec =
      jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
  final result = generateScaffold(
    spec,
    ScaffoldGeneratorOptions(
      className: className,
      specRelativePath: 'test/codegen/fixtures/$name.spec.json',
      generatedAt: '2026-04-17T00:00:00.000Z',
      regenerateCommand:
          'print_widget scaffold --spec=test/codegen/fixtures/$name.spec.json',
    ),
  );
  // Strip the header comment block so the fixture doesn't contain a
  // per-run timestamp.
  final stripped = _stripGeneratedHeader(result.source);
  return _dartFormat(stripped);
}

String _defaultClass(String slug) {
  final parts = slug.split('_');
  final pascal = parts
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join();
  return '_${pascal}Scaffold';
}

String _stripGeneratedHeader(String src) {
  final lines = src.split('\n');
  final firstNonComment = lines.indexWhere(
    (l) => !l.startsWith('//') && l.trim().isNotEmpty,
  );
  if (firstNonComment < 0) return src;
  return lines.sublist(firstNonComment).join('\n');
}

Future<String> _dartFormat(String src) async {
  final tmp = await File(
    p.join(
      Directory.systemTemp.createTempSync('pw_fmt_').path,
      'tmp.dart',
    ),
  ).create();
  tmp.writeAsStringSync(src);
  final r = await Process.run('dart', ['format', tmp.path]);
  if (r.exitCode != 0) {
    throw StateError('dart format failed: ${r.stderr}');
  }
  final out = tmp.readAsStringSync();
  try {
    tmp.parent.deleteSync(recursive: true);
  } catch (_) {}
  return out;
}

ScaffoldGeneratorOptions _defaultOptions() {
  return ScaffoldGeneratorOptions(
    className: '_XScaffold',
    specRelativePath: 'spec.json',
    generatedAt: '2026-04-17T00:00:00.000Z',
    regenerateCommand: 'print_widget scaffold --spec=spec.json',
  );
}

String _renderSingleColorNode(String color) {
  final spec = <String, dynamic>{
    'root': {
      'tag': 'div',
      'bounds': {'w': 20, 'h': 20},
      'styles': {'backgroundColor': color},
    },
  };
  return generateScaffold(spec, _defaultOptions()).source;
}

String _renderSingleColorNodeWithRadius(String color, Object radius) {
  final spec = <String, dynamic>{
    'root': {
      'tag': 'div',
      'bounds': {'w': 40, 'h': 40},
      'styles': {'backgroundColor': color, 'borderRadius': radius},
    },
  };
  return generateScaffold(spec, _defaultOptions()).source;
}

String _renderPaddingNode({
  required num top,
  required num right,
  required num bottom,
  required num left,
}) {
  final spec = <String, dynamic>{
    'root': {
      'tag': 'div',
      'bounds': {'w': 100, 'h': 50},
      'styles': {
        'padding': {'top': top, 'right': right, 'bottom': bottom, 'left': left},
        'backgroundColor': '#0BA284',
      },
      'children': [
        {
          'tag': 'span',
          'text': 'x',
          'typography': {'fontSize': 12, 'fontWeight': 400, 'color': '#000000'},
        },
      ],
    },
  };
  return generateScaffold(spec, _defaultOptions()).source;
}

String _renderFontWeight(Object weight) {
  final spec = <String, dynamic>{
    'root': {
      'tag': 'span',
      'text': 'x',
      'typography': {'fontSize': 12, 'fontWeight': weight, 'color': '#000000'},
    },
  };
  return generateScaffold(spec, _defaultOptions()).source;
}

String _renderFlex({required String direction, required num gap}) {
  final spec = <String, dynamic>{
    'root': {
      'tag': 'div',
      'bounds': {'w': 100, 'h': 40},
      'styles': {
        'display': 'flex',
        'flexDirection': direction,
        'gap': gap,
      },
      'children': [
        {
          'tag': 'span',
          'text': 'a',
          'typography': {'fontSize': 12, 'fontWeight': 400, 'color': '#000000'},
        },
        {
          'tag': 'span',
          'text': 'b',
          'typography': {'fontSize': 12, 'fontWeight': 400, 'color': '#000000'},
        },
      ],
    },
  };
  return generateScaffold(spec, _defaultOptions()).source;
}
