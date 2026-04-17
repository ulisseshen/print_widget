/// Pure-Dart transformer from a scaffold source file (raw Flutter literals
/// emitted by Phase 4's `print_widget scaffold`) to a production widget that
/// references design-system tokens.
///
/// Phase 5 of the spec pipeline. The caller (`TokenizeCommand`) owns file I/O,
/// argument parsing, and process exit codes. This library is pure so unit tests
/// can exercise each substitution rule without touching disk.
///
/// Implementation strategy: **regex + brace-counting on text lines**. This is
/// grammatically simple enough for scaffold output (whose shape is fully
/// deterministic; see `scaffold_generator.dart`). AST-via-`package:analyzer`
/// is the v1.1 upgrade path — places where AST would be cleaner are flagged
/// inline with `// NOTE(ast-upgrade): ...`.
library;

import 'dart:math' as math;

/// Options that shape the generated token swap.
class TokenizerOptions {
  const TokenizerOptions({
    required this.theme,
    required this.strategy,
    required this.tolerance,
    this.scaffoldRelativePath,
  });

  /// Decoded `theme-ref.json` map.
  final Map<String, dynamic> theme;

  /// `exact` — only swap when the literal hex is a key in `colors.tokenMap`.
  /// `near` — also accept the nearest token within [tolerance] (ΔE-CIE76).
  final TokenStrategy strategy;

  /// Only used when [strategy] is [TokenStrategy.near]. Default 2.0 in the CLI.
  final double tolerance;

  /// Optional — only used to record the input path in the output header.
  final String? scaffoldRelativePath;
}

enum TokenStrategy { exact, near }

/// A single literal → token replacement the tokenizer performed.
class Substitution {
  const Substitution({
    required this.kind,
    required this.before,
    required this.after,
    this.note,
  });

  /// `color` / `spacing` / `radius` / `typography`.
  final String kind;
  final String before;
  final String after;

  /// Optional context — e.g. `"near ΔE=1.7"` for a fuzzy match.
  final String? note;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'before': before,
        'after': after,
        if (note != null) 'note': note,
      };
}

/// A literal that could NOT be tokenized — caller should show these as
/// FORCE comments in the output so a reviewer can decide what to do.
class ForcedValue {
  const ForcedValue({
    required this.kind,
    required this.literal,
    required this.reason,
  });

  final String kind;
  final String literal;
  final String reason;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'literal': literal,
        'reason': reason,
      };
}

/// Result of a tokenize pass. [source] is the full `.dart` file contents.
class TokenizerResult {
  TokenizerResult({
    required this.source,
    required this.substitutions,
    required this.forced,
    required this.alreadyTokenized,
  });

  final String source;
  final List<Substitution> substitutions;
  final List<ForcedValue> forced;

  /// True when the input source already contained tokenized references
  /// (`context.customColors.`, `YHAppSpacing.sp`, etc). In that case the
  /// tokenizer does NOT re-run — it returns the original source unchanged
  /// so the caller can raise an error if desired.
  final bool alreadyTokenized;
}

