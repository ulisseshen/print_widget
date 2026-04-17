# Pipeline Gaps Analysis: From Pixel Screenshots to Pixel-Perfect Flutter

**Date:** April 2026
**Context:** Post-mortem of the 27-atom + 23-molecule CRM dashboard build from Lovable (promo-flow-pro-78.lovable.app). This document proposes concrete changes to the print_widget CLI and AI skill pipeline based on observed failures.

---

## 1. Current Pipeline (what exists)

```
Source (Figma / Lovable / Stitch / Screenshot)
    │
    ▼
┌─────────────────────────────────────┐
│  EXTRACT  (extract.mjs via Playwright)     │
│  • Full-page screenshot @2x                │
│  • Auto-detected section crops              │
│  • Aggregate design tokens (top-N colors,   │
│    font sizes, padding values, radii)       │
│  • _DESIGN.md with theme mapping            │
│  • Iconography detection (library + name)   │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  BUILD  (AI agent writes Flutter code)     │
│  • Reads reference crops (pixels)          │
│  • Reads _DESIGN.md (aggregate tokens)     │
│  • Writes widget code from scratch         │
│  • Applies conventions.md rules            │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  GENERATE  (print_widget generate)         │
│  • Runs flutter test --update-goldens      │
│  • Outputs PNG per entry per device        │
│  • Extracts crop regions if configured     │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  COMPARE  (print_widget compare)           │
│  • pixelmatch per-region scoring           │
│  • Heatmap diff PNGs                       │
│  • Exit code 0 if all regions >= threshold │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  ITERATE  (iterate.md loop)                │
│  • AI reads generated PNG + reference PNG  │
│  • AI reads heatmap diff                   │
│  • Adjusts code, regenerates, re-compares  │
│  • Revert-on-regression safety             │
│  • 15-iteration hard cap                   │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  REVIEW  (review.md + post-convergence)    │
│  • 5-point visual audit                    │
│  • Token discipline check                  │
│  • Composition + StatelessWidget check     │
│  • Component reuse check                   │
└─────────────────────────────────────┘
```

### What works

- **Structure generation** is reliable. Agents consistently produce correct widget trees with correct data, correct text, correct hierarchy. The Dart compiles, the layout renders, the content is right.
- **Reference capture** via `extract.mjs` produces clean, DOM-aligned crops with automatic section detection.
- **Aggregate token extraction** (`tokens.json`) captures the page-level palette: which colors exist, which font sizes, which radii. The `_DESIGN.md` report maps these to the project theme.
- **The iteration loop** with revert-on-regression prevents code drift and the 15-cap prevents infinite loops.
- **The review checklist** catches visual misses that pixelmatch hides (missing badge backgrounds, truncated text, wrong icon family).

### What breaks

- **Style matching** is unreliable. Agents score 67-95% on pixelmatch because they get the right content but wrong visual values (padding, font sizes, spacing, colors). They have to GUESS these values from pixel inspection of screenshot crops.
- **Heatmap interpretation** fails. The pink diff areas tell agents WHERE something is wrong but not WHAT to change. "Pink at row 3" does not translate to "change padding from 20 to 16px."
- **Token extraction is aggregate, not per-element.** The current `extractTokensInBrowser()` function walks all nodes and counts how many times each font-size / color / padding appears globally. It does NOT tell the agent "the title in THIS card uses 16px/600/Inter with color #0F1729 and 20px padding-top." The agent sees "the page uses 14px (47 times), 16px (23 times), 12px (18 times)" and has to guess which size goes where.
- **No per-element structural data.** The agent has a screenshot crop and an aggregate token list. It does not have a DOM tree with computed styles for each element in the crop. It must visually reverse-engineer the structure from pixels.

---

## 2. The Gap: Missing "Design Discrimination" Step

The core problem is that the pipeline jumps from **pixels** (screenshot crops) to **code** (Flutter widgets) with no structured intermediate representation of what those pixels contain. The `_DESIGN.md` report is a frequency table, not a blueprint.

### What a "Design Spec" should contain

For each section/crop in the reference, the pipeline needs a per-element structural description:

```json
{
  "element": "card_shell",
  "tag": "div",
  "role": "container",
  "bounds": { "x": 0, "y": 0, "w": 320, "h": 200 },
  "styles": {
    "backgroundColor": "rgba(255, 255, 255, 0.7)",
    "borderRadius": "16px",
    "padding": { "top": 20, "right": 20, "bottom": 20, "left": 20 },
    "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
  },
  "children": [
    {
      "element": "header_row",
      "tag": "div",
      "role": "row",
      "display": "flex",
      "alignItems": "center",
      "gap": "12px",
      "children": [
        {
          "element": "icon_badge",
          "tag": "div",
          "role": "icon_container",
          "bounds": { "w": 40, "h": 40 },
          "styles": {
            "backgroundColor": "rgba(11, 162, 132, 0.12)",
            "borderRadius": "50%",
            "display": "flex",
            "alignItems": "center",
            "justifyContent": "center"
          },
          "children": [
            {
              "element": "icon",
              "tag": "svg",
              "library": "lucide",
              "name": "dollar-sign",
              "size": 20,
              "color": "#0BA284",
              "svgHtml": "<svg>...</svg>"
            }
          ]
        },
        {
          "element": "title",
          "tag": "span",
          "text": "Faturamento",
          "styles": {
            "fontSize": "16px",
            "fontWeight": "600",
            "fontFamily": "Inter",
            "color": "#0F1729",
            "lineHeight": "20px"
          }
        },
        { "element": "spacer", "role": "flex_spacer" },
        {
          "element": "count_badge",
          "tag": "span",
          "text": "12",
          "styles": {
            "fontSize": "12px",
            "fontWeight": "500",
            "color": "#6B7280",
            "backgroundColor": "#F3F4F6",
            "borderRadius": "9999px",
            "padding": { "top": 2, "right": 8, "bottom": 2, "left": 8 }
          }
        }
      ]
    }
  ]
}
```

### How to extract it per source type

#### From Lovable / web apps (Playwright)

The biggest opportunity. The DOM IS the spec — we just aren't reading it deeply enough.

Current `extractTokensInBrowser()` walks all nodes and counts frequencies. The new `extractStructureInBrowser(cropBounds)` would:

1. Take the crop bounding box as input (from `_index.json`)
2. Find all DOM elements whose `getBoundingClientRect()` intersects the crop
3. For each element, capture:
   - Tag name, class list, inner text (leaf only)
   - Full computed styles (not just the aggregate — the actual values for THIS element)
   - Bounding box relative to the crop origin
   - Parent-child relationships → produces a tree
4. For SVG elements, capture the `outerHTML` verbatim
5. Prune invisible/decorative wrapper divs (display:contents, zero-size, etc.)
6. Output a JSON tree per crop

This is not speculative — `getComputedStyle()` on a live DOM element returns every CSS property with its resolved value. The data is there; we just need to read it element-by-element instead of aggregating.

**Implementation:** Add a new function `extractStructureInBrowser(clip)` to `extract.mjs` that runs after `collectSectionsInBrowser()` and `extractTokensInBrowser()`. Output as `<crop>_spec.json` alongside each crop PNG.

#### From Figma (MCP)

The Figma MCP server (`get_design_context`) already returns structured node data with:
- Exact fills (colors with opacity)
- Exact spacing (auto-layout padding, gap)
- Exact typography (font family, size, weight, line-height, letter-spacing)
- Exact corner radii
- Layout mode (horizontal, vertical, wrap)

The gap is that this data arrives as Figma-specific JSON, not as the standardized spec format above. A mapping layer would normalize Figma node properties into the same schema used for web extraction.

**Implementation:** A new `figma_spec.mjs` or a Dart function that takes Figma MCP output and produces the same `_spec.json` format.

#### From screenshots (AI vision fallback)

When the source is a static screenshot with no DOM or Figma data, AI vision is the only option. But instead of asking the AI to jump from pixels to code, ask it to jump from pixels to the structured spec:

```
Given this screenshot crop, produce a JSON design spec with:
- Element hierarchy (containers, rows, columns, text, icons)
- Estimated dimensions in pixels (measure from the image)
- Estimated colors (sample from the image, output hex)
- Estimated font sizes (compare against known reference sizes)
- Estimated spacing (measure gaps between elements)
```

This is a much easier task than writing Flutter code because:
1. The output is structured data, not executable code
2. The AI can focus purely on observation, not implementation
3. The spec can be validated and corrected before any code is written

**Implementation:** A prompt template in the skill that guides AI vision to produce the spec JSON. Invoked as a fallback when no DOM/Figma data is available.

---

## 3. The "Text Scaffold" Approach

Once the design spec exists (from any source), the next step is generating a **Flutter widget tree skeleton** that uses only primitive widgets with exact values. No DS tokens, no custom components, no abstractions — just the raw layout with raw numbers.

### Why a scaffold

The current pipeline asks the AI to do three things simultaneously:
1. Build the correct widget tree structure
2. Apply exact visual values (padding, colors, fonts)
3. Map values to DS tokens and project conventions

This is too many concerns at once. The AI reliably handles #1 (structure) but fails at #2 (exact values) and #3 (tokens). The scaffold separates these:

- **Scaffold** = structure (#1) + exact values (#2) from the design spec
- **Tokenization** = mapping raw values to DS tokens (#3) as a mechanical pass

### What a scaffold looks like

Given the design spec from section 2, the scaffold generator produces:

```dart
// AUTO-GENERATED SCAFFOLD — do not edit manually
// Source: promo-flow-pro-78.lovable.app > kpi_card_faturamento
// Spec: print_widget/output/.specs/kpi_card_faturamento_spec.json

class _KpiCardFaturamentoScaffold extends StatelessWidget {
  const _KpiCardFaturamentoScaffold();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF), // rgba(255,255,255,0.7)
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Icon badge
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0x1F0BA284), // rgba(11,162,132,0.12)
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.attach_money, size: 20, color: Color(0xFF0BA284)),
              ),
              const SizedBox(width: 12),
              const Text(
                'Faturamento',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                  color: Color(0xFF0F1729),
                  height: 1.25, // line-height 20px / font-size 16px
                ),
              ),
              const Spacer(),
              // Count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: const Text(
                  '12',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ... remaining elements with exact values from spec
        ],
      ),
    );
  }
}
```

### Key properties of the scaffold

1. **Every value is a literal** — no tokens, no theme lookups, no DS components. `Color(0xFF0BA284)`, `EdgeInsets.all(20)`, `FontWeight.w600`.
2. **Every value comes from the spec** — the generator does NOT guess. If the spec says `padding-top: 20px`, the scaffold says `EdgeInsets` with top: 20.
3. **Icons are placeholders** — the scaffold uses `Icon(Icons.attach_money)` as a placeholder. The real SVG is embedded in the tokenization pass.
4. **The scaffold compiles and renders** — it is a valid Flutter widget that can be captured by `print_widget generate` and compared against the reference.
5. **The scaffold is disposable** — it exists only to verify layout. Once layout matches, the tokenization pass transforms it into production code.

### How the scaffold is generated

This can be done mechanically from the design spec JSON — no AI required for the basic case:

1. Walk the spec tree top-down
2. For each container node → `Container` with exact padding, decoration, size
3. For each flex row → `Row` with exact gap (via `SizedBox` children)
4. For each flex column → `Column` with exact gap
5. For each text leaf → `Text` with exact `TextStyle`
6. For each SVG icon → placeholder `Icon` or `SvgPicture.string`
7. For spacers → `Spacer()` or `Expanded`

A Dart codegen function or a Node script could do this. For more complex layouts (grids, stacks, overlapping elements), the AI fills in what the mechanical generator cannot handle — but it starts from the generated scaffold rather than from scratch.

---

## 4. Two-Pass Architecture

### Pass 1: Structure + Layout Verification

**Input:** Design spec JSON
**Output:** Scaffold widget code + passing layout comparison

Steps:
1. Generate scaffold from spec (mechanical or AI-assisted)
2. `print_widget generate --name=<entry>` → capture scaffold PNG
3. `print_widget compare --name=<entry>` → verify layout alignment
4. If layout fails, the AI adjusts the scaffold (adding/removing SizedBox, adjusting padding, etc.)
5. Iterate until layout matches (positions and sizes of all elements correct)

The threshold for Pass 1 can be lower (0.85-0.90) because colors and font rendering will differ — the goal is positional accuracy only.

**What the AI focuses on:** Widget tree structure, element ordering, flex distribution, alignment. NOT colors, NOT tokens, NOT conventions.

### Pass 2: Style Application + Convention Enforcement

**Input:** Verified scaffold + project theme + conventions.md
**Output:** Production-ready widget code

Steps:
1. **Token mapping** — Replace every `Color(0xFF...)` with the nearest DS token. Replace every raw `EdgeInsets` with a spacing token (if the project has one). Replace every raw `BorderRadius` with a radius token. Replace every raw `TextStyle` with the project's font helper.
2. **Component substitution** — If the scaffold has a `Container(decoration: BoxDecoration(borderRadius: 16, ...))` and the DS has a `CardShell` widget, replace it.
3. **Widget extraction** — Apply the 3-level rule: extract nested subtrees into `_WidgetName extends StatelessWidget` classes. No `_buildXxx()` methods.
4. **Icon embedding** — Replace placeholder `Icon()` with real SVG strings from the spec (captured via Playwright's `outerHTML`).
5. **Regenerate + compare** — Verify that the tokenized version matches the scaffold version. Token swaps MUST be pixel-identical (no score change). If the score changes, the token mapping introduced a visual difference — revert and investigate.

**What the AI focuses on:** Code quality, token discipline, convention compliance. NOT layout, NOT structure — those are locked from Pass 1.

### Why two passes work better than one

| Concern | Pass 1 | Pass 2 |
|---------|--------|--------|
| Widget tree structure | Yes | Locked |
| Element positioning | Yes | Locked |
| Exact pixel values | Yes (from spec) | Mapped to tokens |
| DS token usage | No | Yes |
| StatelessWidget extraction | No | Yes |
| Component reuse | No | Yes |
| Convention compliance | No | Yes |

The current pipeline asks agents to do all of this in one pass, which means every iteration is fighting on multiple fronts. When an agent changes a padding to fix layout AND swaps a color to a token in the same commit, a regression could come from either change. The two-pass separation makes regressions attributable.

---

## 5. Font Rendering Strategy

### The problem

Flutter's Skia text renderer and Chromium's text renderer produce visibly different output even with the same TTF file. The differences:

| Property | Chromium | Flutter (test mode) |
|----------|----------|-------------------|
| `opsz` axis | Auto-applied from variable fonts | Must be explicit via `fontVariations` |
| Subpixel positioning | Fractional | Pixel-snapped |
| `kern` feature | On by default | Must be explicit via `fontFeatures` |
| Hinting | Minimal (HiDPI) | Platform-dependent |
| Anti-aliasing | Subpixel (ClearType-like) | Greyscale |

The practical effect: Inter text at 14px in Flutter renders ~15-20% wider than in Chromium. At 10-12px the delta is worse because the `opsz` axis minimum is 14.

### The systematic gap

With all mitigations applied (`fontVariations: [FontVariation('opsz', fontSize)]`, `fontFeatures: [FontFeature.enable('kern')]`, Inter Variable TTF), the residual gap is:

- **Text-free widgets** (pure shapes, gradients): 98-99% achievable
- **Text-light widgets** (1-3 text elements): 93-96% achievable
- **Text-heavy widgets** (tables, lists, data cards): 85-93% achievable

Agents wasted 10+ iterations in the CRM session trying to cross this ceiling on text-heavy cards. The gap is a rendering engine difference, not a code bug.

### Proposed strategy

#### 1. Use Flutter-native references when possible

The highest-fidelity comparison is Flutter-to-Flutter. For ongoing iteration (not initial capture), the first passing scaffold screenshot becomes the reference. Subsequent changes are compared against this Flutter-native reference, eliminating the cross-engine gap entirely.

**Workflow:**
1. First run: compare against browser reference (lower threshold)
2. Once the visual audit passes, snapshot the Flutter output as the new reference
3. All future iterations compare Flutter-to-Flutter (normal threshold)

**CLI support needed:** `print_widget snapshot --name=<entry>` — copies the current generated PNG to the reference location (`.ref.png` sibling or `.reference/` subfolder).

#### 2. Adaptive thresholds

Instead of a single `compare_threshold: 0.95` for all entries, allow per-entry or per-category thresholds:

```yaml
# print_widget.yaml
compare_threshold: 0.95          # default for Flutter-to-Flutter
cross_engine_threshold: 0.88     # default for browser-to-Flutter

# Per-entry overrides
thresholds:
  home/atoms/performance/delta_badge_positive: 0.90   # small text-heavy atom
  home/molecules/performance/kpi_card: 0.85            # dense data card
```

The iterate loop would read the entry-specific threshold and stop iterating when it's met, instead of chasing the unreachable 0.95 on text-heavy widgets.

#### 3. Text-region masking (future)

The most principled solution: detect text regions in both reference and generated images, mask them (replace with solid rectangles), then run pixelmatch on the masked versions. This measures layout accuracy without penalizing font rendering differences. Text content correctness is verified separately by the 5-point visual audit (check 1: text complete, check 2: font matches).

This is a larger engineering effort but would make the compare step much more useful for cross-engine comparisons.

#### 4. Agent instructions for the gap

Add to `iterate.md`:

```
## Font Rendering Ceiling

When comparing Flutter output against browser references (Lovable, Figma Make, 
deployed web apps), a systematic 5-7% gap exists due to Skia vs Chromium text 
rendering differences. This gap is NOT fixable by code changes.

**Recognition:** If a text-heavy widget scores 88-93% and the heatmap shows pink 
exclusively on text glyphs (not on spacing, backgrounds, or layout), the widget 
has hit the font rendering ceiling.

**Action:** 
1. Verify with the 5-point visual audit that all text is correct (content, font, 
   weight, size)
2. If the audit passes, the entry is converged at its rendering ceiling
3. Do NOT continue iterating on glyph-level differences
4. Report the ceiling in the final output: "Font rendering ceiling reached at 
   X% — text audit passes, residual is cross-engine delta"
```

---

## 6. Specific CLI/Skill Improvements

### 6.1. `print_widget extract --spec` — Per-element design spec extraction

**What:** Extend the existing `extract.mjs` to output per-crop structural specs alongside the aggregate tokens.

**New output per crop:**
```
<state>/<crop>.png          (existing — screenshot crop)
<state>/<crop>_spec.json    (NEW — per-element DOM tree with computed styles)
```

**Implementation in `extract.mjs`:**

```javascript
// NEW function — runs after section detection, once per crop
function extractStructureInBrowser(clipBounds) {
  const { x: cx, y: cy, w: cw, h: ch } = clipBounds;
  
  function walkElement(el, depth = 0) {
    if (depth > 12) return null; // safety limit
    const r = el.getBoundingClientRect();
    
    // Skip elements outside the crop bounds
    if (r.right < cx || r.left > cx + cw || r.bottom < cy || r.top > cy + ch) return null;
    // Skip tiny/invisible elements
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return null;
    if (r.width < 1 || r.height < 1) return null;
    
    const isText = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    const isSvg = el.tagName === 'svg' || el.tagName === 'SVG';
    
    const node = {
      tag: el.tagName.toLowerCase(),
      bounds: {
        x: Math.round(r.left - cx),
        y: Math.round(r.top - cy),
        w: Math.round(r.width),
        h: Math.round(r.height),
      },
      styles: {
        display: cs.display,
        flexDirection: cs.flexDirection !== 'row' ? cs.flexDirection : undefined,
        alignItems: cs.alignItems !== 'normal' ? cs.alignItems : undefined,
        justifyContent: cs.justifyContent !== 'normal' ? cs.justifyContent : undefined,
        gap: parseFloat(cs.gap) > 0 ? cs.gap : undefined,
        backgroundColor: cs.backgroundColor !== 'rgba(0, 0, 0, 0)' ? cs.backgroundColor : undefined,
        borderRadius: parseFloat(cs.borderRadius) > 0 ? cs.borderRadius : undefined,
        padding: {
          top: parseFloat(cs.paddingTop),
          right: parseFloat(cs.paddingRight),
          bottom: parseFloat(cs.paddingBottom),
          left: parseFloat(cs.paddingLeft),
        },
        boxShadow: cs.boxShadow !== 'none' ? cs.boxShadow : undefined,
      },
    };
    
    // Clean up: remove undefined/zero/default values
    if (!node.styles.padding.top && !node.styles.padding.right && 
        !node.styles.padding.bottom && !node.styles.padding.left) {
      delete node.styles.padding;
    }
    Object.keys(node.styles).forEach(k => {
      if (node.styles[k] === undefined) delete node.styles[k];
    });
    
    if (isText) {
      node.text = el.innerText.trim().slice(0, 200);
      node.typography = {
        fontFamily: cs.fontFamily.split(',')[0].trim().replace(/["']/g, ''),
        fontSize: cs.fontSize,
        fontWeight: cs.fontWeight,
        lineHeight: cs.lineHeight,
        letterSpacing: cs.letterSpacing !== 'normal' ? cs.letterSpacing : undefined,
        color: cs.color,
      };
    }
    
    if (isSvg) {
      node.svgHtml = el.outerHTML;
      node.iconClass = el.getAttribute('class') || undefined;
    }
    
    // Recurse into children (skip SVG internals)
    if (!isSvg && el.children.length > 0) {
      const kids = [...el.children]
        .map(child => walkElement(child, depth + 1))
        .filter(Boolean);
      if (kids.length > 0) node.children = kids;
    }
    
    return node;
  }
  
  // Find the root element for this crop region
  const centerEl = document.elementFromPoint(cx + cw / 2, cy + ch / 2);
  let root = centerEl;
  while (root && root.parentElement && root.parentElement !== document.body) {
    const pr = root.parentElement.getBoundingClientRect();
    if (pr.width > cw * 1.5 || pr.height > ch * 1.5) break;
    root = root.parentElement;
  }
  
  return walkElement(root || document.body);
}
```

**CLI flag:** `print_widget extract --spec` enables per-crop spec extraction. Default off for backward compatibility.

### 6.2. `print_widget scaffold` — Generate Flutter skeleton from spec

**What:** A new CLI command that reads a `_spec.json` file and outputs a Flutter widget scaffold.

```bash
print_widget scaffold --spec=print_widget/output/.specs/kpi_card_spec.json \
                      --name=kpi_card \
                      --output=lib/ui/features/home/widgets/kpi_card_scaffold.dart
```

**Implementation:** A Dart codegen function that walks the spec JSON tree and emits Flutter widget code. The mapping is mechanical:

| Spec property | Flutter widget |
|--------------|----------------|
| `display: flex, flexDirection: row` | `Row` |
| `display: flex, flexDirection: column` | `Column` |
| `gap: 12px` | `SizedBox(width: 12)` or `SizedBox(height: 12)` between children |
| `padding: {top: 20, ...}` | `Padding(padding: EdgeInsets.only(...))` |
| `backgroundColor + borderRadius` | `Container(decoration: BoxDecoration(...))` |
| `text + typography` | `Text('...', style: TextStyle(...))` |
| `svgHtml` | `SvgPicture.string('''...''')` |
| `shape: circle` or `borderRadius: 50%` | `BoxDecoration(shape: BoxShape.circle)` |

Edge cases (absolute positioning, z-index stacking, overflow hidden) would require `Stack` + `Positioned` — the generator handles common patterns and emits `// TODO: manual layout needed` for uncommon ones.

### 6.3. `print_widget tokenize` — Map raw values to DS tokens

**What:** A CLI command that takes a scaffold file and a theme reference, and replaces raw values with token references.

```bash
print_widget tokenize --input=lib/.../kpi_card_scaffold.dart \
                      --theme=print_widget/theme-ref.json \
                      --output=lib/.../kpi_card.dart
```

**Implementation:** A Dart-to-Dart transformer (could be AST-based via `analyzer` package, or regex-based for the MVP) that:

1. Finds `Color(0xFF...)` literals → looks up in theme palette → replaces with `context.customColors.xxx`
2. Finds `EdgeInsets.all(N)` → looks up in spacing scale → replaces with `YHAppSpacing.spN`
3. Finds `BorderRadius.circular(N)` → looks up in radius scale → replaces with `YHAppCornerRadiusV2.rN`
4. Finds `TextStyle(fontFamily: 'Inter', fontSize: N, fontWeight: FontWeight.wN)` → replaces with `interText(size: N, weight: N)` or `context.customTexts.xxx`

**Output:** The tokenized file with a comment header listing every substitution made and any values that had no token match (flagged as `// FORCE: no DS token for Color(0xFF8FC3C3)`).

### 6.4. `print_widget snapshot` — Promote generated to reference

**What:** Copy the current generated PNG to the reference position, creating a Flutter-native reference for future comparisons.

```bash
print_widget snapshot --name=kpi_card   # promotes generated → .ref.png
print_widget snapshot --all             # promotes all entries
```

**Why:** After the first browser-to-Flutter comparison passes the visual audit, all subsequent iterations should compare Flutter-to-Flutter. This eliminates the font rendering gap and makes the 0.95 threshold achievable.

### 6.5. Footer chrome filtering in extract

**Problem:** Every agent in the CRM session included Lovable's "Add to Home Screen" footer bar in their widget because the reference crop included it. The agents couldn't distinguish between app content and platform chrome.

**Solution in `extract.mjs`:** Add a `chromePurge` option to `states.json`:

```json
{
  "chromePurge": [
    "footer:has([class*='pwa'])",
    "[class*='lovable-badge']",
    "[id='lovable-footer']",
    "footer:last-child"
  ]
}
```

Before capturing, the script runs `page.evaluate(() => { for (sel of chromePurge) document.querySelectorAll(sel).forEach(el => el.remove()); })`.

Additionally, the skill instructions should explicitly state:

```
Before capturing any Lovable page, remove the Lovable attribution footer and
any "Add to Home" / PWA install banners. These are platform chrome, not app content.
Run: document.querySelector('footer:last-child')?.remove() in the browser console
and verify the page still renders correctly before screenshot.
```

### 6.6. Safe `--delete-old` (already fixed — document the pattern)

**Problem:** 2 of 3 review agents ran `print_widget generate --delete-old` without `--name=`, deleting all reference images across all entries.

**Fix already applied:** The CLI now requires `--name=` when `--delete-old` is used. Without it, the command refuses to run and prints an error.

**Additional safeguard:** Add a `--dry-run` mode that lists what would be deleted without deleting:

```bash
print_widget generate --delete-old --dry-run
# Output: Would delete 47 files in print_widget/output/
# Use --name=<entry> to scope deletion, or --force to confirm.
```

### 6.7. Changes to iterate.md

Add the following sections:

**Font rendering ceiling** (see section 5.4 above)

**Two-pass awareness:**

```
## Pass-Aware Iteration

If a design spec (`_spec.json`) exists for this entry, the iteration has two phases:

### Phase A — Layout (scaffold)
- Goal: positional accuracy of all elements
- Threshold: cross_engine_threshold (default 0.88)
- Changes allowed: widget tree structure, padding, sizing, alignment
- Changes NOT allowed: token swaps, widget extraction, component substitution

### Phase B — Style (tokenization)
- Goal: code quality + pixel preservation
- Threshold: compare_threshold (default 0.95, Flutter-to-Flutter)
- Changes allowed: token mapping, widget extraction, icon embedding
- Changes NOT allowed: layout structure (locked from Phase A)
- Invariant: every token swap must produce zero score change. Any delta = revert.

If no spec exists, fall back to the current single-pass iteration.
```

### 6.8. Changes to review.md

Add after the "meta-rule":

```
## Pre-flight: verify reference is clean

Before running the 5-point audit, verify the reference crop:

1. **No platform chrome** — no Lovable footer, no PWA banners, no cookie popups, 
   no browser scrollbars.
2. **Correct font** — if the reference was captured from a web page, verify the 
   font is actually loaded (not a silent fallback). Check for the Lovable Inter bug:
   page declares `font-family: Inter` but never imports the font file.
3. **Correct viewport** — the reference device dimensions match the Flutter 
   DeviceFrame. A 1440px-wide capture compared against a 390px iPhone frame will 
   never converge.
4. **No animations in progress** — the reference was captured after `settleMs` 
   elapsed. Skeleton loaders, shimmer effects, or fade-in transitions in the crop 
   make the reference unstable.

If any of these fail, re-run the extraction before iterating on code.
```

### 6.9. Changes to conventions.md

Add a section on the two-pass separation:

```
## Scaffold-first development

When a design spec (`_spec.json`) is available:

1. **Start from the scaffold**, not from scratch. The scaffold has the correct 
   structure and exact values from the DOM.
2. **Do not tokenize during layout iteration.** Keep raw values until the layout 
   matches the reference.
3. **Tokenize as a separate commit.** After layout converges, run the tokenization 
   pass. Verify zero score change.
4. **Extract widgets as a separate commit.** After tokenization, extract to 
   StatelessWidget classes. Verify zero score change.

Each commit is independently reversible. If tokenization breaks something, revert 
to the scaffold. If extraction breaks something, revert to the tokenized version.
```

---

## 7. Agent Instruction Improvements

Based on the specific failures observed in the CRM session, these instructions should be added to the agent launch prompt:

### 7.1. Never generate without `--name`

```
CRITICAL: Always use `print_widget generate --name=<entry>` with an explicit 
entry name. NEVER run `print_widget generate` without --name, and NEVER use 
`--delete-old` without --name. Bare generate will regenerate ALL entries and 
waste minutes. Bare --delete-old without --name will DELETE ALL reference images.
```

### 7.2. Read the spec before writing code

```
BEFORE writing any widget code, check for a design spec:
  ls print_widget/output/.specs/<entry>_spec.json

If a spec exists, read it. Use the exact values from the spec (padding, colors, 
font sizes, border radii). Do NOT estimate these values from the screenshot.

If no spec exists, use the _DESIGN.md token report for aggregate values, but 
acknowledge that per-element values must be estimated from visual inspection.
```

### 7.3. Explicit convention checklist at launch

```
CONVENTIONS (non-negotiable — read before writing any code):

□ Every sub-widget is a `class _Name extends StatelessWidget` — NEVER a 
  `Widget _buildName()` method, NEVER a widget-returning getter, NEVER a 
  local function inside build()
□ Every color comes from the DS token system — NEVER `Color(0xFF...)` inline 
  (exception: Colors.transparent, Colors.white, Colors.black)
□ Every spacing value comes from the DS spacing scale where one exists
□ Every TextStyle goes through the project's font helper (e.g., interText())
□ Maximum 3 levels of widget nesting before extraction
□ Use const constructors wherever possible

These rules apply from the FIRST line of code, not as a cleanup pass.
If you find yourself writing `Color(0xFF...)`, STOP and look up the token.
```

### 7.4. Heatmap interpretation guide

```
INTERPRETING PIXELMATCH HEATMAPS:

The diff heatmap (*.diff.png) shows pink/red areas where pixels differ.
Here is how to translate visual patterns into code changes:

| Heatmap pattern | Likely cause | Fix |
|----------------|-------------|-----|
| Pink outline around an element | Wrong border-radius or wrong padding | Check spec for exact borderRadius and padding values |
| Pink fill inside a container | Wrong background color or missing background | Check spec for exact backgroundColor |
| Pink text (all glyphs highlighted) | Wrong font size, weight, or family | Check spec for exact fontSize, fontWeight, fontFamily |
| Pink horizontal band between rows | Wrong vertical spacing (SizedBox height) | Check spec for exact gap between elements |
| Pink vertical band between columns | Wrong horizontal spacing (SizedBox width) | Check spec for exact gap or padding |
| Uniform pink tint across text only | Font rendering engine difference (ceiling) | NOT fixable — verify visual audit passes, then accept |
| Pink at element edges only | Off-by-1 padding or alignment difference | Adjust padding ±1px or check alignment enum |
| Large pink block where reference has content | Missing element in Flutter code | Add the missing widget |
| Large pink block where Flutter has content | Extra element not in reference | Remove the extra widget (possibly platform chrome) |

NEVER describe the heatmap vaguely ("there are pink areas"). ALWAYS be specific:
"Pink on the title text at row 1 — fontSize in spec is 16px, current code has 14px."
```

### 7.5. When to stop iterating

```
STOP CONDITIONS — know when to stop:

1. **Visual audit passes + score >= threshold** → STOP. You are done.
2. **Visual audit passes + score is 88-93% + heatmap is only on text glyphs** 
   → Font rendering ceiling. STOP. Report the ceiling.
3. **Score stagnates (±1%) for 2 iterations + you've tried 3+ different approaches** 
   → STOP and escalate. Do not try a 4th variation of the same fix.
4. **Score drops after a change** → REVERT immediately. Do not try to "fix forward."
5. **Iteration 15** → STOP unconditionally. Emit escalation report.

You have 15 iterations, not infinite. Do not spend 5 iterations on a 1% improvement 
when 3 other entries need attention.
```

### 7.6. Parallel agent coordination

```
PARALLEL AGENT RULES:

1. Each agent owns specific entries. Do NOT touch files outside your assignment.
2. Shared files (theme extensions, font helpers, common components) are READ-ONLY 
   during parallel work. If you need a change to a shared file, flag it in your 
   report — do not edit it.
3. Your print_widget.yaml entry names are your namespace. Run 
   `print_widget generate --name=<your-entry>` only.
4. Do NOT run `print_widget generate` without --name. Do NOT run with --delete-old.
5. Commit your work to a feature branch before the parallel session ends. 
   Conflict resolution happens afterward, not during.
```

---

## 8. Implementation Priority

Ordered by impact-to-effort ratio:

### Phase 1 — Quick wins (1-2 days)

1. **Add font rendering ceiling section to iterate.md** — prevents the #1 time waste (agents chasing uncrossable gaps)
2. **Add agent instruction template** (sections 7.1-7.6) to the skill's launch prompt
3. **Add `chromePurge` to extract.mjs** — prevents footer chrome confusion
4. **Add per-entry threshold support to print_widget.yaml** — stops agents from iterating past the ceiling
5. **`print_widget snapshot`** command — enables Flutter-to-Flutter references

### Phase 2 — Core architecture (1-2 weeks)

6. **`extractStructureInBrowser()` in extract.mjs** — the per-element spec extraction
7. **`print_widget scaffold`** command — mechanical scaffold generation from specs
8. **Two-pass documentation** in iterate.md, conventions.md, review.md
9. **Heatmap interpretation guide** added to iterate.md

### Phase 3 — Full automation (2-4 weeks)

10. **`print_widget tokenize`** command — automatic token mapping with project theme
11. **Figma-to-spec adapter** — normalize Figma MCP output into the same spec format
12. **Text-region masking** for pixelmatch — removes font rendering from the score entirely
13. **AI vision fallback spec generator** — prompt template for when no DOM/Figma data exists

### Phase 4 — Polish

14. **Adaptive threshold inference** — auto-detect text density in crops and adjust threshold
15. **Scaffold diff visualization** — overlay spec bounds on the generated PNG to show layout deltas
16. **Spec editor UI** — VS Code extension panel to manually adjust spec values when extraction misses something

---

## 9. Summary

The current pipeline captures pixels and asks the AI to reverse-engineer the design from those pixels. The proposed pipeline captures the DESIGN (structured DOM data with exact computed styles) and asks the AI to transcribe that design into Flutter code — then verify the transcription via pixel comparison.

The difference:

| | Current | Proposed |
|---|---------|---------|
| **Input to AI** | Screenshot crop + aggregate token list | Per-element spec with exact values |
| **AI's task** | Reverse-engineer design from pixels | Transcribe structured data to Flutter |
| **Visual comparison** | Single gate (code vs reference) | Two gates (scaffold vs reference, then tokenized vs scaffold) |
| **Font rendering gap** | Causes 10+ wasted iterations | Recognized and bypassed |
| **Token discipline** | Enforced at review time (after the fact) | Enforced by tooling (tokenize command) |
| **Convention compliance** | Enforced at review time | Enforced by tooling (scaffold extraction) |

The AI is excellent at transcription and terrible at estimation. Give it exact values and it will build exact widgets. Ask it to guess values from pixels and it will get them wrong — every time, on every project, with every model.
