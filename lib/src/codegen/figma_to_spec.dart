/// Figma MCP -> spec v1 adapter (Phase 7 of the spec pipeline).
///
/// Normalizes a decoded `get_design_context` response from the Figma MCP
/// server into the same envelope that `lib/src/tools/extract.mjs` emits from
/// browser DOM. Consumers — `scaffold_generator.dart` and `tokenizer.dart` —
/// don't know or care which extractor produced the spec.
///
/// Pure data normalization: no file I/O, no network calls, no Figma REST.
/// The caller owns reading the MCP response and writing the envelope.
library;

import 'dart:math' as math;

/// Options that shape the emitted envelope.
class FigmaToSpecOptions {
  const FigmaToSpecOptions({
    this.sourceUrl,
    this.stateName,
    this.cropFileName,
  });

  /// Figma URL (or any human-friendly identifier) copied into `source.url`.
  /// Falls back to `null` when omitted.
  final String? sourceUrl;

  /// Label copied into `source.state`. Falls back to the root node's `name`.
  final String? stateName;

  /// Value for `crop.file`. Falls back to `<slug(rootName)>.png`.
  final String? cropFileName;
}

/// Normalize a decoded Figma MCP `get_design_context` response into the
/// spec v1 envelope.
///
/// Unknown node types and unknown keys are silently ignored. The adapter never
/// throws for shape drift — it either emits a placeholder node or skips it.
Map<String, dynamic> figmaToSpec(
  Map<String, dynamic> mcpResponse, {
  FigmaToSpecOptions options = const FigmaToSpecOptions(),
}) {
  final rootNode = _unwrapRoot(mcpResponse);
  if (rootNode == null) {
    throw ArgumentError(
      'figma_to_spec: could not locate a root node in the MCP response. '
      'Expected a Figma node object with at least a `type` and '
      '`absoluteBoundingBox` field, either at the top level or under '
      'common wrapper keys (`node`, `root`, `data`).',
    );
  }

  final rootBox = _box(rootNode);
  final rootName = (rootNode['name'] as String?) ?? 'root';
  final walked = _walkNode(rootNode, origin: rootBox);

  // The root itself is always emitted even if `walked` is null (defensive —
  // e.g. zero-sized root). Build a minimal placeholder in that case.
  final rootMap = walked ??
      _orderedNode(
        tag: 'div',
        bounds: _relBounds(rootBox, rootBox),
        styles: <String, dynamic>{'display': 'block'},
      );

  final stateLabel = options.stateName ?? rootName;
  final cropFile = options.cropFileName ?? '${_slug(rootName)}.png';

  return <String, dynamic>{
    r'$version': '1.0',
    'source': <String, dynamic>{
      'url': options.sourceUrl,
      'state': stateLabel,
      'extractor': 'figma_to_spec',
    },
    'crop': <String, dynamic>{
      'file': cropFile,
      'text': rootName,
      'bounds': <String, dynamic>{
        'x': rootBox.x.round(),
        'y': rootBox.y.round(),
        'w': rootBox.w.round(),
        'h': rootBox.h.round(),
      },
    },
    'root': rootMap,
  };
}

// ---------------------------------------------------------------------------
// Root unwrapping
// ---------------------------------------------------------------------------

Map<String, dynamic>? _unwrapRoot(Map<String, dynamic> raw) {
  if (_looksLikeNode(raw)) return raw;
  for (final key in const ['node', 'root', 'data', 'document']) {
    final inner = raw[key];
    if (inner is Map) {
      final cast = inner.cast<String, dynamic>();
      if (_looksLikeNode(cast)) return cast;
      final deeper = _unwrapRoot(cast);
      if (deeper != null) return deeper;
    }
  }
  return null;
}

bool _looksLikeNode(Map<String, dynamic> m) =>
    m['type'] is String && m['absoluteBoundingBox'] is Map;

// ---------------------------------------------------------------------------
// Bounding boxes
// ---------------------------------------------------------------------------

class _Box {
  _Box(this.x, this.y, this.w, this.h);
  final double x;
  final double y;
  final double w;
  final double h;
}