/// Main entrypoint. Transforms [scaffoldSource] per [options].
TokenizerResult tokenize(String scaffoldSource, TokenizerOptions options) {
  final alreadyTokenized = _isTokenized(scaffoldSource);
  if (alreadyTokenized) {
    return TokenizerResult(
      source: scaffoldSource,
      substitutions: const [],
      forced: const [],
      alreadyTokenized: true,
    );
  }

  final state = _TokenizerState(options);
  // Step 1: TextStyle → interText (multi-line block substitution). This must
  // run before per-line color substitution so the inner `Color(0x...)` call
  // is rewritten while we know it lives inside a TextStyle.
  var working = _rewriteTextStyles(scaffoldSource, state);
  // Step 2: BorderRadius.circular(N).
  working = _rewriteBorderRadius(working, state);
  // Step 3: EdgeInsets.* and SizedBox(width/height: N).
  working = _rewriteSpacing(working, state);
  // Step 4: Standalone Color(0x...) literals (including those left by TextStyle
  // handler when it kept the original TextStyle). Already-tokenized references
  // are left alone.
  working = _rewriteColors(working, state);
  // Step 5: SvgPicture width/height — tokenize only when value maps to scale.
  // NOTE(ast-upgrade): an AST would scope this to `SvgPicture.string(` calls.
  // The regex approach below already ran in step 3, so this is a no-op; we
  // handle SvgPicture spacing in step 3's generic width/height matcher.
  working = _rewriteHeader(working, state);
  working = _stripConstIfNeeded(working, state);

  return TokenizerResult(
    source: working,
    substitutions: state.substitutions,
    forced: state.forced,
    alreadyTokenized: false,
  );
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

bool _isTokenized(String source) {
  return source.contains('context.customColors.') ||
      RegExp(r'YHAppSpacing\.sp[\w]+').hasMatch(source) ||
      RegExp(r'YHAppCornerRadiusV2\.r[\w]+').hasMatch(source) ||
      RegExp(r'\binterText\s*\(').hasMatch(source);
}

class _TokenizerState {
  _TokenizerState(this.options)
      : colorMap = _loadColorMap(options.theme),
        spacingClass = _readSpacingClass(options.theme),
        spacingPrefix = _readSpacingPrefix(options.theme),
        spacingScale = _readSpacingScale(options.theme),
        radiusClass = _readRadiusClass(options.theme),
        radiusPrefix = _readRadiusPrefix(options.theme),
        radiusScale = _readRadiusScale(options.theme),
        colorAccessor = _readColorAccessor(options.theme),
        typographyHelper = _readTypographyHelper(options.theme),
        typographyImport = _readTypographyImport(options.theme);

  final TokenizerOptions options;
  final Map<String, String> colorMap; // "#RRGGBB" (upper) -> token name
  final String spacingClass;
  final String spacingPrefix;
  final Map<num, String> spacingScale; // px -> index suffix (e.g. 16 -> "4")
  final String radiusClass;
  final String radiusPrefix;
  final Map<num, String> radiusScale;
  final String colorAccessor;
  final String? typographyHelper;
  final String? typographyImport;

  final List<Substitution> substitutions = [];
  final List<ForcedValue> forced = [];
  bool usedTypography = false;

  Map<String, int> counts() {
    final counts = {'color': 0, 'spacing': 0, 'radius': 0, 'typography': 0};
    for (final s in substitutions) {
      counts[s.kind] = (counts[s.kind] ?? 0) + 1;
    }
    return counts;
  }
}

// ---- theme-ref readers ----------------------------------------------------

Map<String, String> _loadColorMap(Map<String, dynamic> theme) {
  final colors = theme['colors'];
  if (colors is! Map) return const {};
  final tokenMap = colors['tokenMap'];
  if (tokenMap is! Map) return const {};
  final out = <String, String>{};
  tokenMap.forEach((k, v) {
    if (k is String && v is String) {
      out[_normalizeHex(k)] = v;
    }
  });
  return out;
}

String _readColorAccessor(Map<String, dynamic> theme) {
  final colors = theme['colors'];
  if (colors is Map && colors['accessor'] is String) {
    return colors['accessor'] as String;
  }
  return 'context.customColors';
}

String _readSpacingClass(Map<String, dynamic> theme) {
  final s = theme['spacing'];
  if (s is Map && s['class'] is String) return s['class'] as String;
  return 'YHAppSpacing';
}

String _readSpacingPrefix(Map<String, dynamic> theme) {
  final s = theme['spacing'];
  if (s is Map && s['prefix'] is String) return s['prefix'] as String;
  return 'sp';
}

Map<num, String> _readSpacingScale(Map<String, dynamic> theme) {
  final s = theme['spacing'];
  if (s is! Map) return const {};
  final scale = s['scale'];
  if (scale is! Map) return const {};
  final out = <num, String>{};
  scale.forEach((k, v) {
    final px = num.tryParse(k.toString());
    if (px != null) out[px] = v.toString();
  });
  return out;
}

String _readRadiusClass(Map<String, dynamic> theme) {
  final r = theme['radius'];
  if (r is Map && r['class'] is String) return r['class'] as String;
  return 'YHAppCornerRadiusV2';
}

String _readRadiusPrefix(Map<String, dynamic> theme) {
  final r = theme['radius'];
  if (r is Map && r['prefix'] is String) return r['prefix'] as String;
  return 'r';
}

Map<num, String> _readRadiusScale(Map<String, dynamic> theme) {
  final r = theme['radius'];
  if (r is! Map) return const {};
  final scale = r['scale'];
  if (scale is! Map) return const {};
  final out = <num, String>{};
  scale.forEach((k, v) {
    final px = num.tryParse(k.toString());
    if (px != null) out[px] = v.toString();
  });
  return out;
}

String? _readTypographyHelper(Map<String, dynamic> theme) {
  final t = theme['typography'];
  if (t is Map && t['helper'] is String) {
    final h = (t['helper'] as String).trim();
    return h.isEmpty ? null : h;
  }
  return null;
}

String? _readTypographyImport(Map<String, dynamic> theme) {
  final t = theme['typography'];
  if (t is Map && t['import'] is String) {
    final imp = (t['import'] as String).trim();
    return imp.isEmpty ? null : imp;
  }
  return null;
}

// ---- color normalization & distance ---------------------------------------

/// "#0ba284" / "0BA284" / "0xFF0BA284" (hex color substring only) → `#0BA284`.
String _normalizeHex(String hex) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  // strip a leading 0x in case the caller pasted a Flutter literal
  if (s.toLowerCase().startsWith('0x')) s = s.substring(2);
  // Drop alpha if present (keeping RGB portion).
  if (s.length == 8) s = s.substring(2); // treat Flutter alpha-first ARGB
  if (s.length == 6) return '#${s.toUpperCase()}';
  if (s.length == 3) {
    final r = s[0], g = s[1], b = s[2];
    return '#${'$r$r$g$g$b$b'.toUpperCase()}';
  }
  return '#${s.toUpperCase()}';
}

