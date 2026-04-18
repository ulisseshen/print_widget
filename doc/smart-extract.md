# smart-extract-design skill

This document describes the `print-widget-extract` skill — a Playwright-based pipeline that captures live web pages, extracts raw design tokens, and maps them to the project's theme. It is the reference-capture side of the Lovable/web workflow.

For the CLI commands that consume the extract output, see `crops.md` and `compare.md`. For the end-to-end Lovable → Flutter workflow, see `lovable-workflow.md`.

## What it does

Given a URL to any rendered web page (Lovable, Figma Make, a deployed React/Vue/Svelte app, or any SPA), the skill produces:

- Full-page `@2x` screenshots of each navigable state
- Automatic section crops — bounding boxes detected from the rendered DOM
- **Per-crop `_spec.json`** — structured intermediate representation of the DOM subtree under each crop (bounds, computed styles, typography, icon metadata, SVG markup). This is the IR that `print_widget scaffold` consumes and that AI agents read for exact values instead of guessing from pixels. See `pipeline-gaps/spec-format.md`.
- **`_origin.json`** — reference-origin marker (`origin: "browser"`) that `print_widget compare` reads to pick the cross-engine threshold automatically.
- Raw design tokens: colors, typography, spacing, radii, shadows, iconography
- A mapping report (`_DESIGN.md`) that categorizes each token as `✅ exact`, `🎨 forced override`, `⚠️ close match`, or `❌ new`
- Proposals for new tokens the project does not have yet

**Preferred invocation is now the CLI**, not the standalone Node script:

```bash
print_widget extract --url=<URL> --output=<dir>
```

The CLI owns Playwright — first run installs Chromium automatically under `.dart_tool/print_widget/extract-runtime/`, subsequent runs reuse the cache. Flags: `--config=<states.json>`, `--viewport=WxH`, `--theme=<theme-ref.json>`, `--chrome-purge=<selector>` (repeatable), `--force-font=<spec>` (repeatable), `--runtime-dir`, `--skip-install`. See `--llm-guide` or the "Lovable / web workflow" section of the project README.

The `smart-extract-design` skill still exists for guided multi-state navigation (clicks + waits via `AskUserQuestion`), but its STEP 3 now delegates to `print_widget extract` instead of setting up a `/tmp/` Node project manually.

The key property is that bounding boxes are detected from the DOM, not guessed. That means the crops in `_index.json` correspond to actual semantic regions of the reference page, and those same coordinates can be applied to the Flutter render to produce matching generated crops — which is what lets `print_widget compare` do per-region diffing.

## Installation

```bash
print_widget skills --only=extract
```

This installs three files alongside the skill's `SKILL.md`:

| File | Purpose |
|---|---|
| `SKILL.md` | The skill instructions the AI reads |
| `scripts/extract.mjs` | The Playwright capture + token extractor |
| `theme-ref.json` | Empty template for the project's token palette |

The `extract.mjs` script is loaded from the package's `lib/src/tools/extract.mjs` at install time via `Platform.script` resolution — it works both after `dart pub global activate` and in local dev.

### First-time setup — edit `theme-ref.json`

The shipped template has empty `palette` and `semanticOverrides` objects. You fill them once per project:

```json
{
  "name": "my-project-theme",
  "palette": {
    "#0BA284": "brand30",
    "#FFFFFF": "white",
    "#363B45": "textPrimary"
  },
  "semanticOverrides": {
    "#8FC3C3": { "token": "brand30", "role": "accent-brand" }
  },
  "spacingScale": { "4": "sp4", "8": "sp8", "16": "sp16" }
}
```

- `palette` drives exact matching. Colors in this map are flagged with `✅` in the report.
- `semanticOverrides` drives role-based forcing. When a reference uses a color that is semantically a brand color but happens to be a tinted variant, the override tells the extractor to map it to the brand token anyway. Flagged with `🎨`.
- `spacingScale`, `typographyScale`, `fontWeightMap` document your scale tokens for the report.

Without `theme-ref.json`, extraction still works but mapping falls back to raw hex values. Edit it once, then forget.

## Runtime flow

The skill orchestrates the extraction through seven steps.