_Box _box(Map<String, dynamic> node) {
  final abb = node['absoluteBoundingBox'];
  if (abb is Map) {
    final m = abb.cast<String, dynamic>();
    return _Box(
      (m['x'] as num?)?.toDouble() ?? 0,
      (m['y'] as num?)?.toDouble() ?? 0,
      (m['width'] as num?)?.toDouble() ?? 0,
      (m['height'] as num?)?.toDouble() ?? 0,
    );
  }
  return _Box(0, 0, 0, 0);
}

Map<String, dynamic> _relBounds(_Box node, _Box origin) => <String, dynamic>{
      'x': (node.x - origin.x).round(),
      'y': (node.y - origin.y).round(),
      'w': node.w.round(),
      'h': node.h.round(),
    };

// ---------------------------------------------------------------------------
// Walker
// ---------------------------------------------------------------------------

const _kContainerTypes = <String>{
  'FRAME',
  'GROUP',
  'COMPONENT',
  'COMPONENT_SET',
  'INSTANCE',
  'SECTION',
};

const _kUnsupportedTypes = <String>{
  'SLICE',
  'STICKY',
  'CONNECTOR',
  'SHAPE_WITH_TEXT',
  'CODE_BLOCK',
  'WIDGET',
  'STAMP',
};

Map<String, dynamic>? _walkNode(
  Map<String, dynamic> node, {
  required _Box origin,
}) {
  if (node['visible'] == false) return null;

  final type = (node['type'] as String?) ?? 'UNKNOWN';
  if (_kUnsupportedTypes.contains(type)) return null;

  final box = _box(node);
  if (box.w < 0.5 || box.h < 0.5) return null;

  // Tag: svg for icon-like leaves, div for containers, span for text.
  if (type == 'TEXT') {
    return _walkText(node, box: box, origin: origin);
  }

  // Icon detection — INSTANCE with known library prefix, or raw vector types.
  final iconNode = _tryEmitIcon(node, type: type, box: box, origin: origin);
  if (iconNode != null) return iconNode;

  // Raw vector / shape that didn't match an icon heuristic — still a leaf.
  if (const {
    'VECTOR',
    'BOOLEAN_OPERATION',
    'LINE',
    'REGULAR_POLYGON',
    'STAR',
    'ELLIPSE',
  }.contains(type)) {
    // Ellipse with full radius ≈ circle — handled generically below via style.
    final styles = _collectStyles(node, box: box, selfType: type);
    final rawSvg = _tryReadSvg(node);
    final emitted = _orderedNode(
      tag: rawSvg != null ? 'svg' : 'div',
      bounds: _relBounds(box, origin),
      svgHtml: rawSvg,
      styles: styles.isEmpty ? null : styles,
    );
    return emitted;
  }

  final isContainer = _kContainerTypes.contains(type) ||
      type == 'RECTANGLE' && node['children'] is List;

  // Collect styles (may include layout markers that depend on children).
  final styles = _collectStyles(node, box: box, selfType: type);

  // Children
  final rawChildren =
      (node['children'] as List?)?.cast<dynamic>() ?? const <dynamic>[];

  final useAbsolute = (node['layoutMode'] as String?) == null ||
      node['layoutMode'] == 'NONE';

  final emittedKids = <Map<String, dynamic>>[];
  for (final raw in rawChildren) {
    if (raw is! Map) continue;
    final child = raw.cast<String, dynamic>();
    final walked = _walkNode(child, origin: origin);
    if (walked == null) continue;

    // Parent has no layoutMode → position each emitted child absolutely,
    // relative to parent (not the root).
    if (useAbsolute && isContainer) {
      _applyAbsolutePositioning(walked, child: child, parentBox: box);
    }

    emittedKids.add(walked);
  }

  // Pure shape / RECTANGLE leaf (no children) — emit a div with styles.
  if (!isContainer && emittedKids.isEmpty) {
    final rawSvg = _tryReadSvg(node);
    return _orderedNode(
      tag: rawSvg != null ? 'svg' : 'div',
      bounds: _relBounds(box, origin),
      svgHtml: rawSvg,
      styles: styles.isEmpty ? null : styles,
    );
  }

  // Container: ensure parent carries position:relative when emitting absolute
  // children, so scaffold knows to wrap in Stack.
  if (useAbsolute && isContainer && emittedKids.isNotEmpty) {
    styles['position'] = 'relative';
  }

  return _orderedNode(
    tag: 'div',
    bounds: _relBounds(box, origin),
    styles: styles.isEmpty ? null : styles,
    children: emittedKids.isEmpty ? null : emittedKids,
  );
}