/// Returns `[r,g,b]` 0..255 from `#RRGGBB` (already normalized).
List<int> _hexToRgb(String hex) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  return [
    int.parse(h.substring(0, 2), radix: 16),
    int.parse(h.substring(2, 4), radix: 16),
    int.parse(h.substring(4, 6), radix: 16),
  ];
}

/// CIE76 ΔE. Good enough as an MVP fuzzy-match gate; CIE2000 is the
/// precision-freak upgrade.
double _deltaE76(String hexA, String hexB) {
  final a = _rgbToLab(_hexToRgb(hexA));
  final b = _rgbToLab(_hexToRgb(hexB));
  return math.sqrt(
    math.pow(a[0] - b[0], 2) +
        math.pow(a[1] - b[1], 2) +
        math.pow(a[2] - b[2], 2),
  );
}

List<double> _rgbToLab(List<int> rgb) {
  // sRGB → linear
  double srgbToLinear(int v) {
    final c = v / 255.0;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = srgbToLinear(rgb[0]);
  final g = srgbToLinear(rgb[1]);
  final b = srgbToLinear(rgb[2]);

  // Linear RGB → XYZ (D65)
  final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
  final y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750) / 1.00000;
  final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;

  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t + 16 / 116);

  final fx = f(x), fy = f(y), fz = f(z);
  return [
    116 * fy - 16,
    500 * (fx - fy),
    200 * (fy - fz),
  ];
}

// ---- substitution: colors -------------------------------------------------

/// Rewrites every `Color(0xAARRGGBB)` literal in [source] according to
/// [state.colorMap] and [state.options.strategy].
///
/// NOTE(ast-upgrade): naive regex misses no cases for scaffold output (which
/// only writes `Color(0x........)`), but for user-hand-edited input an AST
/// pass would catch e.g. `const Color(0x...)` or `Color.fromARGB(...)`.
String _rewriteColors(String source, _TokenizerState state) {
  final re = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)');
  return source.replaceAllMapped(re, (m) {
    final raw = m.group(1)!.toUpperCase();
    final alpha = int.parse(raw.substring(0, 2), radix: 16);
    final rgbHex = '#${raw.substring(2)}';

    // Sentinels — keep as-is unless explicitly mapped.
    final isPureWhite = raw == 'FFFFFFFF';
    final isTransparent = raw == '00000000';
    if ((isPureWhite || isTransparent) && !state.colorMap.containsKey(rgbHex)) {
      return m.group(0)!;
    }

    final mapped = _resolveColor(rgbHex, state);
    if (mapped == null) {
      final reason = 'no token match for ${m.group(0)} in colors.tokenMap';
      state.forced.add(ForcedValue(
        kind: 'color',
        literal: m.group(0)!,
        reason: reason,
      ));
      return '${_forceMarker(reason)}${m.group(0)!}';
    }

    final tokenRef = '${state.colorAccessor}.${mapped.token}';
    String replacement;
    String? note;
    if (alpha == 0xFF) {
      replacement = tokenRef;
    } else {
      final opacity = _roundTo(alpha / 255, 2);
      replacement = '$tokenRef.withValues(alpha: $opacity)';
    }
    if (mapped.delta != null) {
      note = 'near ΔE=${_roundTo(mapped.delta!, 2)} → ${mapped.token}';
    }
    state.substitutions.add(Substitution(
      kind: 'color',
      before: m.group(0)!,
      after: replacement,
      note: note,
    ));
    return replacement;
  });
}

