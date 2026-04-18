# Figma → spec adapter (Phase 7)

`print_widget figma-spec` normalizes a Figma MCP `get_design_context` response
into the same **spec v1 envelope** that `extract.mjs` emits from browser DOM.
Consumers — `scaffold_generator.dart` and `tokenizer.dart` — don't care which
side produced the spec; they only see the envelope.

Browser side:
```
URL ─► extract.mjs ─► <crop>_spec.json ─► scaffold ─► tokenize
```

Figma side (Phase 7):
```
Figma MCP JSON ─► figma-spec ─► <node>_spec.json ─► scaffold ─► tokenize
                                       ▲
                                       └─ byte-compatible with the browser path
```

## Status

**Shipped (code); empirical validation pending.** The adapter was built
against the stable Figma MCP public shape and 3 synthetic fixtures. No live
Figma-sourced project has been run through end-to-end yet; the first real
driver becomes the validation target.

## CLI

```bash
# Normalize a saved MCP response into a spec file:
print_widget figma-spec \
  --input=figma-response.json \
  --output=print_widget/output/home/.reference/crops/01-card_spec.json

# Inspect via stdout:
print_widget figma-spec --input=figma-response.json --stdout

# Full chain (no intermediate file):
print_widget figma-spec --input=figma.json --output=spec.json
print_widget scaffold --spec=spec.json --stdout

# Attach a live URL + custom state label:
print_widget figma-spec --input=figma.json --stdout \
  --source-url=https://www.figma.com/design/<fileKey>/<name>?node-id=1-234 \
  --state-name=kpi_card
```