### Step 1 — Collect input via `AskUserQuestion`

The skill never hardcodes navigation patterns. Instead it asks structured questions:

- What is the base URL?
- How are states navigated? (single screen, multiple URLs, clicks on elements, or a mix)
- What viewport? (desktop, mobile, tablet — or custom)

For click-based navigation, the skill asks the user to describe the click sequence: `"Home" → "Dashboard" → "Reports"`, and for each state records the labels to click, in order. Dropdowns that close after selection are handled by asking the user to list the reopen + select pair explicitly.

### Step 2 — Build `states.json`

The skill writes a state machine description that the Playwright script consumes:

```json
{
  "url": "https://example.com/",
  "viewport": { "width": 1440, "height": 2400 },
  "deviceScaleFactor": 2,
  "output": "/tmp/extract-example",
  "states": [
    { "name": "initial", "steps": [] },
    {
      "name": "dashboard",
      "steps": [
        { "action": "click", "selector": "text=Home" },
        { "action": "wait", "ms": 500 },
        { "action": "click", "selector": "text=Dashboard" }
      ],
      "settleMs": 1200
    },
    {
      "name": "settings",
      "steps": [
        { "action": "goto", "url": "https://example.com/settings" }
      ]
    }
  ]
}
```

Supported actions: `goto`, `click`, `fill`, `wait`, `scroll`, `press`. Selectors prefer Playwright's `text=VisibleLabel` form because it survives SPA re-renders better than CSS selectors.

### Step 3 — Prepare the Playwright runtime

Playwright requires `node_modules` as a sibling of the script. The skill copies `extract.mjs` to a shared temp dir (`/tmp/.smart-extract-design/`) that holds a long-lived Playwright install:

```bash
RUN_DIR="/tmp/.smart-extract-design"
mkdir -p "$RUN_DIR"
cp <skill-dir>/scripts/extract.mjs "$RUN_DIR/extract.mjs"
cd "$RUN_DIR"
if [ ! -d node_modules/playwright ]; then
  npm init -y > /dev/null
  npm install playwright --silent
  npx playwright install chromium
fi
```

First run downloads Chromium (~60s). Subsequent runs reuse the cache.

### Step 4 — Run extraction

```bash
cd /tmp/.smart-extract-design
node extract.mjs <states.json> --theme=<skill-dir>/theme-ref.json
```

The script iterates each state in `states.json`, executes the step list to reach that state, then captures:

- `fullpage.png` — the full scrollable page at `@2x`
- `NN-<slug>.png` — one PNG per detected section (auto-detected, see below)
- `_index.json` — bounding boxes for each section (`{file, x, y, w, h, text, tag}`)
- `tokens.json` — raw tokens extracted via `getComputedStyle` walks
- `_DESIGN.md` — formatted token report with the four-badge mapping

Output lives at `<output>/NN-<state-slug>/`.

### Step 5 — Review mismatches

The skill reads each generated `_DESIGN.md` and collects colors marked `❌` (new) and `⚠️` (close but not exact). For each distinct hex, it uses `AskUserQuestion` to ask the user how to map it:

```
The prototype uses #XXXXXX (N occurrences). How should we map it?
  1. Force to <nearest-token> (ΔE 8.2)
  2. Create new token <suggested-name>
  3. Keep as raw hex (discuss with design)
```

The recommended (first) option is computed by a nearest-neighbor search in RGB space, preferring semantic role matches when they apply. If the nearest token is more than ΔE 60 away, the first option becomes "create new token" instead.

User decisions flow into a `theme-ref-local.json` file that copies the global `theme-ref.json` and appends the session's overrides. The global `theme-ref.json` is never edited in-place — changes are proposed, not applied.

### Step 6 — Generate consolidated docs

At the top of the output directory:

- `NORMALIZATION.md` — table of "prototype → project token" including exact matches for reference
- `NEW_TOKENS.md` — for each "create new token" decision, a proposal with light + dark values and Dart code snippets for the project's theme files
- `SUMMARY.md` — index listing the processed URL, date, viewport, captured states, counts by badge, and links to the detailed files

### Step 7 — Present the result