/// Inline marker injected at substitution time — the header pass converts it
/// to a `// FORCE:` comment on the line above. Unique enough to never collide
/// with real Dart tokens.
String _forceMarker(String reason) =>
    '/*__PW_FORCE__${reason.replaceAll('*/', '*')}__END__*/';

class _ColorMatch {
  _ColorMatch(this.token, this.delta);
  final String token;
  final double? delta; // non-null for `near` matches
}

_ColorMatch? _resolveColor(String rgbHex, _TokenizerState state) {
  final exact = state.colorMap[rgbHex];
  if (exact != null) return _ColorMatch(exact, null);
  if (state.options.strategy != TokenStrategy.near) return null;
  double bestDe = double.infinity;
  String? bestToken;
  for (final entry in state.colorMap.entries) {
    final d = _deltaE76(rgbHex, entry.key);
    if (d < bestDe) {
      bestDe = d;
      bestToken = entry.value;
    }
  }
  if (bestToken == null || bestDe > state.options.tolerance) return null;
  return _ColorMatch(bestToken, bestDe);
}

double _roundTo(double v, int decimals) {
  final f = math.pow(10, decimals);
  return (v * f).round() / f;
}

// ---- substitution: EdgeInsets + SizedBox ---------------------------------

String _rewriteSpacing(String source, _TokenizerState state) {
  // EdgeInsets.all(N)
  source = source.replaceAllMapped(
    RegExp(r'EdgeInsets\.all\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)'),
    (m) {
      final n = num.parse(m.group(1)!);
      final tok = _spacingTokenFor(n, state);
      if (tok == null) {
        final reason = 'no token match for ${m.group(0)} in spacing.scale';
        state.forced.add(ForcedValue(
          kind: 'spacing', literal: m.group(0)!, reason: reason));
        return '${_forceMarker(reason)}${m.group(0)!}';
      }
      final after = 'EdgeInsets.all($tok)';
      state.substitutions.add(Substitution(
        kind: 'spacing', before: m.group(0)!, after: after));
      return after;
    },
  );

  // EdgeInsets.symmetric(horizontal: H, vertical: V) — either order.
  source = source.replaceAllMapped(
    RegExp(
      r'EdgeInsets\.symmetric\(\s*'
      r'(?:horizontal:\s*([0-9]+(?:\.[0-9]+)?)\s*,\s*vertical:\s*([0-9]+(?:\.[0-9]+)?)\s*'
      r'|vertical:\s*([0-9]+(?:\.[0-9]+)?)\s*,\s*horizontal:\s*([0-9]+(?:\.[0-9]+)?)\s*)\)',
    ),
    (m) {
      final h = num.parse(m.group(1) ?? m.group(4)!);
      final v = num.parse(m.group(2) ?? m.group(3)!);
      final ht = _spacingValueFor(h, state);
      final vt = _spacingValueFor(v, state);
      final after =
          'EdgeInsets.symmetric(horizontal: ${ht.rendered}, vertical: ${vt.rendered})';
      return _recordSpacing(state, m.group(0)!, after, [ht, vt]);
    },
  );

  // EdgeInsets.fromLTRB(l, t, r, b)
  source = source.replaceAllMapped(
    RegExp(
      r'EdgeInsets\.fromLTRB\(\s*'
      r'([0-9]+(?:\.[0-9]+)?)\s*,\s*'
      r'([0-9]+(?:\.[0-9]+)?)\s*,\s*'
      r'([0-9]+(?:\.[0-9]+)?)\s*,\s*'
      r'([0-9]+(?:\.[0-9]+)?)\s*\)',
    ),
    (m) {
      final l = _spacingValueFor(num.parse(m.group(1)!), state);
      final t = _spacingValueFor(num.parse(m.group(2)!), state);
      final r = _spacingValueFor(num.parse(m.group(3)!), state);
      final b = _spacingValueFor(num.parse(m.group(4)!), state);
      final after =
          'EdgeInsets.fromLTRB(${l.rendered}, ${t.rendered}, ${r.rendered}, ${b.rendered})';
      return _recordSpacing(state, m.group(0)!, after, [l, t, r, b]);
    },
  );

  // SizedBox(width: N) / SizedBox(height: N) / SizedBox(width: N, height: N)
  source = source.replaceAllMapped(
    RegExp(
      r'SizedBox\(\s*'
      r'(?:width:\s*([0-9]+(?:\.[0-9]+)?)\s*)?'
      r'(?:,\s*)?'
      r'(?:height:\s*([0-9]+(?:\.[0-9]+)?)\s*)?\)',
    ),
    (m) {
      final w = m.group(1);
      final h = m.group(2);
      if (w == null && h == null) return m.group(0)!;
      final parts = <String>[];
      final values = <_SpacingValue>[];
      if (w != null) {
        final wv = _spacingValueFor(num.parse(w), state);
        values.add(wv);
        parts.add('width: ${wv.rendered}');
      }
      if (h != null) {
        final hv = _spacingValueFor(num.parse(h), state);
        values.add(hv);
        parts.add('height: ${hv.rendered}');
      }
      final after = 'SizedBox(${parts.join(', ')})';
      return _recordSpacing(state, m.group(0)!, after, values);
    },
  );

  // `width: N,` and `height: N,` as standalone arguments (e.g. Container,
  // SvgPicture.string). Only swap when the value appears alone on its line
  // (so we don't re-tokenize the lineHeight-like fields elsewhere) and maps
  // to a known scale index.
  source = source.replaceAllMapped(
    RegExp(r'(?<=\s)(width|height):\s*([0-9]+(?:\.[0-9]+)?),'),
    (m) {
      final key = m.group(1)!;
      final raw = num.parse(m.group(2)!);
      final tok = _spacingTokenFor(raw, state);
      if (tok == null) return m.group(0)!; // silent no-op (not a force — the
      // consumer likely wants the literal).
      final after = '$key: $tok,';
      state.substitutions.add(Substitution(
        kind: 'spacing', before: m.group(0)!, after: after));
      return after;
    },
  );

  return source;
}