| Flag | Purpose |
|---|---|
| `--input=<path>` | Path to the decoded MCP JSON response. Required. |
| `--output=<path>` | Destination for the spec JSON. Required unless `--stdout`. |
| `--stdout` | Print the spec to stdout and exit. |
| `--force` | Overwrite an existing `--output` file. |
| `--source-url=<url>` | Recorded under `source.url` in the envelope (default `null`). |
| `--state-name=<label>` | Recorded under `source.state` (default: root node's `name`). |
| `--json` | Machine-readable summary on stdout (node count, state, output path). |

## Envelope

Byte-compatible with `extract.mjs` output:

```json
{
  "$version": "1.0",
  "source": {
    "url": "<--source-url, or null>",
    "state": "<--state-name, or root.name>",
    "extractor": "figma_to_spec"
  },
  "crop": {
    "file": "<basename(output).png>",
    "text": "<root.name>",
    "bounds": {"x": "<viewport-absolute x>", "y": "...", "w": "...", "h": "..."}
  },
  "root": { /* walked node tree, bounds are root-relative */ }
}
```

Key ordering is stable inside each node: `tag`, `bounds`, `text`, `typography`,
`icon`, `svgHtml`, `styles`, `children`. Running the adapter twice on the same
input produces byte-identical output.

## Normalization rules

### Layout

| Figma | Spec output |
|---|---|
| `layoutMode: "VERTICAL"` | `styles.display: "flex"`, `styles.flexDirection: "column"` |
| `layoutMode: "HORIZONTAL"` | `styles.display: "flex"` (row default, `flexDirection` omitted) |
| `layoutMode: "NONE"` / absent | parent: `styles.position: "relative"`; each child: `styles.position: "absolute"`, `top`, `left` relative to parent |
| `itemSpacing: N` (on flex parent) | `styles.gap: N` |
| `paddingLeft/Top/Right/Bottom` (any > 0) | `styles.padding: {top, right, bottom, left}` |
| `primaryAxisAlignItems` | `justifyContent`: `MIN` → `flex-start`, `CENTER` → `center`, `MAX` → `flex-end`, `SPACE_BETWEEN` → `space-between` |
| `counterAxisAlignItems` | `alignItems`: `MIN` → `flex-start`, `CENTER` → `center`, `MAX` → `flex-end`, `STRETCH` → `stretch` |
| `layoutGrow: 1` on child | `styles.flexGrow: 1` |

### Fills / background

- `fills[0].type === "SOLID"` (first visible fill): `styles.backgroundColor`
  = `rgb(R, G, B)` or `rgba(R, G, B, A)`. RGB are rounded to 0–255 ints
  from 0–1 floats; A is preserved at up to 2 decimals. `fills[0].opacity`
  multiplies `color.a`.
- `fills[0].type === "GRADIENT_LINEAR"`: `styles.backgroundImage`
  = `linear-gradient(<deg>, <stops>)`. Angle derived from
  `gradientHandlePositions`; falls back to `180deg` (top → bottom) when
  handles are missing.
- `GRADIENT_RADIAL` / `GRADIENT_ANGULAR` / `GRADIENT_DIAMOND`: **best-effort
  fallback** to the first stop's solid color in `styles.backgroundColor`.
- Fills with `visible: false` are skipped.

### Strokes / border

- `strokes[0].type === "SOLID"` with `strokeWeight > 0`:
  `styles.border: {width, color, style: "solid", align}`. `strokeAlign`
  (`INSIDE` / `OUTSIDE` / `CENTER`) is captured as `border.align` for
  downstream renderers that care; scaffold codegen ignores it.

### Corner radius

- Uniform `cornerRadius: N` → `styles.borderRadius: N` (number).
- `rectangleCornerRadii: [tl, tr, br, bl]` with all four equal collapses to
  a single number; when mixed, emits an object with 4 named corners.
- Square-ish shape (|w − h| < 1) with `cornerRadius ≥ min(w,h)/2` →
  `styles.borderRadius: "50%"` (matches `extract.mjs`'s circle convention).

### Effects

- `DROP_SHADOW` (visible): CSS `<x>px <y>px <radius>px <spread>px <rgba>`.
- Multiple `DROP_SHADOW` are comma-joined into a single `boxShadow` string.
- `INNER_SHADOW` composes with an `inset ` prefix.
- `LAYER_BLUR` / `BACKGROUND_BLUR` are skipped for MVP.

### Opacity / visibility

- `opacity < 1` → `styles.opacity` (rounded to 2 decimals).
- `visible: false` → node omitted entirely (dropped from parent's `children`).

### Text nodes (`type === "TEXT"`)

- `text` = `characters` trimmed, clipped to 500 chars.
- `typography.fontFamily` = first comma-separated entry of `style.fontFamily`.
- `typography.fontSize` = `style.fontSize` (number).
- `typography.fontWeight` = `style.fontWeight` (number).
- `typography.lineHeight` = `style.lineHeightPx` if present, else
  `style.fontSize × style.lineHeightPercent / 100`.
- `typography.letterSpacing` = `style.letterSpacing` when non-zero and not
  `letterSpacingUnit === "PERCENT"` with value 0.
- `typography.color` = first SOLID fill using the same RGB conversion.
- `typography.textAlign` = lowercased `style.textAlignHorizontal` when not
  `LEFT` (which is omitted).
- `typography.textTransform`: `UPPER` → `uppercase`, `LOWER` → `lowercase`,
  `TITLE` → `capitalize`, other values omitted.

### Icons

- `INSTANCE` with a `mainComponent.name`, `componentProperties.*.value`, or
  node `name` matching `<Lib>/<Icon>` (case-insensitive, library prefix must
  be one of `lucide` / `lucideicon` / `phosphor` / `heroicon` / `heroicons`):
  `icon: {library, name: kebab-case(icon-name)}`, `tag: "svg"`.
- `VECTOR` / `BOOLEAN_OPERATION` with bounding box under 64×64 are treated
  as anonymous icons: `icon: {library: "unknown", name: kebab(node.name)}`.
- `svgHtml` is emitted **only** when the MCP response surfaces SVG markup
  (at `svg` / `svgString` / `exportSettings[].svg`). Otherwise omitted —
  scaffold falls back to a placeholder `SvgPicture.string` with TODO.

### Bounds

- `bounds: {x, y, w, h}` on the root is viewport-absolute (rounded to int)
  and lives in `crop.bounds`.
- `bounds` inside `root` and each descendant are rounded integers relative
  to the root's origin.
- `absoluteBoundingBox` can be floats; rounding happens on emit.
- Nodes with `w < 0.5` or `h < 0.5` are skipped.

### Recursion

- Recurses into `FRAME`, `GROUP`, `COMPONENT`, `COMPONENT_SET`, `INSTANCE`
  (when no icon match — otherwise icon becomes a leaf), `SECTION`.
- Leaves: `TEXT`, `VECTOR`, `BOOLEAN_OPERATION`, `RECTANGLE`, `ELLIPSE`,
  `LINE`, `REGULAR_POLYGON`, `STAR`.
- Silently omitted: `SLICE`, `STICKY`, `CONNECTOR`, `SHAPE_WITH_TEXT`,
  `CODE_BLOCK`, `WIDGET`, `STAMP`, and anything else unknown.

## Known limits (MVP)

- **No live Figma REST calls.** This is a pure-data normalization over a
  JSON file the caller already has. Fetch → save → adapt → scaffold.
- **No SVG synthesis.** If the MCP response doesn't include SVG markup for
  a vector / icon node, the spec omits `svgHtml` and scaffold emits a
  placeholder with a TODO. A follow-up feature can render SVG from vector
  paths, but that's out of scope here.
- **Variant / component-property resolution is string-matching only.**
  Icon detection looks at `mainComponent.name`, `componentProperties`
  values (when strings), and the node's own `name`. Nested InstanceSwap
  properties aren't resolved.
- **`GRADIENT_RADIAL` / `GRADIENT_ANGULAR` / `GRADIENT_DIAMOND`** fall back
  to the first stop's solid color. The scaffold will render as a flat
  background — it's explicitly lossy.
- **`LAYER_BLUR` / `BACKGROUND_BLUR`** are dropped entirely. Scaffold has
  no `backdrop-filter` equivalent shape yet.
- **Shape drift resilience.** Unknown keys are silently ignored; unknown
  node types are silently omitted. The adapter never throws on a valid
  JSON document — only on a missing root node.

## Pitfalls (observed while implementing)

- **Figma colors are 0–1 floats, CSS is 0–255 ints.**
  `{r: 0.043, g: 0.635, b: 0.514}` → `rgb(11, 162, 131)`.
- **Effective alpha = `color.a × (fill.opacity ?? 1)`.** Both fields are
  commonly set — missing this yields wrong-opacity backgrounds.
- **`absoluteBoundingBox` is float.** Round with `.round()` when emitting
  `bounds`; preserve floats in `typography` (fontSize 14.5 is valid).
- **Idempotency depends on stable key insertion order.** Dart `Map`
  preserves insertion order — the adapter inserts in a deterministic
  sequence (`tag`, `bounds`, `text`, `typography`, `icon`, `svgHtml`,
  `styles`, `children`) so the emitted JSON is byte-stable.

## Testing

Unit tests per rule: `test/codegen/figma_to_spec_test.dart` (44 assertions).
Integration tests via `Process.run`: `test/codegen/figma_integration_test.dart`
(19 cases — including the 3-fixture golden matches and 3 `figma-spec →
scaffold` chain tests that assert no TODO markers on simple inputs).

Synthetic fixtures under `test/codegen/figma_fixtures/`:
- `flex_card.mcp.json` + `.expected_spec.json` — FRAME (VERTICAL) with
  padding 20, gap 12, white 70% bg, one drop shadow, 2 text children.
- `icon_row.mcp.json` + `.expected_spec.json` — FRAME (HORIZONTAL) with
  gap 8, padding 4. Contains `Lucide/DollarSign` INSTANCE + a TEXT.
- `absolute_badge.mcp.json` + `.expected_spec.json` — FRAME (`layoutMode:
  NONE`) with centered TEXT + corner RECTANGLE badge (cornerRadius 9999).

Run the suite:
```bash
flutter test test/codegen/figma_to_spec_test.dart \
             test/codegen/figma_integration_test.dart
```

## Follow-up work

1. **Live Figma driver.** First real Figma-sourced project validates the
   shape assumptions against an actual MCP response; the canary-validation
   doc gets empirical numbers.
2. **SVG from vector paths.** For nodes without pre-rendered SVG, walk the
   vector data and emit `svgHtml` directly.
3. **Variant property resolution.** Follow
   `componentProperties.<name>.preferredValues` / InstanceSwap targets to
   find the actual swapped-in icon component name.
4. **JSON Schema for v1.1.** Once the envelope stabilizes under both
   extractors, encode it as JSON Schema and enforce at the adapter
   boundary.
