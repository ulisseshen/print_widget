# Lovable Adapter

## Purpose

Convert a Lovable.dev URL (or any deployed React web app) into a Flutter widget with visual validation against the live reference. The adapter wires together `smart-extract-design` (reference capture), the Token Bundle process (theme mapping), and `print_widget compare` (objective convergence).

## Critical pre-flight gotchas

Read every one of these before touching a Lovable URL. Each represents hours of debugging lost by someone who skipped it.

1. **Lovable declares fonts without importing them.** Nearly every Lovable project puts `font-family: Inter, sans-serif` (or similar) in CSS but never `@import`s the font file. The browser silently falls back to the OS sans-serif — macOS Playwright falls back to Helvetica Neue, Linux to DejaVu. Any reference captured without force-loading the font is rendered in the **wrong font**, and every downstream comparison lies. Fix: add `forceFonts:` to `states.json` for extract:
   ```json
   { "forceFonts": ["Inter:wght@300;400;500;600;700"] }
   ```
   The extract will inject the Google Fonts stylesheet and await `document.fonts.ready` before capture.

2. **Use the published URL, not the preview URL.** `preview--xxx.lovable.app` requires authentication and falls through to the Lovable login page. The same project without `preview--` (e.g. `xxx.lovable.app`) is public. Always ask for the published URL.

3. **Inspect the leaf element, not the container.** Tailwind classes like `text-[12px]` often override parent sizes on the inner `<span>`. A walk-up inspector that stops at the pill container returns the wrong font size. Always descend to `childNodes.length === 0` with text, or trust the DevTools element panel the user screenshots — DevTools is the oracle.

4. **Flutter's Inter is ~15% wider than Chromium's Inter** at the same size, even from the same TTF file. Causes: Chromium auto-applies the `opsz` axis from variable fonts, Flutter does NOT; subpixel positioning differs; kerning is on by default in Chromium. Partial fix — use Inter Variable (from rsms/inter releases, not fontsource static) plus `FontVariation('opsz', fontSize)` + `FontFeature.enable('kern')` on every TextStyle. Minimum `opsz` on Inter is 14, so text < 14px still has a residual ~5% width gap that you compensate for by bumping DeviceFrame width and padding the reference with `magick -gravity west -extent WxH`.

5. **Custom SVG icons → embed verbatim with `flutter_svg`.** Do not substitute with Material Symbols. Capture the `svg.outerHTML` from the Lovable DOM (filter by `.lucide` class for Lucide icons), paste as a `const` String literal, render with `SvgPicture.string(svg, colorFilter: ColorFilter.mode(brandColor, BlendMode.srcIn))`. This also applies to decorative SVGs (e.g. concentric circles in card corners) — replace any Flutter CustomPainter you were about to write with the inline SVG.

## Flow

### 1. User provides a Lovable URL

Example: `https://my-app.lovable.app` (without the `preview--` prefix). Confirm the URL resolves and is publicly reachable before doing anything else.

### 2. Phase 0 — Viewport contract

Ask the user for the target viewport, or detect it from the site's media queries. Pin it on both sides. **Fail fast if unclear** — see `viewport.md`. Do not skip this step "just to see what comes out"; a mismatched viewport poisons every subsequent phase.

### 3. Extract reference

Invoke the `smart:extract-design` skill (install via `print_widget skills --only=extract`) with the URL and the pinned viewport. It produces, under `/tmp/extract-<slug>/01-<state>/`:

- `fullpage.png` — reference image of the full scrollable page
- `<NN>-<section>.png` — section crops, auto-detected from the DOM (e.g. `01-hero.png`, `02-features.png`)
- `<NN>-<section>_spec.json` — **per-element structural spec** (DOM subtree with computed styles, typography, icons). This is the IR — exact values for padding, fontSize, backgroundColor (with alpha), borderRadius. Use this as the primary source for implementation. See `doc/pipeline-gaps/spec-format.md`.
- `_index.json` — crop bounding boxes (x, y, w, h) per region + spec filename per crop
- `tokens.json` — raw tokens (colors, spacing, typography, radii, optionally iconography)
- `_DESIGN.md` — theme mapping report with ✅ / 🎨 / ⚠️ / ❌ markers per token

### 4. Copy to the print_widget reference dir

```bash
mkdir -p print_widget/output/<feature>/.reference/crops
cp /tmp/extract-<slug>/01-<state>/fullpage.png print_widget/output/<feature>/.reference/
cp /tmp/extract-<slug>/01-<state>/[0-9]*.png print_widget/output/<feature>/.reference/crops/
cp /tmp/extract-<slug>/01-<state>/[0-9]*_spec.json print_widget/output/<feature>/.reference/crops/
cp /tmp/extract-<slug>/01-<state>/_index.json print_widget/output/<feature>/.reference/
```