class _SpacingValue {
  _SpacingValue({required this.rendered, required this.matched, required this.original});
  final String rendered; // exact Dart fragment
  final bool matched; // true if mapped to token
  final String original; // raw numeric as appeared in source
}

_SpacingValue _spacingValueFor(num v, _TokenizerState state) {
  final tok = _spacingTokenFor(v, state);
  if (tok == null) {
    return _SpacingValue(rendered: _num(v), matched: false, original: _num(v));
  }
  return _SpacingValue(rendered: tok, matched: true, original: _num(v));
}

String? _spacingTokenFor(num px, _TokenizerState state) {
  final suffix = state.spacingScale[px];
  if (suffix == null) return null;
  return '${state.spacingClass}.${state.spacingPrefix}$suffix';
}

/// Records substitution/force entries and returns the rewrite (prefixed with
/// inline FORCE markers when any value failed to map).
String _recordSpacing(
  _TokenizerState state,
  String before,
  String after,
  List<_SpacingValue> values,
) {
  final hasAnyMatch = values.any((p) => p.matched);
  final misses = values.where((p) => !p.matched).toList();
  if (hasAnyMatch) {
    state.substitutions.add(Substitution(
      kind: 'spacing', before: before, after: after));
  }
  if (misses.isEmpty) return after;
  final reasons = <String>[];
  for (final p in misses) {
    final reason = 'no token match for ${p.original} in spacing.scale';
    reasons.add(reason);
    state.forced.add(ForcedValue(
      kind: 'spacing', literal: p.original, reason: reason));
  }
  final combined = reasons.toSet().join(' | ');
  return '${_forceMarker(combined)}$after';
}

