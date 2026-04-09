# Lovable workflow — end-to-end

This document walks through the complete flow for converting a Lovable.dev URL (or any deployed React/Vue SPA) into a Flutter widget with visual validation. It is the composition of the pieces documented separately in `smart-extract.md`, `crops.md`, `compare.md`, `viewport-contract.md`, and `visual-loop.md`.

Read those individual docs first if you want the internals. This one is the end-to-end recipe.

## Prerequisites

| Requirement | Install once |
|---|---|
| `print_widget` CLI | `dart pub global activate print_widget_flutter` |
| Main skill for your AI tool | `print_widget skills --install` (auto-run by `print_widget init`) |
| Extract skill (Playwright-based) | `print_widget skills --only=extract` |
| Node + pixelmatch in the Flutter project | `npm install pixelmatch pngjs` |
| Playwright runtime (auto-installs on first extract) | (nothing — the skill does it) |
| `theme-ref.json` filled with your project's palette | Edit `~/.claude/skills/print-widget-extract/theme-ref.json` (or the project-scope copy) once |

## The flow at a glance

```
Lovable URL
    ↓
[Phase 0] Pin viewport on both sides
    ↓
[Phase 1] smart:extract-design → Playwright captures live page
    ↓      → produces: fullpage.png, section crops, _index.json, tokens.json, _DESIGN.md
    ↓
[Phase 2] Copy extract output to <outputDir>/<feature>/.reference/
    ↓
[Phase 3] Build Token Bundle from _DESIGN.md (resolve ✅ / 🎨 / ⚠️ / ❌ per color)
    ↓
[Phase 4] DS component discovery (grep existing widgets before building new ones)
    ↓
[Phase 5] Implement Flutter widget using only mapped tokens
    ↓      → add PrintEntry with cropsFrom: <.reference/_index.json>
    ↓
[Phase 6] print_widget generate --name=<feature>
    ↓      → produces: full PNG + matched crops at <feature>/crops/
    ↓
[Phase 7] print_widget compare --name=<feature>
    ↓      → reports per-region scores, writes heatmaps
    ↓
[Phase 8] Visual iteration loop (see visual-loop.md)
    ↓      → revert on regression, escalate on hard cap
    ↓
Converged Flutter widget
```

Each phase has a documented failure mode and a documented recovery. The sections below walk through them in order.

## Phase 0 — Viewport contract

Before anything else, decide the target dimensions and pin both sides. Mobile is easy (device presets). Web is the hard case: a 1440-wide Lovable reference compared against a 1280-wide Flutter render will never converge.

1. Ask the user (or detect) the target viewport. For Lovable, the production subdomain usually renders at desktop widths; the mobile layout needs a separate extract run.
2. Write a `DeviceFrame` for the Flutter side:
   ```dart
   const lovableDesktop = DeviceFrame(
     name: 'lovable_desktop',
     size: Size(1440, 2400),
     pixelRatio: 2.0,
   );
   ```
3. Pass the same width/height/DPR into the extract script's `states.json` viewport field.

If you skip this phase and the dimensions drift, `print_widget compare` will fail fast with a dimension mismatch error — that is intentional, do not auto-resize.

Details: `viewport-contract.md`.

## Phase 1 — Extract reference

Invoke the extract skill with the URL and the pinned viewport.

```
User: /smart:extract-design https://my-app.lovable.app
```

The skill runs Playwright against the URL and produces, under `/tmp/extract-<slug>/01-<state>/`:

| File | Content |
|---|---|
| `fullpage.png` | Full-page screenshot at the pinned DPR |
| `NN-<section>.png` | One PNG per auto-detected section (from DOM bounding boxes) |
| `_index.json` | Bounding boxes of each section — the same coordinates the Flutter side will use |
| `tokens.json` | Raw colors, typography, spacing, radii, shadows, and iconography |
| `_DESIGN.md` | Formatted token report with ✅ / 🎨 / ⚠️ / ❌ badges |

For multi-state prototypes (login → dashboard → settings), the skill asks which click sequences to record and produces one `01-<state>`, `02-<state>`, `03-<state>` directory per state.

Details: `smart-extract.md`.

## Phase 2 — Copy to reference dir

Move the relevant state's files into the print_widget reference layout:

```bash
FEATURE=dashboard
EXTRACT=/tmp/extract-my-app-lovable-app-20260408

mkdir -p print_widget/output/$FEATURE/.reference/crops
cp $EXTRACT/01-initial/fullpage.png print_widget/output/$FEATURE/.reference/lovable_desktop.png
cp $EXTRACT/01-initial/[0-9]*.png   print_widget/output/$FEATURE/.reference/crops/
cp $EXTRACT/01-initial/_index.json  print_widget/output/$FEATURE/.reference/
```

This is the layout `print_widget compare` expects. The device-name filename (`lovable_desktop.png`) matches the DeviceFrame declared in Phase 0 so the full-page fallback works if no crops are defined.

## Phase 3 — Build the Token Bundle

Open the extract's `_DESIGN.md` and walk each row. The AI (or you, if doing this manually) resolves each entry:

| Badge | Meaning | Action |
|---|---|---|
| ✅ exact | Hex is already in `theme-ref.json.palette` | Use the mapped token directly |
| 🎨 forced override | Hex is in `semanticOverrides` | Use the override token (brand tint → brand, etc.) |
| ⚠️ close match | Hex is within ΔE 20 of an existing token | Ask: reuse nearest, or create new? |
| ❌ new | No close match in the palette | Propose a new token with light + dark values |

The output is a concrete mapping table:

```
Extracted → Token
#1BA16E (text, 12×)            → theme.colors.contentPositive
#1BA16E (background pill, 3×)  → theme.colors.brandPrimary   (forced)
#F6F7FA                         → theme.colors.surfaceBase
#E1E7EF                         → theme.colors.borderSubtle
#18px padding                   → NEW: AppSpacing.sp18
```

Every value that ends up in Phase 5's Flutter implementation must come from this table. No raw hex, no raw `EdgeInsets.all(16)`.

## Phase 4 — DS component discovery

Before creating any new widget, grep the existing design system:

```bash
Grep: "class \\w+ extends (Stateless|Stateful)Widget" in lib/ packages/
Glob: lib/core/components/*.dart
Glob: packages/*/lib/src/widgets/*.dart
```

For each visible section in the extract's `_index.json`, decide:

- Section → existing DS widget (use it)
- Section → needs-new-widget (explain why, flag to the user)

The most common failure mode skipping this phase: creating `_FilterChipsWidget` when `YHAnimatedPillTabGroup` already exists. The parallel widget then carries subtle bugs (wrong font-family propagation, missing animations, wrong highlight color) and costs many iterations to unwind.

Details: the DS component discovery section of `visual-loop.md` and the mandatory rule in the `print-widget` skill's `conventions.md`.

## Phase 5 — Implement the Flutter widget

Write the Flutter code:

- Mirror the DOM structure implied by the crops
- Use only tokens from the Phase 3 table (no raw values)
- Keep widget nesting shallow — extract sub-trees into private `_WidgetName extends StatelessWidget` classes rather than `_buildXxx()` methods
- Reuse DS components from Phase 4

Add the entry to your `print_widget/config.dart`:

```dart
import 'package:my_app/features/dashboard/presentation/dashboard_screen.dart';

final printList = <PrintEntry>[
  page(
    'dashboard',
    const DashboardScreen(),
    devices: [
      DeviceFrame(
        name: 'lovable_desktop',
        size: Size(1440, 2400),
        pixelRatio: 2.0,
      ),
    ],
    scrollExtent: 2400,
    cropsFrom: 'print_widget/output/dashboard/.reference/_index.json',
  ),
];
```

The `cropsFrom:` is the critical piece — it tells `generate` to produce crops at the same bounding boxes as the reference, so `compare` has matched pairs.

## Phase 6 — Generate

```bash
print_widget generate --name=dashboard
```

Output layout:

```
print_widget/output/dashboard/
  lovable_desktop.png                  # full-page golden
  crops/                                # NEW — one PNG per region from _index.json
    01-header.png
    02-metrics.png
    03-chart.png
    04-table.png
  .reference/                           # from Phase 2
    lovable_desktop.png
    crops/
      01-header.png
      02-metrics.png
      03-chart.png
      04-table.png
    _index.json
```