void _applyAbsolutePositioning(
  Map<String, dynamic> emittedChild, {
  required Map<String, dynamic> child,
  required _Box parentBox,
}) {
  final childBox = _box(child);
  final styles =
      (emittedChild['styles'] as Map?)?.cast<String, dynamic>() ?? {};
  styles['position'] = 'absolute';
  styles['left'] = '${(childBox.x - parentBox.x).round()}px';
  styles['top'] = '${(childBox.y - parentBox.y).round()}px';
  emittedChild['styles'] = styles;
}

// ---------------------------------------------------------------------------
// Style collection
// ---------------------------------------------------------------------------

Map<String, dynamic> _collectStyles(
  Map<String, dynamic> node, {
  required _Box box,
  required String selfType,
}) {
  final out = <String, dynamic>{};

  // Layout
  final layoutMode = node['layoutMode'] as String?;
  if (layoutMode == 'VERTICAL') {
    out['display'] = 'flex';
    out['flexDirection'] = 'column';
  } else if (layoutMode == 'HORIZONTAL') {
    out['display'] = 'flex';
    // row is default — omit flexDirection
  }

  if (layoutMode == 'VERTICAL' || layoutMode == 'HORIZONTAL') {
    final spacing = (node['itemSpacing'] as num?)?.toDouble();
    if (spacing != null && spacing > 0) {
      out['gap'] = _niceNum(spacing);
    }
    final primary = node['primaryAxisAlignItems'] as String?;
    final mapped = _mapPrimaryAxis(primary);
    if (mapped != null) out['justifyContent'] = mapped;
    final counter = node['counterAxisAlignItems'] as String?;
    final mappedCross = _mapCounterAxis(counter);
    if (mappedCross != null) out['alignItems'] = mappedCross;
  }

  // layoutGrow — Figma only emits layoutGrow:1 as a sibling flex hint.
  final layoutGrow = (node['layoutGrow'] as num?)?.toDouble();
  if (layoutGrow != null && layoutGrow > 0) {
    out['flexGrow'] = _niceNum(layoutGrow);
  }

  // Padding
  final pt = (node['paddingTop'] as num?)?.toDouble() ?? 0;
  final pr = (node['paddingRight'] as num?)?.toDouble() ?? 0;
  final pb = (node['paddingBottom'] as num?)?.toDouble() ?? 0;
  final pl = (node['paddingLeft'] as num?)?.toDouble() ?? 0;
  if (pt > 0 || pr > 0 || pb > 0 || pl > 0) {
    out['padding'] = <String, dynamic>{
      'top': _niceNum(pt),
      'right': _niceNum(pr),
      'bottom': _niceNum(pb),
      'left': _niceNum(pl),
    };
  }

  // Fills / background
  final fillInfo = _extractBackground(node);
  if (fillInfo != null) {
    if (fillInfo.solidCss != null) {
      out['backgroundColor'] = fillInfo.solidCss;
    }
    if (fillInfo.gradientCss != null) {
      out['backgroundImage'] = fillInfo.gradientCss;
    }
  }

  // Strokes / border
  final borderInfo = _extractBorder(node);
  if (borderInfo != null) {
    out['border'] = borderInfo;
  }

  // Corner radius
  final radius = _extractBorderRadius(node, box);
  if (radius != null) {
    out['borderRadius'] = radius;
  }

  // Effects (drop shadow, inner shadow, blur)
  final shadowCss = _extractBoxShadow(node);
  if (shadowCss != null) {
    out['boxShadow'] = shadowCss;
  }

  // Opacity
  final opacity = (node['opacity'] as num?)?.toDouble();
  if (opacity != null && opacity < 1.0) {
    out['opacity'] = _round2(opacity);
  }

  return out;
}

