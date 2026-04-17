# Spec v1 Format

Per-crop structural spec emitted by `extract.mjs` alongside every PNG crop. Closes the pixel-guessing gap by giving downstream tooling (agents writing Flutter, or `print_widget scaffold` once landed) exact values from the DOM instead of forcing them to reverse-engineer from screenshots.

## File location

```
<output>/<NN-stateName>/
├── fullpage.png
├── 01-<slug>.png           # crop screenshot
├── 01-<slug>_spec.json     # ← this document (structural spec)
├── 02-<slug>.png
├── 02-<slug>_spec.json
├── _index.json             # crop index, now includes `spec` filename
├── tokens.json             # aggregate tokens (unchanged)
└── _DESIGN.md              # token narrative (unchanged)
```

## Envelope

```json
{
  "$version": "1.0",
  "source": {
    "url": "https://promo-flow-pro-78.lovable.app/",
    "state": "initial",
    "extractor": "extract.mjs"
  },
  "crop": {
    "file": "02-kpi-card.png",
    "text": "Faturamento 12",
    "bounds": { "x": 32, "y": 180, "w": 344, "h": 160 }
  },
  "root": { /* Node, see below */ }
}
```

`bounds` in `crop` are viewport-absolute (matching `_index.json`). Bounds inside `root` are **relative to the crop origin**.

## Node shape

```typescript
interface Node {
  tag: string;                  // lowercase tag name (div, span, svg, ...)
  bounds: { x, y, w, h };       // relative to crop origin, rounded
  text?: string;                // present when element has direct text children
  typography?: Typography;      // present when `text` is present
  icon?: { library, name };     // present on <svg> when detected
  svgHtml?: string;             // present on <svg>, full outerHTML for round-trip
  styles?: Styles;              // only non-default values
  children?: Node[];            // only present when non-empty
}
```

### Typography (text leaves only)

```json
{
  "fontFamily": "Inter",
  "fontSize": 16,
  "fontWeight": 600,
  "lineHeight": 20,
  "color": "rgb(15, 23, 41)",
  "letterSpacing": "0.5px",
  "textAlign": "center",
  "textTransform": "uppercase"
}
```

- `fontSize` and `lineHeight` are numbers (px) when resolvable, otherwise the raw string (`"normal"`).
- `fontWeight` is a number (100–900) when resolvable, otherwise the raw token (`"bold"`).
- `letterSpacing`, `textAlign`, `textTransform` are **omitted** when default.

### Styles vocabulary (all keys optional)

| Key | Type | Notes |
|---|---|---|
| `display` | string | Only emitted when non-`block`/`inline` |
| `flexDirection` | string | Only when `display: flex` or `inline-flex` |
| `alignItems`, `justifyContent` | string | Only when non-default |
| `gap` | number (px) | |
| `flexWrap` | string | Only when non-`nowrap` |
| `flexGrow` | number | Only when > 0 |
| `padding` | `{top, right, bottom, left}` (px) | Emitted if any side > 0 |
| `margin` | `{top, right, bottom, left}` (px) | Emitted if any side > 0 |
| `backgroundColor` | string (rgba/rgb/hex) | |
| `backgroundImage` | string | Raw CSS value, typically a gradient |
| `borderRadius` | number (px) or string | String when `%` (e.g. circles), number when px |
| `border` | `{width, color, style}` | Only on visible borders (width > 0) |
| `boxShadow` | string | Raw CSS value |
| `position` | string | Only when non-`static` |
| `top`, `right`, `bottom`, `left` | string | Only when `position` is non-`static` and side is non-`auto` |
| `overflow` | string | Only when non-`visible` |
| `transform` | string | Only when non-`none` |
| `zIndex` | string | Only when non-`auto` |
| `opacity` | number (0–1) | Only when < 1 |
| `textOverflow` | string | On text leaves when `ellipsis` |

### Icon detection

When a `<svg>` is encountered, the walker detects the icon library from the element's classes or `<use>` sprite references:

- `lucide` / `lucide-<name>` → `{ library: "lucide", name: "<name>" }`
- `ph ph-<name>` → `{ library: "phosphor", name: "<name>" }`
- `heroicon-<name>` → `{ library: "heroicons", name: "<name>" }`
- `icon-<name>` (sprite) → `{ library: "sprite", name: "<name>" }`
- Fallback: `{ library: "unknown", name: "<cls[0]>" }`

`svgHtml` is always captured so downstream tools can embed the exact SVG via `flutter_svg`'s `SvgPicture.string(...)`.

## How agents should consume the spec

Before writing any Flutter code for a crop, **always read `<crop>_spec.json`** first:

1. Walk the `root` tree top-down — this is the widget tree structure you'll mirror in Flutter
2. For every text leaf, copy `typography` values **verbatim** into the `TextStyle` — do NOT estimate from the PNG
3. For every container with `styles.padding`, `styles.borderRadius`, `styles.backgroundColor` — use those exact values, do NOT guess from pixels
4. For SVG nodes with `icon.library === "lucide"` (or phosphor, heroicons) — look up the project's icon helper and use the matching icon
5. For SVG nodes without a recognizable library — embed the `svgHtml` via `SvgPicture.string(...)` (requires `flutter_svg` in pubspec)

The PNG is the acceptance test, not the source. Reading from pixels is what causes the 67-95% pixelmatch band documented in `gaps-analysis.md`.

## Chrome purge (DOM cleanup before capture)

Add to `states.json` (top-level or per-state) to strip platform UI:

```json
{
  "url": "...",
  "chromePurge": [
    "footer:last-child",
    "[class*='lovable-badge']",
    "[id='lovable-footer']",
    "[class*='pwa-install']"
  ],
  "states": [
    {
      "name": "kpi-detail",
      "chromePurge": ["[class*='cookie-banner']"],
      "steps": [...]
    }
  ]
}
```

Per-state `chromePurge` overrides config-level entirely (not merged). Invalid selectors are skipped silently.

## Known limitations of v1

- **Root selection is heuristic.** When crops span non-contiguous DOM (rare but possible with CSS grid), the walker may capture too much or too little. Manual fixup with a tighter crop usually fixes it.
- **CSS custom properties are resolved.** If the page uses `color: var(--brand-500)`, the spec captures the resolved `rgb(...)` — not the token name. Token mapping happens later via `theme-ref.json` and the `tokenize` command (Phase 5).
- **Grid layouts are captured as `display: grid` with raw template strings.** The scaffold generator (Phase 4) will need special handling; for now agents should read the raw strings.
- **`::before` and `::after` pseudo-elements are not walked.** If a design uses them structurally (e.g. a decorative line), the spec will be missing that node. Mitigation: inspect the reference crop manually and add the element by hand.
- **No JSON Schema validation.** v1 is permissive. If we hit real interop issues (multiple consumers, API rot), v1.1 will add a schema.

## Example: icon_badge (canary)

A tiny circular icon container + centered SVG:

```json
{
  "$version": "1.0",
  "source": { "url": "https://example/", "state": "initial", "extractor": "extract.mjs" },
  "crop": { "file": "03-icon-badge.png", "text": "", "bounds": { "x": 20, "y": 120, "w": 40, "h": 40 } },
  "root": {
    "tag": "div",
    "bounds": { "x": 0, "y": 0, "w": 40, "h": 40 },
    "styles": {
      "display": "flex",
      "alignItems": "center",
      "justifyContent": "center",
      "backgroundColor": "rgba(11, 162, 132, 0.12)",
      "borderRadius": "50%"
    },
    "children": [
      {
        "tag": "svg",
        "bounds": { "x": 10, "y": 10, "w": 20, "h": 20 },
        "icon": { "library": "lucide", "name": "dollar-sign" },
        "svgHtml": "<svg class=\"lucide lucide-dollar-sign\" width=\"20\" height=\"20\" ...>...</svg>",
        "styles": { "color": "rgb(11, 162, 132)" }
      }
    ]
  }
}
```

From this, scaffold codegen (or an agent) produces a Flutter widget with exact `Color(0x1F0BA284)`, `BoxShape.circle`, `SvgPicture.string(...)` — zero pixel guessing.
