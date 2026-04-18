import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget_flutter/src/codegen/figma_to_spec.dart';

/// Unit tests for the Figma MCP → spec v1 adapter (Phase 7).
///
/// Each test exercises a single normalization rule in isolation. The
/// integration test suite drives the full pipeline against the
/// `test/codegen/figma_fixtures/*.mcp.json` fixtures.
void main() {
  group('figmaToSpec — envelope shape', () {
    test('emits \$version + source.extractor = figma_to_spec', () {
      final out = figmaToSpec(_frame());
      expect(out[r'$version'], '1.0');
      expect((out['source'] as Map)['extractor'], 'figma_to_spec');
    });

    test('source.state defaults to root name; overridden by option', () {
      final a = figmaToSpec(_frame(name: 'KpiCard'));
      expect((a['source'] as Map)['state'], 'KpiCard');

      final b = figmaToSpec(
        _frame(name: 'KpiCard'),
        options: const FigmaToSpecOptions(stateName: 'custom-label'),
      );
      expect((b['source'] as Map)['state'], 'custom-label');
    });

    test('crop.file defaults to slug of root name; overridden by option', () {
      final a = figmaToSpec(_frame(name: 'KPI Card'));
      expect((a['crop'] as Map)['file'], 'kpi-card.png');

      final b = figmaToSpec(
        _frame(name: 'KPI Card'),
        options: const FigmaToSpecOptions(cropFileName: 'custom.png'),
      );
      expect((b['crop'] as Map)['file'], 'custom.png');
    });

    test('crop.bounds uses viewport-absolute coords', () {
      final out = figmaToSpec(_frame(x: 100, y: 200, w: 320, h: 180));
      expect((out['crop'] as Map)['bounds'],
          {'x': 100, 'y': 200, 'w': 320, 'h': 180});
    });

    test('source.url carries the --source-url option', () {
      final out = figmaToSpec(
        _frame(),
        options: const FigmaToSpecOptions(sourceUrl: 'https://figma.com/x'),
      );
      expect((out['source'] as Map)['url'], 'https://figma.com/x');
    });

    test('throws when no recognizable Figma node is present', () {
      expect(() => figmaToSpec({'random': 'junk'}), throwsArgumentError);
    });
  });

  group('figmaToSpec — color normalization', () {
    test('SOLID fill: 0-1 floats → rgb() ints', () {
      final node = _frame(fills: [
        {
          'type': 'SOLID',
          'color': {'r': 0.043, 'g': 0.635, 'b': 0.514, 'a': 1},
        }
      ]);
      final spec = figmaToSpec(node);
      final styles = _rootStyles(spec);
      expect(styles['backgroundColor'], 'rgb(11, 162, 131)');
    });

    test('SOLID fill with alpha < 1 → rgba() with 2-decimal alpha', () {
      final node = _frame(fills: [
        {
          'type': 'SOLID',
          'color': {'r': 1, 'g': 1, 'b': 1, 'a': 0.7},
        }
      ]);
      expect(
        _rootStyles(figmaToSpec(node))['backgroundColor'],
        'rgba(255, 255, 255, 0.7)',
      );
    });

    test('fill.opacity multiplies with color.a', () {
      final node = _frame(fills: [
        {
          'type': 'SOLID',
          'color': {'r': 0, 'g': 0, 'b': 0, 'a': 1},
          'opacity': 0.5,
        }
      ]);
      expect(
        _rootStyles(figmaToSpec(node))['backgroundColor'],
        'rgba(0, 0, 0, 0.5)',
      );
    });

    test('fully transparent fill is omitted', () {
      final node = _frame(fills: [
        {
          'type': 'SOLID',
          'color': {'r': 1, 'g': 0, 'b': 0, 'a': 0},
        }
      ]);
      final styles = _rootStyles(figmaToSpec(node));
      expect(styles.containsKey('backgroundColor'), isFalse);
    });

    test('fill with visible:false is skipped', () {
      final node = _frame(fills: [
        {
          'type': 'SOLID',
          'visible': false,
          'color': {'r': 1, 'g': 0, 'b': 0, 'a': 1},
        },
        {
          'type': 'SOLID',
          'color': {'r': 0, 'g': 1, 'b': 0, 'a': 1},
        }
      ]);
      expect(
        _rootStyles(figmaToSpec(node))['backgroundColor'],
        'rgb(0, 255, 0)',
      );
    });

    test('GRADIENT_LINEAR with handles emits linear-gradient CSS', () {
      final node = _frame(fills: [
        {
          'type': 'GRADIENT_LINEAR',
          'gradientHandlePositions': [
            {'x': 0, 'y': 0},
            {'x': 1, 'y': 1},
          ],
          'gradientStops': [
            {
              'position': 0,
              'color': {'r': 0, 'g': 0, 'b': 0, 'a': 1},
            },
            {
              'position': 1,
              'color': {'r': 1, 'g': 1, 'b': 1, 'a': 1},
            },
          ],
        }
      ]);
      final styles = _rootStyles(figmaToSpec(node));
      expect(
        styles['backgroundImage'],
        matches(r'^linear-gradient\(\d+(\.\d+)?deg, rgb\(0, 0, 0\) 0%, rgb\(255, 255, 255\) 100%\)$'),
      );
    });

    test('GRADIENT_RADIAL falls back to first stop solid color', () {
      final node = _frame(fills: [
        {
          'type': 'GRADIENT_RADIAL',
          'gradientStops': [
            {
              'color': {'r': 0.2, 'g': 0.4, 'b': 0.6, 'a': 1},
            },
          ],
        }
      ]);
      final styles = _rootStyles(figmaToSpec(node));
      expect(styles['backgroundColor'], 'rgb(51, 102, 153)');
      expect(styles.containsKey('backgroundImage'), isFalse);
    });
  });

  group('figmaToSpec — corner radius', () {
    test('uniform cornerRadius → number', () {
      final node = _frame(extra: {'cornerRadius': 16});
      expect(_rootStyles(figmaToSpec(node))['borderRadius'], 16);
    });

    test('rectangleCornerRadii with all-equal corners → single number', () {
      final node = _frame(extra: {
        'rectangleCornerRadii': [8, 8, 8, 8],
      });
      expect(_rootStyles(figmaToSpec(node))['borderRadius'], 8);
    });

    test('mixed rectangleCornerRadii → object with 4 corners', () {
      final node = _frame(extra: {
        'rectangleCornerRadii': [8, 16, 4, 2],
      });
      expect(_rootStyles(figmaToSpec(node))['borderRadius'], {
        'topLeft': 8,
        'topRight': 16,
        'bottomRight': 4,
        'bottomLeft': 2,
      });
    });

    test('square-ish shape with radius >= half-side → "50%"', () {
      // 20x20 with cornerRadius 10 (= half side) → circle.
      final node = _frame(
        x: 0,
        y: 0,
        w: 20,
        h: 20,
        extra: {'cornerRadius': 10},
      );
      expect(_rootStyles(figmaToSpec(node))['borderRadius'], '50%');
    });

    test('large radius (9999) on square → "50%"', () {
      final node = _frame(
        x: 0,
        y: 0,
        w: 20,
        h: 20,
        extra: {'cornerRadius': 9999},
      );
      expect(_rootStyles(figmaToSpec(node))['borderRadius'], '50%');
    });

    test('large radius on non-square rectangle → numeric radius preserved', () {
      // Pill shape: 64x24, radius 9999 — spec preserves the raw number (the
      // scaffold generator decides it means "pill" based on the value).
      final node = _frame(
        x: 0,
        y: 0,
        w: 64,
        h: 24,
        extra: {'cornerRadius': 9999},
      );
      expect(_rootStyles(figmaToSpec(node))['borderRadius'], 9999);
    });
  });

  group('figmaToSpec — drop shadow composition', () {
    test('single DROP_SHADOW → boxShadow CSS string', () {
      final node = _frame(extra: {
        'effects': [
          {
            'type': 'DROP_SHADOW',
            'color': {'r': 0, 'g': 0, 'b': 0, 'a': 0.1},
            'offset': {'x': 0, 'y': 1},
            'radius': 3,
          }
        ]
      });
      expect(
        _rootStyles(figmaToSpec(node))['boxShadow'],
        '0px 1px 3px rgba(0, 0, 0, 0.1)',
      );
    });

    test('multiple drop shadows → comma-joined', () {
      final node = _frame(extra: {
        'effects': [
          {
            'type': 'DROP_SHADOW',
            'color': {'r': 0, 'g': 0, 'b': 0, 'a': 0.1},
            'offset': {'x': 0, 'y': 1},
            'radius': 3,
          },
          {
            'type': 'DROP_SHADOW',
            'color': {'r': 0, 'g': 0, 'b': 0, 'a': 0.06},
            'offset': {'x': 0, 'y': 4},
            'radius': 8,
          },
        ]
      });
      expect(
        _rootStyles(figmaToSpec(node))['boxShadow'],
        '0px 1px 3px rgba(0, 0, 0, 0.1), 0px 4px 8px rgba(0, 0, 0, 0.06)',
      );
    });

    test('INNER_SHADOW composes with inset prefix', () {
      final node = _frame(extra: {
        'effects': [
          {
            'type': 'INNER_SHADOW',
            'color': {'r': 0, 'g': 0, 'b': 0, 'a': 0.2},
            'offset': {'x': 0, 'y': 2},
            'radius': 4,
          }
        ]
      });
      expect(
        _rootStyles(figmaToSpec(node))['boxShadow'],
        'inset 0px 2px 4px rgba(0, 0, 0, 0.2)',
      );
    });

    test('LAYER_BLUR and invisible effects are skipped', () {
      final node = _frame(extra: {
        'effects': [
          {
            'type': 'LAYER_BLUR',
            'radius': 4,
          },
          {
            'type': 'DROP_SHADOW',
            'visible': false,
            'color': {'r': 0, 'g': 0, 'b': 0, 'a': 0.5},
            'offset': {'x': 0, 'y': 1},
            'radius': 1,
          },
        ]
      });
      final styles = _rootStyles(figmaToSpec(node));
      expect(styles.containsKey('boxShadow'), isFalse);
    });
  });

  group('figmaToSpec — typography', () {
    test('lineHeightPercent → px conversion using fontSize', () {
      final node = _frame(children: [
        {
          'type': 'TEXT',
          'name': 't',
          'characters': 'Hi',
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 20, 'height': 12},
          'style': {
            'fontFamily': 'Inter',
            'fontSize': 12,
            'fontWeight': 400,
            'lineHeightPercent': 150,
          },
          'fills': [
            {
              'type': 'SOLID',
              'color': {'r': 0, 'g': 0, 'b': 0, 'a': 1},
            }
          ],
        }
      ]);
      final typ = _firstChildTypography(figmaToSpec(node));
      expect(typ['lineHeight'], 18);
    });

    test('textAlign LEFT is omitted, CENTER/RIGHT/JUSTIFIED are lowercased', () {
      for (final pair in const [
        ['LEFT', null],
        ['CENTER', 'center'],
        ['RIGHT', 'right'],
        ['JUSTIFIED', 'justified'],
      ]) {
        final node = _frame(children: [
          _text(text: 'x', textAlignHorizontal: pair[0]),
        ]);
        final typ = _firstChildTypography(figmaToSpec(node));
        if (pair[1] == null) {
          expect(typ.containsKey('textAlign'), isFalse,
              reason: 'LEFT should omit textAlign');
        } else {
          expect(typ['textAlign'], pair[1],
              reason: 'case ${pair[0]}');
        }
      }
    });

    test('textCase UPPER/LOWER/TITLE → textTransform; NONE omitted', () {
      final cases = {
        'UPPER': 'uppercase',
        'LOWER': 'lowercase',
        'TITLE': 'capitalize',
      };
      cases.forEach((figma, css) {
        final node = _frame(children: [
          _text(text: 'x', textCase: figma),
        ]);
        expect(
          _firstChildTypography(figmaToSpec(node))['textTransform'],
          css,
          reason: 'case $figma',
        );
      });

      final node = _frame(children: [_text(text: 'x', textCase: 'NONE')]);
      expect(
        _firstChildTypography(figmaToSpec(node)).containsKey('textTransform'),
        isFalse,
      );
    });

    test('text longer than 500 chars is clipped', () {
      final long = 'a' * 800;
      final node = _frame(children: [_text(text: long)]);
      final span = _firstChild(figmaToSpec(node));
      expect((span['text'] as String).length, 500);
    });

    test('letterSpacing is omitted when zero', () {
      final node = _frame(children: [_text(text: 'hi')]);
      final typ = _firstChildTypography(figmaToSpec(node));
      expect(typ.containsKey('letterSpacing'), isFalse);
    });
  });

  group('figmaToSpec — layout mapping', () {
    test('VERTICAL → display:flex + flexDirection:column', () {
      final out = figmaToSpec(_frame(extra: {'layoutMode': 'VERTICAL'}));
      final styles = _rootStyles(out);
      expect(styles['display'], 'flex');
      expect(styles['flexDirection'], 'column');
    });

    test('HORIZONTAL → display:flex (row default, omitted)', () {
      final out = figmaToSpec(_frame(extra: {'layoutMode': 'HORIZONTAL'}));
      final styles = _rootStyles(out);
      expect(styles['display'], 'flex');
      expect(styles.containsKey('flexDirection'), isFalse);
    });

    test('NONE + children → parent styles.position = relative', () {
      final node = _frame(extra: {
        'layoutMode': 'NONE',
      }, children: [
        _text(text: 'child'),
      ]);
      final styles = _rootStyles(figmaToSpec(node));
      expect(styles['position'], 'relative');
    });

    test('NONE + child → child styles carry absolute + top/left', () {
      final node = {
        'type': 'FRAME',
        'name': 'root',
        'layoutMode': 'NONE',
        'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 200, 'height': 100},
        'children': [
          {
            'type': 'RECTANGLE',
            'name': 'badge',
            'absoluteBoundingBox': {'x': 170, 'y': 10, 'width': 20, 'height': 20},
            'cornerRadius': 9999,
            'fills': [
              {
                'type': 'SOLID',
                'color': {'r': 1, 'g': 0, 'b': 0, 'a': 1},
              }
            ],
          }
        ],
      };
      final spec = figmaToSpec(node.cast<String, dynamic>());
      final child = ((spec['root'] as Map)['children'] as List).first as Map;
      final styles = (child['styles'] as Map).cast<String, dynamic>();
      expect(styles['position'], 'absolute');
      expect(styles['left'], '170px');
      expect(styles['top'], '10px');
    });
  });

  group('figmaToSpec — align mapping', () {
    test('primaryAxisAlignItems: MIN/CENTER/MAX/SPACE_BETWEEN', () {
      final cases = <String, String>{
        'MIN': 'flex-start',
        'CENTER': 'center',
        'MAX': 'flex-end',
        'SPACE_BETWEEN': 'space-between',
      };
      cases.forEach((figma, css) {
        final node = _frame(extra: {
          'layoutMode': 'VERTICAL',
          'primaryAxisAlignItems': figma,
        });
        expect(
          _rootStyles(figmaToSpec(node))['justifyContent'],
          css,
          reason: 'case $figma',
        );
      });
    });

    test('counterAxisAlignItems: MIN/CENTER/MAX/STRETCH', () {
      final cases = <String, String>{
        'MIN': 'flex-start',
        'CENTER': 'center',
        'MAX': 'flex-end',
        'STRETCH': 'stretch',
      };
      cases.forEach((figma, css) {
        final node = _frame(extra: {
          'layoutMode': 'VERTICAL',
          'counterAxisAlignItems': figma,
        });
        expect(
          _rootStyles(figmaToSpec(node))['alignItems'],
          css,
          reason: 'case $figma',
        );
      });
    });
  });

  group('figmaToSpec — icon detection', () {
    test('INSTANCE "Lucide/DollarSign" → icon.library=lucide, kebab name', () {
      final node = _frame(children: [
        {
          'type': 'INSTANCE',
          'name': 'Lucide/DollarSign',
          'mainComponent': {'name': 'Lucide/DollarSign'},
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 20, 'height': 20},
        }
      ]);
      final child = _firstChild(figmaToSpec(node));
      expect(child['tag'], 'svg');
      expect(child['icon'], {'library': 'lucide', 'name': 'dollar-sign'});
    });

    test('INSTANCE "Phosphor/House" → phosphor + kebab name', () {
      final node = _frame(children: [
        {
          'type': 'INSTANCE',
          'name': 'Phosphor/House',
          'mainComponent': {'name': 'Phosphor/House'},
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 20, 'height': 20},
        }
      ]);
      expect(_firstChild(figmaToSpec(node))['icon'],
          {'library': 'phosphor', 'name': 'house'});
    });

    test('INSTANCE "Heroicon/Bell" → heroicons', () {
      final node = _frame(children: [
        {
          'type': 'INSTANCE',
          'name': 'Heroicon/Bell',
          'mainComponent': {'name': 'Heroicon/Bell'},
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 20, 'height': 20},
        }
      ]);
      expect(_firstChild(figmaToSpec(node))['icon'],
          {'library': 'heroicons', 'name': 'bell'});
    });

    test('INSTANCE name case-insensitive on library prefix', () {
      final node = _frame(children: [
        {
          'type': 'INSTANCE',
          'name': 'lucide/user',
          'mainComponent': {'name': 'lucide/user'},
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 20, 'height': 20},
        }
      ]);
      expect(_firstChild(figmaToSpec(node))['icon'],
          {'library': 'lucide', 'name': 'user'});
    });

    test('VECTOR under 64x64 → unknown library + kebab(name)', () {
      final node = _frame(children: [
        {
          'type': 'VECTOR',
          'name': 'DeltaUp Arrow',
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 16, 'height': 16},
        }
      ]);
      expect(_firstChild(figmaToSpec(node))['icon'],
          {'library': 'unknown', 'name': 'delta-up-arrow'});
    });

    test('VECTOR over 64x64 — not treated as icon (no icon emitted)', () {
      final node = _frame(children: [
        {
          'type': 'VECTOR',
          'name': 'BigVector',
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 200, 'height': 200},
        }
      ]);
      final child = _firstChild(figmaToSpec(node));
      expect(child.containsKey('icon'), isFalse);
    });
  });

  group('figmaToSpec — bounds relativization', () {
    test('child bounds are root-relative, not viewport-absolute', () {
      // Root at (100, 200); child at (120, 220) → child bounds (20, 20).
      final node = _frame(x: 100, y: 200, w: 320, h: 180, children: [
        _text(
          text: 'Hello',
          x: 120,
          y: 220,
          w: 150,
          h: 20,
        ),
      ]);
      final child = _firstChild(figmaToSpec(node));
      final bounds = (child['bounds'] as Map).cast<String, dynamic>();
      expect(bounds['x'], 20);
      expect(bounds['y'], 20);
      expect(bounds['w'], 150);
      expect(bounds['h'], 20);
    });
  });

  group('figmaToSpec — skipping invisible / zero-sized nodes', () {
    test('visible:false on child is dropped', () {
      final node = _frame(children: [
        {
          'type': 'TEXT',
          'name': 'x',
          'characters': 'hidden',
          'visible': false,
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 10, 'height': 10},
          'style': {'fontFamily': 'Inter', 'fontSize': 12, 'fontWeight': 400},
          'fills': [
            {
              'type': 'SOLID',
              'color': {'r': 0, 'g': 0, 'b': 0, 'a': 1},
            }
          ],
        }
      ]);
      final root = figmaToSpec(node)['root'] as Map;
      expect(root['children'], isNull,
          reason: 'children key omitted entirely when no visible kids');
    });

    test('zero-width child is dropped', () {
      final node = _frame(children: [
        {
          'type': 'RECTANGLE',
          'name': 'empty',
          'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 0, 'height': 10},
        }
      ]);
      final root = figmaToSpec(node)['root'] as Map;
      expect(root['children'], isNull);
    });
  });

  group('figmaToSpec — idempotency', () {
    test('running twice on the same input produces identical maps', () {
      final input = _frame(
        fills: [
          {
            'type': 'SOLID',
            'color': {'r': 1, 'g': 1, 'b': 1, 'a': 0.7},
          }
        ],
        extra: {'cornerRadius': 16, 'layoutMode': 'VERTICAL'},
        children: [_text(text: 'Hi')],
      );
      final a = figmaToSpec(input);
      final b = figmaToSpec(input);
      // Both maps should JSON-serialize to the same thing.
      expect(a, equals(b));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a basic FRAME with sane defaults. Extra keys may override / add.
Map<String, dynamic> _frame({
  String name = 'Frame',
  double x = 0,
  double y = 0,
  double w = 100,
  double h = 100,
  List<dynamic>? fills,
  List<dynamic>? children,
  Map<String, dynamic>? extra,
}) {
  final m = <String, dynamic>{
    'type': 'FRAME',
    'name': name,
    'absoluteBoundingBox': {'x': x, 'y': y, 'width': w, 'height': h},
    'fills': fills ?? const [],
    'visible': true,
  };
  if (children != null) m['children'] = children;
  if (extra != null) m.addAll(extra);
  return m;
}

Map<String, dynamic> _text({
  required String text,
  double x = 0,
  double y = 0,
  double w = 100,
  double h = 20,
  String? textAlignHorizontal,
  String? textCase,
}) {
  return <String, dynamic>{
    'type': 'TEXT',
    'name': 'text',
    'characters': text,
    'absoluteBoundingBox': {'x': x, 'y': y, 'width': w, 'height': h},
    'style': <String, dynamic>{
      'fontFamily': 'Inter',
      'fontSize': 14,
      'fontWeight': 500,
      'lineHeightPx': 20,
      if (textAlignHorizontal != null)
        'textAlignHorizontal': textAlignHorizontal,
      if (textCase != null) 'textCase': textCase,
    },
    'fills': [
      {
        'type': 'SOLID',
        'color': {'r': 0, 'g': 0, 'b': 0, 'a': 1},
      }
    ],
  };
}

Map<String, dynamic> _rootStyles(Map<String, dynamic> spec) {
  final root = spec['root'] as Map;
  final styles = root['styles'];
  if (styles is Map) return styles.cast<String, dynamic>();
  return <String, dynamic>{};
}

Map<String, dynamic> _firstChild(Map<String, dynamic> spec) {
  final root = spec['root'] as Map;
  final kids = root['children'] as List;
  return (kids.first as Map).cast<String, dynamic>();
}

Map<String, dynamic> _firstChildTypography(Map<String, dynamic> spec) {
  final child = _firstChild(spec);
  final t = child['typography'];
  if (t is Map) return t.cast<String, dynamic>();
  return <String, dynamic>{};
}