This is the layout `print_widget compare` expects. The `_spec.json` files sit next to their crops and follow implementation through to the review stage.

### 5. Build the Token Bundle from _DESIGN.md

Walk each token row in `_DESIGN.md` and decide:

- ✅ **exact match** → use the existing project token as-is
- 🎨 **forced override** → use the override token the report suggests (brand color pinned, etc.)
- ⚠️ **close match** → ask the user: reuse the nearest existing token, or create a new one? Do not decide silently.
- ❌ **new color/value** → propose a new token with both light and dark values; add to the project theme before implementation

The output of this step is a concrete mapping table: *extracted token → project token*. Every value used in step 7 must come from this table.

### 6. Design-system component discovery (MANDATORY — see `conventions.md` for the full rules)

Grep existing components (`lib/ui/`, `lib/components/`, `lib/design_system/`, `packages/*_design_system/`, `lib/ui/features/*/widgets/`) and map each visible section from step 3's crops to an existing widget where possible. **Do not create custom widgets when the project already has them** — that's how parallel component sets get born.

Two tiers to search for:

- **Tier A — primitive components**: buttons, cards, chips, pills, toggles, tabs, badges, filters, form fields.
- **Tier B — composite components**: tables, data grids, paginated lists, filter rows, search fields, kanban columns, timelines, card-list hybrids, pagination strips. **Whenever a section shows a row of header cells above repeated body rows, STOP and grep for an existing table** (`YHAdaptiveTable`, `YHSimpleTable`, `YHDataGrid`, `CardOrdersTable`, or any feature-specific `*Table` / `*Grid` / `*List`). Do NOT hand-roll `_Table` / `_Row` / `_Cell` private classes without first verifying nothing exists.

Search twice per section: once by primitive name (card, chip, button) and once by domain name (orders list, pedidos table, clients grid). The second search is what finds feature-specific components that have become the app's pattern without being in the DS package.

For each section in `_index.json`, record: *section → existing component* or *section → needs-new-widget (why)*.

**When the match is partial — right primitive, wrong visual specs** (different row height, different padding, different header style): invoke `AskUserQuestion` before writing any code. Present four options: (1) use as-is and accept the delta, (2) improve the existing component in place, (3) create a V2 variant (see the `SideBarV2` / `CustomColorsV2` precedent), or (4) hand-roll a new one scoped to this feature. Do NOT default to option 4 just because it's faster — the user may want option 1/2/3, and choosing wrong here is the single highest source of technical debt on Lovable ports.

### 7. Implement the Flutter widget

**Before writing any code, read the `_spec.json` for the crop.** It contains exact values (padding, fontSize, borderRadius, backgroundColor with alpha, icon library/name) that you would otherwise be guessing from pixels. Pixel-guessing is the #1 source of iteration waste — documented in `doc/pipeline-gaps/gaps-analysis.md` and empirically 67–95% pixelmatch scoring band.

The typical read flow for one crop:
1. `cat print_widget/output/<feature>/.reference/crops/<NN>-<section>_spec.json`
2. Walk the `root` tree — this is the widget tree structure
3. For each text leaf, copy `typography` into `TextStyle` verbatim
4. For each container, use `styles.padding` / `styles.borderRadius` / `styles.backgroundColor` exact values — mapped to project tokens per step 5
5. For SVGs, use `icon.library` + `icon.name` to find the project's icon helper; if unknown library, embed `svgHtml` via `SvgPicture.string(...)`

The PNG is the acceptance test (via `print_widget compare`), not the source of truth. Read the spec.

Constraints:

- Use **only** mapped tokens from step 5. No raw hex codes. No raw `EdgeInsets.all(16)` — use spacing tokens.
- Mirror the DOM structure implied by the spec; keep widget nesting shallow (extract to private `StatelessWidget` classes, no `_buildXxx()` methods).
- Add to `print_widget/config.dart` as a `page(...)` entry:

  ```dart
  page('<feature>', MyFeatureScreen(),
    devices: [/* the pinned viewport from Phase 0 */],
    cropsFrom: 'print_widget/output/<feature>/.reference/_index.json',
  )
  ```

  `cropsFrom` tells `generate` to produce crops at the same bounding boxes as the reference, so `compare` has matched pairs.

### 8. Generate + compare

```bash
print_widget generate --name=<feature>
print_widget compare  --name=<feature>
```

Read the per-region scores and heatmaps. Exit code 0 means done; exit code 1 means at least one region is still below threshold.

### 9. Iterate

Follow `iterate.md`:

- Make the smallest change that targets the worst-scoring region
- Regenerate, recompare
- **Revert on regression** (if a change drops any previously-passing region below threshold, undo it)
- **Escalate on hard cap** (if 15 iterations pass without net improvement, stop and report the residual diff)

## Re-extraction

If the user changes the Lovable design later:

1. Re-run `smart:extract-design` with the same slug
2. Diff the new `_DESIGN.md` against the old one
3. Surface which tokens changed and which sections now have different bounding boxes
4. Decide per-row whether to update the Flutter implementation or pin to the old reference

Do not silently overwrite the old reference — the diff is what tells the user whether their design actually drifted or the extractor just got unlucky.

## Parallel agent teams (5+ sibling components)

When the Lovable page contains 5+ sibling components under one container (a row of KPI cards, a grid of tiles, a list of chips), use the **parallel agent team** pattern from `parallel.md`. That reference file owns the provider-agnostic rules — artifact contract, workspace isolation, agent brief template, main session aggregation — so read it first. This section adds only the Lovable-specific bits.

### Lovable-specific gotcha: Playwright ESM import path

Every agent that runs a custom Playwright script will hit the same trap: `import 'playwright'` in an ESM `.mjs` file resolves relative to the script's own directory, NOT the current working directory. `NODE_PATH` does not help with ESM. Three fixes, in order of preference:

1. **Copy the script into `/tmp/.smart-extract-design/` and run from there** — that dir already has `node_modules/playwright` installed by the smart-extract-design skill's first-time setup. `cd /tmp/.smart-extract-design && node your-script.mjs`.
2. **Symlink `node_modules`** from `/tmp/.smart-extract-design/` into the agent workspace: `ln -s /tmp/.smart-extract-design/node_modules /tmp/agent-team-<feature>/<slot>/node_modules`.
3. **Absolute import** (last resort): `import { chromium } from '/tmp/.smart-extract-design/node_modules/playwright/index.mjs'`.

Put this in every agent brief. Otherwise each agent will burn ~15min re-deriving the workaround.

### Lovable-specific gotcha: DOM structure dump BEFORE writing any Dart

For the container (organism level — NOT the atoms), dump the real DOM structure via Playwright before writing a single line of the Dart organism widget:

```js
// Inspect the target container at the pinned viewport
const container = document.querySelector('<selector>');
const style = getComputedStyle(container);
const dump = {
  display: style.display,             // flex? grid?
  flexDirection: style.flexDirection,
  flexWrap: style.flexWrap,            // flex-wrap: wrap changes the visible set per viewport
  gap: style.gap,
  padding: style.padding,
  childCount: container.children.length,
  children: [...container.children].map((c) => ({
    tag: c.tagName,
    cls: c.className,
    bbox: c.getBoundingClientRect(),
  })),
};
console.log(JSON.stringify(dump, null, 2));
```

Commit the dump as a doc comment on the organism widget so future maintainers can verify composition without re-running Playwright. This prevents "I thought it was a Row, but it was a flex-wrap Wrap with 50 segments" retrofits.

### Lovable-specific gotcha: responsive grid reflow

Lovable uses responsive flex-wrap grids. **The set of visible children depends on the viewport.** A card that exists in the 1280 DOM visible row may not be in the 1920 row, and vice versa. Always inspect at the exact target viewport you pinned in Phase 0. If you inspect at the wrong viewport you will either miss a card or capture a phantom one — and the phantom will not match anything in the live site at your chosen viewport.

### Lovable-specific additions to the generic brief

When filling in the `parallel.md` brief template for a Lovable job, add these fields:

- **Reference source**: the published (non-`preview--`) Lovable URL
- **Reference node/selector**: CSS selector of the container + the index of the child slot
- **Viewport**: the viewport pinned in Phase 0 (critical — do not inherit the default)
- **Playwright runtime**: "run all .mjs scripts from `/tmp/.smart-extract-design` (see above)"
- **Icon capture**: "Filter by `.lucide` class to grab the Lucide SVG outerHTML from the DOM; paste as a `const` String"
- **Font rules**: "The container uses Inter. If the captured reference shows fallback fonts, force-inject `forceFonts: ['Inter:wght@300;400;500;600;700']` into the extract states.json" (see the pre-flight gotchas at the top of this file)

## Anti-inference note

For icons, **inspect the DOM via the extract's `tokens.json`**. If iconography detection is enabled, it lists Lucide / Heroicons / Material icon names directly from the rendered SVG `data-*` or class attributes. **Never guess icons from labels** ("Settings" does not automatically mean `Icons.settings` — the reference might use `tune` or `gear` or a custom SVG). Guessing icons is the single most common source of visual drift on web-derived Flutter widgets.
