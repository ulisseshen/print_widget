import 'package:flutter_test/flutter_test.dart';
import 'package:print_widget_flutter/src/codegen/tokenizer.dart';

/// A minimal theme that exercises every substitution kind.
Map<String, dynamic> _baseTheme() => {
      'name': 'test',
      'colors': {
        'accessor': 'context.customColors',
        'tokenMap': {
          '#0BA284': 'brand30',
          '#0F1729': 'textPrimary',
          '#6B7280': 'textMuted',
        },
      },
      'spacing': {
        'class': 'YHAppSpacing',
        'prefix': 'sp',
        'scale': {
          '0': 0,
          '4': 1,
          '8': 2,
          '12': 3,
          '16': 4,
          '20': 5,
          '40': 10,
        },
      },
      'radius': {
        'class': 'YHAppCornerRadiusV2',
        'prefix': 'r',
        'scale': {
          '4': 1,
          '8': 2,
          '12': 3,
          '16': 4,
          '9999': 'full',
        },
      },
      'typography': {
        'helper': 'interText',
        'import': 'package:yh/inter_text.dart',
      },
    };

TokenizerOptions _opts({
  TokenStrategy strategy = TokenStrategy.exact,
  double tolerance = 2.0,
  Map<String, dynamic>? overrideTheme,
}) =>
    TokenizerOptions(
      theme: overrideTheme ?? _baseTheme(),
      strategy: strategy,
      tolerance: tolerance,
      scaffoldRelativePath: 'scaffold.dart',
    );