If generation fails with a dimension mismatch, an overflow, or a missing font, fix it before proceeding. `print_widget compare` cannot recover from a broken generate.

Details: `crops.md`.

## Phase 7 — Compare

```bash
print_widget compare --name=dashboard
```

Output:

```
print_widget compare
  threshold: 95.0%

▸ dashboard
    ✓ 01-header: 98.42%
    ✗ 02-metrics: 82.14%  (below 95%)
      heatmap: print_widget/output/dashboard/crops/02-metrics_diff.png
    ✓ 03-chart: 96.77%
    ✗ 04-table: 89.01%  (below 95%)
      heatmap: print_widget/output/dashboard/crops/04-table_diff.png
```

Exit code is 1 because two regions failed. Open the two heatmap PNGs — red pixels mark exactly where the Flutter output diverges. Those red pixels are your edit list for the next iteration.

Details: `compare.md`.

## Phase 8 — Iterate

The main `print-widget` skill takes over. It reads the compare output, backs up the files about to be touched, makes targeted edits for the failed regions in a single batch, regenerates, re-runs compare, and compares the new scores to the previous iteration. If any region regressed, it reverts and tries a different approach.

The loop exits on one of three conditions:

1. All regions reach the threshold (converged — success)
2. 15 iterations pass without net improvement (hard cap — escalation report)
3. Stuck detection triggers and a fresh reference fetch does not help (escalation report)

Details: `visual-loop.md`.

## Re-extraction when the design changes

When the Lovable design updates:

```
User: re-extract https://my-app.lovable.app
```

1. Re-run `smart:extract-design` with the same slug
2. Diff the new `_DESIGN.md` against the committed one — surface which tokens changed
3. Decide per-row whether to update the Flutter implementation, pin to the old reference, or add a new token
4. Copy the new crops into `<feature>/.reference/crops/` (overwriting)
5. Re-run `generate` + `compare` — the iteration loop handles any resulting drift

Never overwrite the old reference silently. The diff is what tells you whether the design actually drifted or the extractor got unlucky on a responsive breakpoint.

## Common failure modes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| `compare` fails with dimension mismatch | Viewport not pinned on one side | Phase 0 — match both sides |
| All regions show 100% but the layout looks wrong to the eye | Comparing stale crops from a previous generate | `print_widget generate --delete-old --name=<entry>` then compare |
| Icons in the Flutter render look plausible but different from Lovable | Icon inferred from label instead of observed | Check `tokens.json.iconography` for the actual library/name; see anti-inference rule in `visual-loop.md` |
| Loop oscillates between two regions, neither ever converging | Fixes on one region regress another | The revert-on-regression rule should catch this; if the same pair keeps flipping, escalate and tune the widget structure manually |
| Extract produces wrong section boundaries | The page's DOM wraps everything in a single flexbox; section detection walks to the wrong level | Adjust the click sequence to navigate to a state with clearer section boundaries, or fall back to manual `crops:` coordinates |
| `compare` says "pixelmatch not installed" | npm deps missing in the Flutter project | `cd <project> && npm install pixelmatch pngjs` |

## Why this workflow exists

Before v0.7.0, web references were nearly impossible to converge with `print_widget`. A real session captured in `PRINT_WIDGET_IMPROVEMENT_PROPOSAL.md` (from a Metas V2 implementation) documented ~30 manual iterations to hit visual fidelity on a single Lovable page, with the human having to send cropped screenshots every time the AI missed a detail it could not see in the compressed full-page PNG.

Every phase in this workflow corresponds to one of the gaps identified in that session:

| Session gap | Workflow phase |
|---|---|
| Full-page comparison lost fine detail | Phase 1 auto-crops + Phase 7 per-region compare |
| Components re-created instead of reused | Phase 4 DS discovery |
| Icons inferred from labels | Phase 1 iconography extraction + anti-inference rule |
| Cores normalized without semantic context | Phase 3 Token Bundle with role-based overrides |
| Loop was not actually autonomous | Phase 8 three-tier stop + revert-on-regression + escalation |
| Web context (React/Tailwind) had no translation | Phase 1 DOM token extraction |
| Segmented button component was re-invented multiple times | Phase 4 component catalog |

The composition is what matters. Each piece in isolation is insufficient; the full pipeline is what makes autonomous convergence possible on web references.