// ---- substitution: radius -------------------------------------------------

String _rewriteBorderRadius(String source, _TokenizerState state) {
  return source.replaceAllMapped(
    RegExp(r'BorderRadius\.circular\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)'),
    (m) {
      final raw = num.parse(m.group(1)!);
      final suffix = state.radiusScale[raw];
      if (suffix == null) {
        final reason = 'no token match for ${m.group(0)} in radius.scale';
        state.forced.add(ForcedValue(
          kind: 'radius', literal: m.group(0)!, reason: reason));
        return '${_forceMarker(reason)}${m.group(0)!}';
      }
      final after =
          'BorderRadius.circular(${state.radiusClass}.${state.radiusPrefix}$suffix)';
      state.substitutions.add(Substitution(
        kind: 'radius', before: m.group(0)!, after: after));
      return after;
    },
  );
}

// ---- substitution: TextStyle → interText ---------------------------------

String _rewriteTextStyles(String source, _TokenizerState state) {
  final helper = state.typographyHelper;
  if (helper == null) return source; // no helper → leave TextStyle alone

  final result = StringBuffer();
  var cursor = 0;
  while (cursor < source.length) {
    final idx = source.indexOf('TextStyle(', cursor);
    if (idx < 0) {
      result.write(source.substring(cursor));
      break;
    }
    result.write(source.substring(cursor, idx));
    final end = _matchParen(source, idx + 'TextStyle'.length);
    if (end < 0) {
      // Unbalanced — bail out on the remainder.
      result.write(source.substring(idx));
      break;
    }
    final block = source.substring(idx, end + 1);
    final replaced = _rewriteTextStyleBlock(block, state);
    result.write(replaced);
    cursor = end + 1;
  }
  return result.toString();
}