The skill shows the user a short tree of generated files, mapping highlights (how many exact / forced / new), decisions requiring action (new tokens to add to the theme), and suggested next steps — typically handing off to the main `print-widget` skill's Lovable adapter.

## What the extractor walks

Inside `extractTokensInBrowser` (see `lib/src/tools/extract.mjs`), the script walks the DOM under `main` or `body`. For each visible element it samples computed styles and counts occurrences:

| Token family | What is collected |
|---|---|
| Colors — text | `getComputedStyle(el).color` when the element has text content |
| Colors — background | `getComputedStyle(el).backgroundColor` (excluding transparent) |
| Colors — borders | `borderTopColor` when `borderTopWidth > 0` |
| Typography | Font family (first entry), size, weight, line height — only when the element has text |
| Spacing | `paddingTop/Right/Bottom/Left` and `gap` on elements with children |
| Radii | `borderRadius` when > 0 |
| Shadows | `boxShadow` when not `none` |
| Iconography | SVG `class` attributes parsed for `lucide-*`, `ph-*`, `heroicon*` prefixes, plus position and size via `getBoundingClientRect()` |

The top N most-frequent entries in each category make it into `tokens.json`. Frequency ranking is important: a color used 200 times is signal, a color used once is noise.

Iconography detection (added in v0.7.0) emits a structure like:

```json
{
  "iconography": {
    "libraries": ["lucide"],
    "icons": [
      { "library": "lucide", "name": "globe", "at": { "x": 120, "y": 45 }, "size": { "w": 16, "h": 16 } },
      { "library": "lucide", "name": "user", "at": { "x": 160, "y": 45 }, "size": { "w": 16, "h": 16 } }
    ]
  }
}
```

This feeds the iteration loop's anti-inference rule: icons come from the DOM, never from guessing based on labels.

## Section detection

Automatic cropping is the most important feature for downstream `print_widget compare` matching. The algorithm:

1. Start at `document.querySelector('main') || document.body`
2. Walk down while the current root has only one meaningful child (skipping generic wrappers like `<div class="layout">`)
3. Collect the children of the root that are visible and at least 30% of the viewport width and 60px tall
4. If there are only 1-2 such children, drill one more level deeper (some layouts wrap everything in a single container)
5. For each collected element, capture `{x, y, w, h, text, tag}` via `getBoundingClientRect()` and write a PNG clipped to that rect

This produces section crops that correspond to visually meaningful blocks — headers, card grids, filter rows, tables — rather than arbitrary pixel grids. The `_index.json` coordinates can then be fed to `PrintEntry.cropsFrom` so that the Flutter render produces crops at the same semantic regions.

## Fallback when Playwright fails

If Chromium cannot install (corporate sandbox, ARM Linux without prebuilt binary, etc.) the skill falls back to native headless Chrome:

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --headless=new --screenshot=/tmp/x.png --window-size=1440,2400 <URL>
```

This captures only the full-page screenshot. Section crops, token extraction, and iconography detection all require Playwright's in-browser `evaluate()` — the headless Chrome CLI has no equivalent. The skill warns the user that extraction is degraded when the fallback fires.

## When not to use this skill

- The prototype exposes design tokens via an API or file — import them directly
- The source is an actual Figma file — use the `figma` workflow in the main `print-widget` skill instead, which uses `mcp__figma__*` tools
- You only want a single quick screenshot with no token extraction — use `playwright screenshot` or headless Chrome directly

## Handoff to print_widget

The extract output is designed to feed `print_widget compare`. After extraction:

```bash
mkdir -p print_widget/output/<feature>/.reference/crops
cp /tmp/extract-<slug>/01-<state>/fullpage.png print_widget/output/<feature>/.reference/
cp /tmp/extract-<slug>/01-<state>/[0-9]*.png print_widget/output/<feature>/.reference/crops/
cp /tmp/extract-<slug>/01-<state>/_index.json print_widget/output/<feature>/.reference/
```

Then the `PrintEntry` references `_index.json` via `cropsFrom:`, `print_widget generate` produces matched crops, and `print_widget compare` diffs each region at native resolution. The full loop is documented in `lovable-workflow.md`.