String? _mapPrimaryAxis(String? v) {
  switch (v) {
    case 'MIN':
      return 'flex-start';
    case 'CENTER':
      return 'center';
    case 'MAX':
      return 'flex-end';
    case 'SPACE_BETWEEN':
      return 'space-between';
    default:
      return null;
  }
}

String? _mapCounterAxis(String? v) {
  switch (v) {
    case 'MIN':
      return 'flex-start';
    case 'CENTER':
      return 'center';
    case 'MAX':
      return 'flex-end';
    case 'STRETCH':
      return 'stretch';
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Fills
// ---------------------------------------------------------------------------

class _FillInfo {
  _FillInfo({this.solidCss, this.gradientCss});
  final String? solidCss;
  final String? gradientCss;
}

_FillInfo? _extractBackground(Map<String, dynamic> node) {
  final fills = node['fills'];
  if (fills is! List || fills.isEmpty) return null;

  // Walk fills in order (Figma paints bottom-up; the first visible fill is
  // what the observer sees most prominently). For MVP we consume fills[0]
  // when visible, following the spec contract.
  for (final f in fills) {
    if (f is! Map) continue;
    final fill = f.cast<String, dynamic>();
    if (fill['visible'] == false) continue;

    final type = fill['type'] as String?;
    if (type == 'SOLID') {
      final css = _fillSolidCss(fill);
      if (css == null) return null;
      return _FillInfo(solidCss: css);
    }
    if (type == 'GRADIENT_LINEAR') {
      final grad = _gradientLinearCss(fill);
      if (grad != null) return _FillInfo(gradientCss: grad);
      // Unparseable — fall back to first stop solid.
      final fallback = _fillGradientFallbackCss(fill);
      if (fallback != null) return _FillInfo(solidCss: fallback);
    }
    if (type == 'GRADIENT_RADIAL' ||
        type == 'GRADIENT_ANGULAR' ||
        type == 'GRADIENT_DIAMOND') {
      final fallback = _fillGradientFallbackCss(fill);
      if (fallback != null) return _FillInfo(solidCss: fallback);
    }
    // IMAGE fills and other types — MVP ignores.
  }
  return null;
}

String? _fillSolidCss(Map<String, dynamic> fill) {
  final color = fill['color'];
  if (color is! Map) return null;
  final c = color.cast<String, dynamic>();
  final r = (c['r'] as num?)?.toDouble() ?? 0;
  final g = (c['g'] as num?)?.toDouble() ?? 0;
  final b = (c['b'] as num?)?.toDouble() ?? 0;
  final a = (c['a'] as num?)?.toDouble() ?? 1;
  final fillOpacity = (fill['opacity'] as num?)?.toDouble() ?? 1;
  final effectiveA = (a * fillOpacity).clamp(0.0, 1.0);
  return _rgbaCss(r, g, b, effectiveA);
}

String? _fillGradientFallbackCss(Map<String, dynamic> fill) {
  final stops = fill['gradientStops'];
  if (stops is! List || stops.isEmpty) return null;
  final first = stops.first;
  if (first is! Map) return null;
  final s = first.cast<String, dynamic>();
  final color = s['color'];
  if (color is! Map) return null;
  final c = color.cast<String, dynamic>();
  final r = (c['r'] as num?)?.toDouble() ?? 0;
  final g = (c['g'] as num?)?.toDouble() ?? 0;
  final b = (c['b'] as num?)?.toDouble() ?? 0;
  final a = (c['a'] as num?)?.toDouble() ?? 1;
  return _rgbaCss(r, g, b, a);
}

String? _gradientLinearCss(Map<String, dynamic> fill) {
  final stops = fill['gradientStops'];
  if (stops is! List || stops.isEmpty) return null;

  // Figma encodes the gradient axis as two handle positions in unit space
  // (`gradientHandlePositions[0,1]` → start, end). MVP: approximate with a
  // CSS angle derived from the handle delta. When handles are absent, fall
  // back to `to bottom`.
  double angleDeg = 180; // default: top → bottom
  final handles = fill['gradientHandlePositions'];
  if (handles is List && handles.length >= 2) {
    final h0 = handles[0];
    final h1 = handles[1];
    if (h0 is Map && h1 is Map) {
      final m0 = h0.cast<String, dynamic>();
      final m1 = h1.cast<String, dynamic>();
      final dx = ((m1['x'] as num?)?.toDouble() ?? 1) -
          ((m0['x'] as num?)?.toDouble() ?? 0);
      final dy = ((m1['y'] as num?)?.toDouble() ?? 1) -
          ((m0['y'] as num?)?.toDouble() ?? 0);
      // CSS: 0deg == upward; positive rotates clockwise. atan2(dx, -dy) gives
      // that angle in radians. Convert to degrees, normalize to [0, 360).
      final rad = math.atan2(dx, -dy);
      angleDeg = rad * 180 / math.pi;
      if (angleDeg < 0) angleDeg += 360;
      angleDeg = (angleDeg * 10).round() / 10;
    }
  }

  final stopStrs = <String>[];
  for (final s in stops) {
    if (s is! Map) continue;
    final m = s.cast<String, dynamic>();
    final color = m['color'];
    if (color is! Map) continue;
    final c = color.cast<String, dynamic>();
    final r = (c['r'] as num?)?.toDouble() ?? 0;
    final g = (c['g'] as num?)?.toDouble() ?? 0;
    final b = (c['b'] as num?)?.toDouble() ?? 0;
    final a = (c['a'] as num?)?.toDouble() ?? 1;
    final pos = (m['position'] as num?)?.toDouble();
    final rgba = _rgbaCss(r, g, b, a);
    if (rgba == null) continue;
    if (pos != null) {
      stopStrs.add('$rgba ${(pos * 100).round()}%');
    } else {
      stopStrs.add(rgba);
    }
  }
  if (stopStrs.isEmpty) return null;
  return 'linear-gradient(${_niceNum(angleDeg)}deg, ${stopStrs.join(', ')})';
}

// ---------------------------------------------------------------------------
// Strokes
// ---------------------------------------------------------------------------

Map<String, dynamic>? _extractBorder(Map<String, dynamic> node) {
  final strokes = node['strokes'];
  if (strokes is! List || strokes.isEmpty) return null;
  final weight = (node['strokeWeight'] as num?)?.toDouble() ?? 0;
  if (weight <= 0) return null;
  final first = strokes.first;
  if (first is! Map) return null;
  final stroke = first.cast<String, dynamic>();
  if (stroke['visible'] == false) return null;
  final type = stroke['type'] as String?;
  if (type != 'SOLID') return null;
  final css = _fillSolidCss(stroke);
  if (css == null) return null;
  final out = <String, dynamic>{
    'width': _niceNum(weight),
    'color': css,
    'style': 'solid',
  };
  final align = node['strokeAlign'] as String?;
  if (align != null) {
    out['align'] = align;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Corner radius
// ---------------------------------------------------------------------------

Object? _extractBorderRadius(Map<String, dynamic> node, _Box box) {
  final rectRadii = node['rectangleCornerRadii'];
  if (rectRadii is List && rectRadii.length == 4) {
    final tl = (rectRadii[0] as num?)?.toDouble() ?? 0;
    final tr = (rectRadii[1] as num?)?.toDouble() ?? 0;
    final br = (rectRadii[2] as num?)?.toDouble() ?? 0;
    final bl = (rectRadii[3] as num?)?.toDouble() ?? 0;
    if (tl == 0 && tr == 0 && br == 0 && bl == 0) {
      // Fall through to uniform cornerRadius check.
    } else if (tl == tr && tr == br && br == bl) {
      return _collapseRadius(tl, box);
    } else {
      return <String, dynamic>{
        'topLeft': _niceNum(tl),
        'topRight': _niceNum(tr),
        'bottomRight': _niceNum(br),
        'bottomLeft': _niceNum(bl),
      };
    }
  }

  final cornerRadius = (node['cornerRadius'] as num?)?.toDouble();
  if (cornerRadius != null && cornerRadius > 0) {
    return _collapseRadius(cornerRadius, box);
  }
  return null;
}

Object _collapseRadius(double r, _Box box) {
  // Circle heuristic: square-ish shape with radius >= half the min side.
  final minSide = math.min(box.w, box.h);
  if (minSide > 0 && r >= minSide / 2 && (box.w - box.h).abs() < 1.0) {
    return '50%';
  }
  return _niceNum(r);
}

// ---------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------

String? _extractBoxShadow(Map<String, dynamic> node) {
  final effects = node['effects'];
  if (effects is! List || effects.isEmpty) return null;
  final parts = <String>[];
  for (final e in effects) {
    if (e is! Map) continue;
    final eff = e.cast<String, dynamic>();
    if (eff['visible'] == false) continue;
    final type = eff['type'] as String?;
    if (type != 'DROP_SHADOW' && type != 'INNER_SHADOW') continue;

    final color = eff['color'];
    if (color is! Map) continue;
    final c = color.cast<String, dynamic>();
    final r = (c['r'] as num?)?.toDouble() ?? 0;
    final g = (c['g'] as num?)?.toDouble() ?? 0;
    final b = (c['b'] as num?)?.toDouble() ?? 0;
    final a = (c['a'] as num?)?.toDouble() ?? 1;
    final rgba = _rgbaCss(r, g, b, a);
    if (rgba == null) continue;

    final offset = eff['offset'];
    final ox =
        offset is Map ? (offset['x'] as num?)?.toDouble() ?? 0.0 : 0.0;
    final oy =
        offset is Map ? (offset['y'] as num?)?.toDouble() ?? 0.0 : 0.0;
    final radius = (eff['radius'] as num?)?.toDouble() ?? 0.0;
    final spread = (eff['spread'] as num?)?.toDouble() ?? 0.0;

    final prefix = type == 'INNER_SHADOW' ? 'inset ' : '';
    final spreadPart = spread > 0 ? ' ${_niceNum(spread)}px' : '';
    parts.add(
      '$prefix${_niceNum(ox)}px ${_niceNum(oy)}px ${_niceNum(radius)}px$spreadPart $rgba',
    );
  }
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

// ---------------------------------------------------------------------------
// Text nodes
// ---------------------------------------------------------------------------

Map<String, dynamic>? _walkText(
  Map<String, dynamic> node, {
  required _Box box,
  required _Box origin,
}) {
  final raw = (node['characters'] as String?) ?? '';
  final text = raw.trim();
  if (text.isEmpty) return null;
  final clipped = text.length > 500 ? text.substring(0, 500) : text;

  final style =
      (node['style'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  final typography = <String, dynamic>{};

  final family = style['fontFamily'];
  if (family is String && family.isNotEmpty) {
    typography['fontFamily'] = family.split(',').first.trim();
  }
  final size = (style['fontSize'] as num?)?.toDouble();
  if (size != null) typography['fontSize'] = _niceNum(size);
  final weight = (style['fontWeight'] as num?)?.toInt();
  if (weight != null) typography['fontWeight'] = weight;

  double? lineHeightPx = (style['lineHeightPx'] as num?)?.toDouble();
  if (lineHeightPx == null) {
    final lhPct = (style['lineHeightPercent'] as num?)?.toDouble();
    if (lhPct != null && size != null) {
      lineHeightPx = size * lhPct / 100;
    }
  }
  if (lineHeightPx != null) typography['lineHeight'] = _niceNum(lineHeightPx);

  final letterSpacing = (style['letterSpacing'] as num?)?.toDouble();
  final letterUnit = style['letterSpacingUnit'] as String?;
  final hasLetterSpacing = letterSpacing != null &&
      letterSpacing != 0 &&
      !(letterUnit == 'PERCENT' && letterSpacing == 0);
  if (hasLetterSpacing) {
    typography['letterSpacing'] = _niceNum(letterSpacing);
  }

  // Color (from fills[0] solid)
  final textColor = _extractBackground(node)?.solidCss;
  if (textColor != null) typography['color'] = textColor;

  final textAlign = style['textAlignHorizontal'] as String?;
  if (textAlign != null && textAlign != 'LEFT') {
    typography['textAlign'] = textAlign.toLowerCase();
  }

  final textCase = style['textCase'] as String?;
  switch (textCase) {
    case 'UPPER':
      typography['textTransform'] = 'uppercase';
      break;
    case 'LOWER':
      typography['textTransform'] = 'lowercase';
      break;
    case 'TITLE':
      typography['textTransform'] = 'capitalize';
      break;
  }

  return _orderedNode(
    tag: 'span',
    bounds: _relBounds(box, origin),
    text: clipped,
    typography: typography.isEmpty ? null : typography,
  );
}

// ---------------------------------------------------------------------------
// Icon detection
// ---------------------------------------------------------------------------

Map<String, dynamic>? _tryEmitIcon(
  Map<String, dynamic> node, {
  required String type,
  required _Box box,
  required _Box origin,
}) {
  Map<String, String>? iconPayload;

  if (type == 'INSTANCE') {
    iconPayload = _iconFromInstance(node);
  } else if (type == 'VECTOR' || type == 'BOOLEAN_OPERATION') {
    if (box.w < 64 && box.h < 64) {
      final rawName = (node['name'] as String?)?.trim() ?? '';
      if (rawName.isNotEmpty) {
        iconPayload = <String, String>{
          'library': 'unknown',
          'name': _kebab(rawName),
        };
      }
    }
  }

  if (iconPayload == null) return null;

  final svg = _tryReadSvg(node);
  final styles = _collectStyles(node, box: box, selfType: type);
  return _orderedNode(
    tag: 'svg',
    bounds: _relBounds(box, origin),
    icon: iconPayload,
    svgHtml: svg,
    styles: styles.isEmpty ? null : styles,
  );
}

Map<String, String>? _iconFromInstance(Map<String, dynamic> node) {
  final candidates = <String>[];
  final mainComponent = node['mainComponent'];
  if (mainComponent is Map) {
    final m = mainComponent.cast<String, dynamic>();
    final n = m['name'];
    if (n is String) candidates.add(n);
  }
  final cpn = node['componentProperties'];
  if (cpn is Map) {
    for (final v in cpn.values) {
      if (v is Map) {
        final pv = v['value'];
        if (pv is String) candidates.add(pv);
      } else if (v is String) {
        candidates.add(v);
      }
    }
  }
  final selfName = node['name'];
  if (selfName is String) candidates.add(selfName);

  for (final raw in candidates) {
    final parsed = _parseIconName(raw);
    if (parsed != null) return parsed;
  }
  return null;
}

Map<String, String>? _parseIconName(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // Patterns: "Lucide/DollarSign", "Phosphor/House", "LucideIcon/X",
  // "Heroicon/Bell", "Heroicons/bell" — case insensitive.
  final m = RegExp(r'^([A-Za-z]+)\s*[/_:-]\s*(.+)$').firstMatch(s);
  if (m == null) return null;
  final lib = m.group(1)!.toLowerCase();
  final name = m.group(2)!.trim();
  String? resolved;
  if (lib == 'lucide' || lib == 'lucideicon') {
    resolved = 'lucide';
  } else if (lib == 'phosphor') {
    resolved = 'phosphor';
  } else if (lib == 'heroicon' || lib == 'heroicons') {
    resolved = 'heroicons';
  }
  if (resolved == null) return null;
  return <String, String>{
    'library': resolved,
    'name': _kebab(name),
  };
}

String? _tryReadSvg(Map<String, dynamic> node) {
  // Several Figma MCP variants surface SVG markup at these keys.
  for (final key in const ['svg', 'svgString', 'svgHtml']) {
    final v = node[key];
    if (v is String && v.contains('<svg')) return v;
  }
  final es = node['exportSettings'];
  if (es is List) {
    for (final e in es) {
      if (e is Map) {
        final m = e.cast<String, dynamic>();
        for (final key in const ['svg', 'svgString']) {
          final v = m[key];
          if (v is String && v.contains('<svg')) return v;
        }
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Kebab-case a Figma name. Handles:
///   "DollarSign"   → "dollar-sign"
///   "KPI Card"     → "kpi-card"        (runs of uppercase treated as a word)
///   "XMLHttpParser"→ "xml-http-parser" (word boundary between run and next
///                                       lower start)
///   "dollar_sign"  → "dollar-sign"
///   "delta up arrow" → "delta-up-arrow"
String _kebab(String s) {
  if (s.isEmpty) return s;

  // Step 1: insert separators at casing boundaries.
  //   upper → lower: "DollarSign" → "Dollar-Sign"  (before each upper-lower)
  //   upper-run followed by lower: "XMLHttp" → "XML-Http"
  //   letter → digit boundaries ignored (kept contiguous)
  final withSeparators = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final code = ch.codeUnitAt(0);
    final isUpper = code >= 0x41 && code <= 0x5A;
    final prevCh = i > 0 ? s[i - 1] : null;
    final nextCh = i + 1 < s.length ? s[i + 1] : null;

    final prevCode = prevCh?.codeUnitAt(0);
    final prevIsLower =
        prevCode != null && prevCode >= 0x61 && prevCode <= 0x7A;
    final nextCode = nextCh?.codeUnitAt(0);
    final nextIsLower =
        nextCode != null && nextCode >= 0x61 && nextCode <= 0x7A;
    final prevIsUpper =
        prevCode != null && prevCode >= 0x41 && prevCode <= 0x5A;

    if (isUpper && prevIsLower) {
      withSeparators.write('-');
    } else if (isUpper && prevIsUpper && nextIsLower) {
      // End of an upper-case run followed by a word start.
      withSeparators.write('-');
    }
    withSeparators.write(ch);
  }

  // Step 2: lowercase + replace any non-[a-z0-9] run with a single hyphen.
  var out = withSeparators.toString().toLowerCase();
  out = out.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  if (out.startsWith('-')) out = out.substring(1);
  if (out.endsWith('-')) out = out.substring(0, out.length - 1);
  return out;
}

String _slug(String s) {
  final kebab = _kebab(s);
  return kebab.isEmpty ? 'figma-node' : kebab;
}

String? _rgbaCss(double r, double g, double b, double a) {
  if (a <= 0) return null;
  final ri = (r * 255).round().clamp(0, 255);
  final gi = (g * 255).round().clamp(0, 255);
  final bi = (b * 255).round().clamp(0, 255);
  if (a >= 0.999) {
    return 'rgb($ri, $gi, $bi)';
  }
  final ar = _round2(a);
  // Avoid a trailing zero like "1.0" ending up here; we already handle a>=0.999.
  return 'rgba($ri, $gi, $bi, ${_formatAlpha(ar)})';
}

String _formatAlpha(double a) {
  if (a == a.roundToDouble()) return a.toInt().toString();
  // Match extract.mjs's CSS convention for small alphas: keep 1-2 decimals.
  final s = a.toString();
  return s;
}

double _round2(double v) => (v * 100).round() / 100;

num _niceNum(double v) {
  if (v == v.roundToDouble()) return v.toInt();
  // Keep 3 decimals tops; strip trailing zeros.
  final rounded = (v * 1000).round() / 1000;
  return rounded;
}

// ---------------------------------------------------------------------------
// Ordered node construction
// ---------------------------------------------------------------------------

/// Builds a node map with a stable key ordering that mirrors extract.mjs's
/// emission: tag, bounds, text, typography, icon, svgHtml, styles, children.
/// Fields that are null/omitted are dropped.
Map<String, dynamic> _orderedNode({
  required String tag,
  Map<String, dynamic>? bounds,
  String? text,
  Map<String, dynamic>? typography,
  Map<String, String>? icon,
  String? svgHtml,
  Map<String, dynamic>? styles,
  List<Map<String, dynamic>>? children,
}) {
  final out = <String, dynamic>{'tag': tag};
  if (bounds != null) out['bounds'] = bounds;
  if (text != null) out['text'] = text;
  if (typography != null) out['typography'] = typography;
  if (icon != null) out['icon'] = icon;
  if (svgHtml != null) out['svgHtml'] = svgHtml;
  if (styles != null) out['styles'] = styles;
  if (children != null) out['children'] = children;
  return out;
}