/// Finds the matching `)` for the `(` at [openIdx] — returns the index of the
/// matching `)` or -1 if unbalanced. Does NOT look inside string literals —
/// TextStyle arguments don't usually contain `'` or `"` with parens, but
/// Text('...') in the same line is not a concern because we only call this
/// function after locking onto a `TextStyle(`.
int _matchParen(String s, int openIdx) {
  assert(s[openIdx] == '(');
  var depth = 0;
  var inString = false;
  String? quote;
  for (var i = openIdx; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == r'\\' && i + 1 < s.length) {
        i++; // skip escaped char
        continue;
      }
      if (c == quote) {
        inString = false;
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inString = true;
      quote = c;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String _rewriteTextStyleBlock(String block, _TokenizerState state) {
  // block starts with `TextStyle(` and ends with `)`.
  final helper = state.typographyHelper!;

  // Parse simple top-level key: value pairs. Separator is `,` at paren-depth 0.
  final inner = block.substring('TextStyle('.length, block.length - 1);
  final pairs = _splitTopLevelArgs(inner);
  final parsed = <String, String>{};
  for (final p in pairs) {
    final colon = p.indexOf(':');
    if (colon < 0) continue;
    final key = p.substring(0, colon).trim();
    final value = p.substring(colon + 1).trim();
    parsed[key] = value;
  }

  // Only transform when fontFamily == 'Inter' (matches the helper default).
  final family = parsed['fontFamily'];
  final isInter = family != null && _unquote(family) == 'Inter';
  if (!isInter) {
    // Leave TextStyle shape alone but still tokenize any color inside.
    // That happens in the per-file color pass later.
    return block;
  }

  final size = parsed['fontSize'];
  final weightRaw = parsed['fontWeight'];
  final colorRaw = parsed['color'];
  final heightRaw = parsed['height'];
  final letterRaw = parsed['letterSpacing'];

  final buf = StringBuffer('$helper(');
  final parts = <String>[];
  if (size != null) {
    parts.add('size: $size');
  }
  if (weightRaw != null) {
    final w = _mapFontWeightToInt(weightRaw);
    if (w != null) parts.add('weight: $w');
  }
  if (colorRaw != null) {
    final tokenized = _tokenizeInlineColor(colorRaw, state);
    parts.add('color: $tokenized');
  }
  if (heightRaw != null) parts.add('height: $heightRaw');
  if (letterRaw != null) parts.add('letterSpacing: $letterRaw');
  buf.write(parts.join(', '));
  buf.write(')');

  state.usedTypography = true;
  state.substitutions.add(Substitution(
    kind: 'typography',
    before: 'TextStyle(...)',
    after: '$helper(...)',
  ));
  return buf.toString();
}

List<String> _splitTopLevelArgs(String s) {
  final out = <String>[];
  var depth = 0;
  var inString = false;
  String? quote;
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      buf.write(c);
      if (c == r'\\' && i + 1 < s.length) {
        buf.write(s[i + 1]);
        i++;
        continue;
      }
      if (c == quote) {
        inString = false;
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      inString = true;
      quote = c;
      buf.write(c);
      continue;
    }
    if (c == '(' || c == '{' || c == '[') depth++;
    if (c == ')' || c == '}' || c == ']') depth--;
    if (c == ',' && depth == 0) {
      if (buf.toString().trim().isNotEmpty) {
        out.add(buf.toString().trim());
      }
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
  return out;
}

String _unquote(String s) {
  final t = s.trim();
  if ((t.startsWith("'") && t.endsWith("'")) ||
      (t.startsWith('"') && t.endsWith('"'))) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

int? _mapFontWeightToInt(String raw) {
  final t = raw.trim();
  if (t == 'FontWeight.bold') return 700;
  if (t == 'FontWeight.normal') return 400;
  final m = RegExp(r'^FontWeight\.w([1-9]00|1000)$').firstMatch(t);
  if (m != null) return int.parse(m.group(1)!);
  final asInt = int.tryParse(t);
  return asInt;
}

/// Recursively resolves a `Color(0xAARRGGBB)` expression inside a TextStyle
/// color arg, so the TextStyle rewrite and the top-level color rewrite agree.
String _tokenizeInlineColor(String raw, _TokenizerState state) {
  final m = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)').firstMatch(raw);
  if (m == null) return raw;
  final hexRaw = m.group(1)!.toUpperCase();
  final alpha = int.parse(hexRaw.substring(0, 2), radix: 16);
  final rgbHex = '#${hexRaw.substring(2)}';
  final sentinel = hexRaw == 'FFFFFFFF' || hexRaw == '00000000';
  if (sentinel && !state.colorMap.containsKey(rgbHex)) return raw;
  final match = _resolveColor(rgbHex, state);
  if (match == null) {
    state.forced.add(ForcedValue(
      kind: 'color',
      literal: m.group(0)!,
      reason: 'no token match for ${m.group(0)} in colors.tokenMap',
    ));
    return raw;
  }
  final ref = '${state.colorAccessor}.${match.token}';
  final out = alpha == 0xFF
      ? ref
      : '$ref.withValues(alpha: ${_roundTo(alpha / 255, 2)})';
  state.substitutions.add(Substitution(
    kind: 'color',
    before: m.group(0)!,
    after: out,
    note: match.delta == null
        ? null
        : 'near ΔE=${_roundTo(match.delta!, 2)} → ${match.token}',
  ));
  // Substring replace inside `raw` to preserve any `const `/whitespace prefix.
  return raw.replaceFirst(m.group(0)!, out);
}

// ---- header + const propagation ------------------------------------------

String _rewriteHeader(String source, _TokenizerState state) {
  // Step 1 — split the source: strip any existing scaffold AUTO-GENERATED
  // header, preserve the imports, and keep the body separately.
  final lines = source.split('\n');

  final imports = <String>[];
  final body = <String>[];
  var firstImport = lines.indexWhere((l) => l.trimLeft().startsWith('import '));
  var afterImportsIdx = firstImport;
  if (firstImport >= 0) {
    // Collect contiguous imports (allowing blank interlines).
    var i = firstImport;
    while (i < lines.length) {
      final l = lines[i];
      if (l.trimLeft().startsWith('import ') || l.trim().isEmpty) {
        // Keep going while we're in the import region — break on the first
        // non-blank, non-import line.
        if (l.trim().isEmpty && imports.isEmpty) {
          // Leading blank before any import? Keep it out.
          i++;
          continue;
        }
        imports.add(l);
        i++;
        if (l.trim().isEmpty && i < lines.length &&
            !lines[i].trimLeft().startsWith('import ')) {
          // The blank line was the import/body separator — stop.
          afterImportsIdx = i;
          break;
        }
        afterImportsIdx = i;
      } else {
        break;
      }
    }
    body.addAll(lines.sublist(afterImportsIdx));
  } else {
    body.addAll(lines);
  }

  // Strip trailing blank imports (keep one separator).
  while (imports.isNotEmpty && imports.last.trim().isEmpty) {
    imports.removeLast();
  }

  // Add the typography import if needed.
  if (state.usedTypography && state.typographyImport != null) {
    final imp = "import '${state.typographyImport}';";
    if (!imports.any((l) => l.trim() == imp)) imports.add(imp);
  }

  // Step 2 — convert inline FORCE markers in body to comment lines above.
  final forcedBody = <String>[];
  final markerRe =
      RegExp(r'/\*__PW_FORCE__(.*?)__END__\*/', multiLine: false);
  for (final raw in body) {
    var l = raw;
    final matches = markerRe.allMatches(l).toList();
    if (matches.isNotEmpty) {
      final indent = l.substring(0, l.length - l.trimLeft().length);
      for (final mm in matches) {
        final reason = mm.group(1)!;
        forcedBody.add('$indent// FORCE: $reason');
      }
      l = l.replaceAll(markerRe, '');
    }
    forcedBody.add(l);
  }

  // Step 3 — assemble the tokenize header.
  final counts = state.counts();
  final themeName = state.options.theme['name'] is String
      ? state.options.theme['name'] as String
      : 'unknown';
  final header = <String>[
    '// Tokenized by print_widget tokenize — do not edit.',
    '// Scaffold source: ${state.options.scaffoldRelativePath ?? '<stdin>'}',
    '// Theme: $themeName',
    '// Substitutions: ${counts['color']} colors, '
        '${counts['spacing']} spacing, '
        '${counts['radius']} radius, '
        '${counts['typography']} typography',
    if (state.forced.isNotEmpty)
      '// Forced (no token match): ${state.forced.length} — see // FORCE: comments below',
    '// Regenerate: print_widget tokenize '
        '--input=${state.options.scaffoldRelativePath ?? '<path>'} '
        '--theme=<theme.json> --output=<path>',
  ];

  // Step 4 — glue header + imports + body.
  final buf = StringBuffer();
  buf.writeln(header.join('\n'));
  buf.writeln();
  if (imports.isNotEmpty) {
    buf.writeln(imports.join('\n'));
    buf.writeln();
  }
  // Drop any leading blank lines from the body (we just emitted one).
  var bodyStart = 0;
  while (bodyStart < forcedBody.length && forcedBody[bodyStart].trim().isEmpty) {
    bodyStart++;
  }
  buf.write(forcedBody.sublist(bodyStart).join('\n'));
  var out = buf.toString();
  if (!out.endsWith('\n')) out += '\n';
  return out;
}

/// If any tokenization introduced a non-const reference (`context.customColors`
/// or a typography helper), strip `const ` from the class constructor and from
/// the `return const ...` in `build(...)`. The scaffold generator already
/// handled SVG-driven const drops, so this only fires when our substitutions
/// *introduced* the non-const call.
String _stripConstIfNeeded(String source, _TokenizerState state) {
  final hasContextRef = source.contains('${state.colorAccessor}.');
  final hasHelperCall = state.typographyHelper != null &&
      RegExp('\\b${RegExp.escape(state.typographyHelper!)}\\s*\\(')
          .hasMatch(source);
  if (!hasContextRef && !hasHelperCall) return source;

  // Drop `const ` preceding the class constructor of the form:
  //   const _FooScaffold({super.key});
  final classCtor = RegExp(r'const\s+(_\w+)\s*\(\{super\.key\}\);');
  source = source.replaceAllMapped(classCtor, (m) => '${m.group(1)}({super.key});');

  // Drop `const ` inside `return const ...;` or on inner widgets — let
  // dart format / analyzer warnings take care of the rest. Safest to
  // just drop top-level `return ...;` const usage.
  return source;
}

String _num(num n) {
  final d = n.toDouble();
  if (d == d.truncateToDouble() && d.abs() < 1e16) {
    return d.toInt().toString();
  }
  var s = d.toString();
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}
