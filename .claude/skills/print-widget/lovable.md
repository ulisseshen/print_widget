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
- `_index.json` — crop bounding boxes (x, y, w, h) per region
- `tokens.json` — raw tokens (colors, spacing, typography, radii, optionally iconography)
- `_DESIGN.md` — theme mapping report with ✅ / 🎨 / ⚠️ / ❌ markers per token

### 4. Copy to the print_widget reference dir

```bash
mkdir -p print_widget/output/<feature>/.reference/crops
cp /tmp/extract-<slug>/01-<state>/fullpage.png print_widget/output/<feature>/.reference/
cp /tmp/extract-<slug>/01-<state>/[0-9]*.png print_widget/output/<feature>/.reference/crops/
cp /tmp/extract-<slug>/01-<state>/_index.json print_widget/output/<feature>/.reference/
```

This is the layout `print_widget compare` expects.

### 5. Build the Token Bundle from _DESIGN.md

Walk each token row in `_DESIGN.md` and decide:

- ✅ **exact match** → use the existing project token as-is
- 🎨 **forced override** → use the override token the report suggests (brand color pinned, etc.)
- ⚠️ **close match** → ask the user: reuse the nearest existing token, or create a new one? Do not decide silently.
- ❌ **new color/value** → propose a new token with both light and dark values; add to the project theme before implementation

The output of this step is a concrete mapping table: *extracted token → project token*. Every value used in step 7 must come from this table.

### 6. Design-system component discovery

Grep existing components (`lib/ui/`, `lib/components/`, `lib/design_system/`, etc.) and map each visible section from step 3's crops to an existing DS widget where possible. **Do not create custom widgets when the DS already has them** — that's how parallel component sets get born.

For each section in `_index.json`, record: *section → DS widget* or *section → needs-new-widget (why)*.

### 7. Implement the Flutter widget

Constraints:

- Use **only** mapped tokens from step 5. No raw hex codes. No raw `EdgeInsets.all(16)` — use spacing tokens.
- Mirror the DOM structure implied by the crops; keep widget nesting shallow (extract to private `StatelessWidget` classes, no `_buildXxx()` methods).
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

## Anti-inference note

For icons, **inspect the DOM via the extract's `tokens.json`**. If iconography detection is enabled, it lists Lucide / Heroicons / Material icon names directly from the rendered SVG `data-*` or class attributes. **Never guess icons from labels** ("Settings" does not automatically mean `Icons.settings` — the reference might use `tune` or `gear` or a custom SVG). Guessing icons is the single most common source of visual drift on web-derived Flutter widgets.