void main() {
  group('colors', () {
    test('exact 0xFF match swaps to token accessor', () {
      final src = '''
import 'package:flutter/material.dart';
const c = Color(0xFF0BA284);
''';
      final r = tokenize(src, _opts());
      expect(r.source, contains('context.customColors.brand30'));
      expect(r.source, isNot(contains('Color(0xFF0BA284)')));
      expect(r.substitutions, hasLength(1));
      expect(r.substitutions.first.kind, 'color');
    });

    test('alpha < 0xFF wraps in .withValues(alpha:) with 2-decimal opacity', () {
      // 0x1F = 31 → 31/255 = 0.1215... → rounds to 0.12.
      final src = '''
import 'package:flutter/material.dart';
const c = Color(0x1F0BA284);
''';
      final r = tokenize(src, _opts());
      expect(r.source,
          contains('context.customColors.brand30.withValues(alpha: 0.12)'));
      // Must not emit the deprecated withOpacity.
      expect(r.source, isNot(contains('withOpacity(')));
    });

    test('no token match emits FORCE comment and preserves literal', () {
      final src = '''
import 'package:flutter/material.dart';
const c = Color(0xFFABCDEF);
''';
      final r = tokenize(src, _opts());
      expect(r.source, contains('Color(0xFFABCDEF)'));
      expect(r.source, contains('// FORCE:'));
      expect(r.forced, hasLength(1));
      expect(r.forced.first.kind, 'color');
    });

    test('pure white & transparent sentinels are preserved when unmapped', () {
      final src = '''
import 'package:flutter/material.dart';
const a = Color(0xFFFFFFFF);
const b = Color(0x00000000);
''';
      final r = tokenize(src, _opts());
      expect(r.source, contains('Color(0xFFFFFFFF)'));
      expect(r.source, contains('Color(0x00000000)'));
      expect(r.forced, isEmpty);
      expect(r.substitutions, isEmpty);
    });

    test('near strategy accepts ΔE ≤ tolerance and marks as near', () {
      // Shift #0BA284 by 2 points on the R channel to stay within ΔE<~2.
      final src = '''
import 'package:flutter/material.dart';
const c = Color(0xFF0DA485);
''';
      final r = tokenize(src, _opts(strategy: TokenStrategy.near, tolerance: 5));
      expect(r.source, contains('context.customColors.brand30'));
      expect(r.substitutions.first.note, contains('near'));
    });

    test('near strategy rejects when ΔE > tolerance', () {
      // #FF00FF is nowhere near any theme color.
      final src = '''
import 'package:flutter/material.dart';
const c = Color(0xFFFF00FF);
''';
      final r = tokenize(src, _opts(strategy: TokenStrategy.near, tolerance: 2));
      expect(r.source, contains('Color(0xFFFF00FF)'));
      expect(r.forced, hasLength(1));
    });
  });

  group('spacing — EdgeInsets', () {
    test('EdgeInsets.all(16) → YHAppSpacing.sp4', () {
      final r = tokenize("final e = EdgeInsets.all(16);", _opts());
      expect(r.source, contains('EdgeInsets.all(YHAppSpacing.sp4)'));
    });

    test('EdgeInsets.symmetric maps matched values, forces unmatched', () {
      final r = tokenize(
        'final e = EdgeInsets.symmetric(horizontal: 10, vertical: 4);',
        _opts(),
      );
      // 10 is not in the scale → stays literal; 4 maps to sp1.
      expect(r.source, contains('horizontal: 10'));
      expect(r.source, contains('vertical: YHAppSpacing.sp1'));
      expect(r.source, contains('// FORCE:'));
      expect(r.forced, hasLength(1));
    });

    test('EdgeInsets.fromLTRB mixed match/miss preserves per-position tokens',
        () {
      final r = tokenize(
        'final e = EdgeInsets.fromLTRB(20, 16, 20, 12);',
        _opts(),
      );
      expect(
        r.source,
        contains(
          'EdgeInsets.fromLTRB(YHAppSpacing.sp5, YHAppSpacing.sp4, YHAppSpacing.sp5, YHAppSpacing.sp3)',
        ),
      );
      expect(r.forced, isEmpty);
    });

    test('SizedBox(width: N, height: N) each arg tokenizes independently', () {
      final r = tokenize('SizedBox(width: 8, height: 16);', _opts());
      expect(r.source,
          contains('SizedBox(width: YHAppSpacing.sp2, height: YHAppSpacing.sp4)'));
    });
  });

  group('radius', () {
    test('BorderRadius.circular(N) where N is in scale', () {
      final r = tokenize('BorderRadius.circular(12);', _opts());
      expect(r.source,
          contains('BorderRadius.circular(YHAppCornerRadiusV2.r3)'));
    });

    test('BorderRadius.circular(9999) → rfull', () {
      final r = tokenize('BorderRadius.circular(9999);', _opts());
      expect(r.source,
          contains('BorderRadius.circular(YHAppCornerRadiusV2.rfull)'));
    });

    test('BorderRadius.circular(N) unmapped → FORCE', () {
      final r = tokenize('BorderRadius.circular(17);', _opts());
      expect(r.source, contains('BorderRadius.circular(17)'));
      expect(r.source, contains('// FORCE:'));
      expect(r.forced, hasLength(1));
    });
  });

  group('typography — TextStyle → interText', () {
    test('Inter TextStyle transforms to interText helper call', () {
      final src = '''
import 'package:flutter/material.dart';
final s = TextStyle(
  fontFamily: 'Inter',
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: Color(0xFF0BA284),
  height: 1.429,
);
''';
      final r = tokenize(src, _opts());
      expect(r.source, contains('interText('));
      expect(r.source, contains('size: 14'));
      expect(r.source, contains('weight: 600'));
      expect(r.source, contains('color: context.customColors.brand30'));
      expect(r.source, contains('height: 1.429'));
      expect(r.substitutions.where((s) => s.kind == 'typography'), hasLength(1));
      // The typography import should be added to the output.
      expect(r.source, contains("import 'package:yh/inter_text.dart';"));
    });

    test('FontWeight.bold → 700, FontWeight.normal → 400', () {
      final src = '''
import 'package:flutter/material.dart';
final a = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.bold);
final b = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.normal);
''';
      final r = tokenize(src, _opts());
      expect(r.source, contains('weight: 700'));
      expect(r.source, contains('weight: 400'));
    });

    test('non-Inter TextStyle is preserved, its inner color still tokenizes', () {
      final src = '''
import 'package:flutter/material.dart';
final s = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 12,
  color: Color(0xFF0BA284),
);
''';
      final r = tokenize(src, _opts());
      expect(r.source, contains('TextStyle('));
      expect(r.source, contains('fontFamily:'));
      expect(r.source, contains('context.customColors.brand30'));
    });
  });

  group('const propagation', () {
    test('drops const from class constructor when substitution introduces non-const refs',
        () {
      final src = '''
import 'package:flutter/material.dart';

class _Foo extends StatelessWidget {
  const _Foo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(color: Color(0xFF0BA284));
  }
}
''';
      final r = tokenize(src, _opts());
      // The `const _Foo({super.key});` must lose its const.
      expect(r.source, contains('_Foo({super.key});'));
      expect(r.source, isNot(contains('const _Foo({super.key})')));
    });
  });

  group('idempotency', () {
    test('already-tokenized input is refused and returned as-is', () {
      final src = '''
import 'package:flutter/material.dart';
final c = context.customColors.brand30;
''';
      final r = tokenize(src, _opts());
      expect(r.alreadyTokenized, isTrue);
      expect(r.source, src);
      expect(r.substitutions, isEmpty);
    });

    test('detects YHAppSpacing.sp token as already-tokenized', () {
      final src = '''
import 'package:flutter/material.dart';
final e = EdgeInsets.all(YHAppSpacing.sp4);
''';
      final r = tokenize(src, _opts());
      expect(r.alreadyTokenized, isTrue);
    });
  });

  group('header', () {
    test('strips AUTO-GENERATED scaffold header and adds tokenize header', () {
      final src = '''
// AUTO-GENERATED by print_widget scaffold — do not edit.
// Source spec: foo.json
// Generated: 2026-04-17T00:00:00.000Z
// Regenerate: print_widget scaffold --spec=foo.json
//
// The scaffold uses literal values.

import 'package:flutter/material.dart';

const c = Color(0xFF0BA284);
''';
      final r = tokenize(src, _opts());
      expect(r.source, startsWith('// Tokenized by print_widget tokenize'));
      expect(r.source, isNot(contains('AUTO-GENERATED by print_widget scaffold')));
      expect(r.source, contains('// Theme: test'));
      expect(r.source, contains('// Substitutions: 1 colors'));
    });
  });
}
