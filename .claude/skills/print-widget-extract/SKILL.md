---
name: smart:extract-design
description: Extract design tokens (colors, typography, spacing, radius), screenshot and crop sections from web prototypes (Lovable, Figma Make, any React/Vue SPA), and map everything to the project theme. Use when the user asks to "extract design", "capture this lovable", "grab the tokens from this page", or "/smart:extract-design". Always ask at runtime how to navigate (single URL vs clicks/URLs) — never hardcode selectors.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Smart Extract Design

Pipeline to extract the design of any rendered web page and produce:

- **Full-page @2x screenshots** of each state/screen
- **Automatic section crops** (detection via DOM bounding boxes)
- **Raw design tokens** (colors, typography, spacing, radius, shadows, iconography)
- **Mapping to the project design system** with badges ✅/🎨/⚠️/❌
- **Proposal of new tokens** (light + dark) when needed

All navigation is asked at runtime. The skill **does not assume** dropdowns, tab bars, or any specific UI pattern.

---

## First-time setup — edit `theme-ref.json`

Open the skill's `theme-ref.json` (next to this SKILL.md) and fill in:

- `palette` — hex → token name mappings for your design system (e.g. `"#0BA284": "brand30"`)
- `semanticOverrides` — hex → `{token, role}` for colors that should map by semantic role even when the RGB distance isn’t the closest
- `spacingScale`, `typographyScale`, `fontWeightMap` — your scale tokens

Without this file, extraction still works but mapping falls back to raw hex values. Edit once per project, then forget.

---

## STEP 1 — Collect input via AskUserQuestion

**ALWAYS use `AskUserQuestion`**, never free-text prompts.

**Question 1 — Base URL:** free input. If already given in the conversation, reuse it.

**Question 2 — How to navigate:**
- "Single screen" — capture only the initial state
- "Multiple URLs" — list of URLs (/home, /dashboard, /settings)
- "Same URL with clicks" — user describes which elements to click (text=Dashboard, etc.)
- "Mixed" — URLs + clicks

**Question 3 — Output dir (optional):** default `print_widget/output/extract-<host-slug>-<timestamp>`.

**Question 4 — Viewport (optional):**
- Desktop 1440x2400 (recommended)
- Mobile 390x844
- Tablet 820x1180

---

## STEP 2 — Build states.json

```json
{
  "url": "https://example.com/",
  "viewport": { "width": 1440, "height": 2400 },
  "deviceScaleFactor": 2,
  "output": "print_widget/output/extract-example",
  "states": [
    { "name": "initial", "steps": [] },
    {
      "name": "focus-state",
      "steps": [
        { "action": "click", "selector": "text=My Home" },
        { "action": "wait", "ms": 500 },
        { "action": "click", "selector": "text=Focus" }
      ],
      "settleMs": 1200
    }
  ]
}
```

**Actions:** `goto`, `click`, `fill`, `wait`, `scroll`, `press`. Prefer `text=VisibleLabel` selectors — most stable across SPA re-renders.

**Dropdown tip:** dropdowns close after selection — always reopen before the next state.

---

## STEP 3 — Prepare runtime (Playwright)

Playwright lives in a `node_modules` sibling of the script. Copy extract.mjs to a temp dir that holds `node_modules`:

```bash
RUN_DIR="/tmp/.smart-extract-design"
mkdir -p "$RUN_DIR"
cp <this-skill-dir>/scripts/extract.mjs "$RUN_DIR/extract.mjs"
cd "$RUN_DIR"
if [ ! -d node_modules/playwright ]; then
  npm init -y > /dev/null 2>&1
  npm install playwright --silent
  npx playwright install chromium
fi
```

First run downloads Chromium (~60s). Subsequent runs reuse the cache.

---

## STEP 4 — Run the extraction

```bash
cd /tmp/.smart-extract-design
node extract.mjs "/path/to/states.json" --theme="<this-skill-dir>/theme-ref.json"
```

Output per state at `<output>/NN-<slug>/`:
- `fullpage.png`
- `NN-<section>.png` — one per detected section
- `_index.json` — bounding boxes
- `tokens.json` — raw tokens (including iconography if detected)
- `_DESIGN.md` — formatted tokens + mapping to theme

---

## STEP 5 — Review mismatches and ask the user

Read each `_DESIGN.md` and collect:
- ❌ new colors
- ⚠️ close-but-not-exact colors

For each distinct new hex, **use `AskUserQuestion`**:

```
question: "The prototype uses `#XXXXXX` (N occurrences). How should we map it?"
options:
  - "Force to <suggested-token> (ΔE < 20)"
  - "Create new token <suggested-name>"
  - "Keep as raw hex (discuss with design)"
```

Rules for the 1st (recommended) option:
1. Identify the closest token by **semantic role**, not just RGB distance
2. If ambiguous, fall back to nearest RGB neighbor
3. If ΔE > 60, change the 1st option to "create new token"

After capturing decisions, add forced mappings to a local `theme-ref-local.json` (copy of theme-ref.json + session overrides). **Do NOT edit the global `theme-ref.json`.**

Re-run just the mapping phase:
```bash
node extract.mjs states.json --theme=<output>/theme-ref-local.json
```

---

## STEP 6 — Generate consolidated docs

At the top of the output dir, create:

### `NORMALIZATION.md`
Table "Prototype → project token" including exact matches (✅) and forced overrides (🎨).

### `NEW_TOKENS.md`
For each "create new token" decision, emit a proposal with light + dark values and code snippets for the project's theme files.

### `SUMMARY.md`
Index: processed URL, date, viewport, captured states, counts (✅/🎨/❌), links.

---

## STEP 7 — Present the result

Show:
1. File structure generated (short tree)
2. Mapping highlights (exact / forced / new counts)
3. Decisions requiring action (new tokens to add)
4. Next steps — typically hand off to the `print-widget` skill's lovable adapter

---

## Handoff to print_widget

After extraction completes, the output is ready for the `print-widget` skill's `lovable.md` adapter:

```bash
# Copy extract output to print_widget reference dir
mkdir -p print_widget/output/<feature>/.reference/crops
cp <extract-dir>/01-<state>/fullpage.png print_widget/output/<feature>/.reference/
cp <extract-dir>/01-<state>/[0-9]*.png print_widget/output/<feature>/.reference/crops/
cp <extract-dir>/01-<state>/_index.json print_widget/output/<feature>/.reference/
```

Then invoke the print-widget skill's lovable adapter to build the Flutter widget and iterate with `print_widget compare` as the stop condition.

---

## General rules

- **Never hardcode** labels or selectors — always ask via `AskUserQuestion`
- **Never assume** dropdown/tab/sidebar patterns
- **Confirm interpretation** before running if the user already gave state info in chat
- **Pragmatism**: single screen with no interaction → 1 state with `steps: []`

## When NOT to use this skill

- The prototype exposes API/design tokens directly (use them)
- It's an actual Figma file (use the `figma` workflow in the main print-widget skill)
- You only need 1 quick screenshot, no crops or tokens

## Fallback if Playwright fails

If Chromium can't install:
```bash
# Native Chrome headless (screenshot only — loses crops and tokens)
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --headless=new --screenshot=/tmp/x.png --window-size=1440,2400 <URL>
```
Warn the user that without Playwright the skill loses interaction, section crops, and token extraction.
