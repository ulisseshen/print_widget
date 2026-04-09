# Visual iteration loop

This document explains the autonomous visual iteration loop that drives the `print-widget` skill's figma/lovable/stitch workflows. It is the runtime behavior the AI follows when converging a Flutter widget against a design reference.

For the user-facing command that is the loop's objective stop condition, see `compare.md`. For per-region crop setup, see `crops.md`. For pinning dimensions before the loop starts, see `viewport-contract.md`.

## Design goals

The loop replaces a previous version that asked the user for approval every iteration and gave up after 5 cycles. Both behaviors produced visual drift in practice: the AI accepted mismatches it couldn't see in compressed full-page images, or "fixed" things that weren't broken and regressed elsewhere.

The new loop has four non-negotiable properties:

| Property | What it means | Why |
|---|---|---|
| **Autonomous** | Never asks the user between iterations | User intervention interrupts convergence without adding information the loop could not gather itself |
| **Objective stop** | `print_widget compare` exit 0 is a necessary condition | Prevents "it looks fine" acceptance of regressions invisible in compressed previews |
| **Regression-safe** | Every fix is backed up before editing; any score drop triggers a revert | Prevents drift into worse code when fixing one region breaks another |
| **Loud on failure** | Hard cap (15 iterations) produces an escalation report, never a silent accept | Forces the user to see what the loop could not converge rather than hiding residual diffs |

## Three-tier stop condition

A single numeric score is not enough. The loop exits only when all three tiers pass simultaneously.

### Tier 1 — Structural (AI vision)

The AI reads the generated PNG and the reference PNG, then walks the `review.md` checklist:

- Every text string matches exactly (no approximations, no retyping)
- Every color is a theme token (no raw `Color()` or hex literals)
- Every spacing value is a token (no raw `EdgeInsets`)
- Every icon matches visual observation (not inferred from a semantic name)
- Every DS component is used where one exists (no duplicate custom widgets)

This tier catches semantic issues that pixel diff cannot — wrong text content, wrong font weight used for the right visual weight, an icon that happens to have the same silhouette.

### Tier 2 — Perceptual (pixelmatch)

`print_widget compare --name=<entry>` is run. Exit code 0 means every region's similarity is at or above `compare_threshold` (default 0.95). Exit code 1 means at least one region fell below.

Per-region heatmaps are written next to the generated crops as `<region>_diff.png`. Red pixels mark exactly where the generated output diverges from the reference. The AI reads those heatmaps during the next iteration to target the fix.

### Tier 3 — Stuck detection

If the same region has the same score (±1%) for two consecutive iterations, the loop is stuck. It takes a recovery action before continuing:

1. Re-fetch the reference fresh — re-run `smart-extract-design` for Lovable, re-fetch the Figma MCP node for Figma. The reference cache may be stale or the crop coordinates may be wrong.
2. Re-run compare with the fresh reference.
3. If still stuck after the fresh fetch, escalate.

### Hard cap

The loop runs for at most 15 iterations (raised from the previous version's 5). On the 15th iteration, if tiers 1 and 2 have not both passed, it emits the escalation report (see below) and stops. It never silently accepts mismatches — silent acceptance is how visual drift accumulates.

## Per-iteration procedure

The AI follows this exact sequence each cycle:

1. `print_widget generate --name=<entry>`
2. Read generated PNG at `<outputDir>/<entry>/<device>.png`
3. Read reference PNG at `<outputDir>/<entry>/.reference/<device>.png`
4. Run Tier 1 check (AI vision against `review.md`)
5. Run Tier 2 check (`print_widget compare --name=<entry>`)
6. If both pass → exit the loop, emit final report
7. Back up files about to be edited: `cp <file> /tmp/pw_iter_<N>_backup.dart`
8. List all differences from both tiers, group as critical vs minor, reference the heatmap PNGs for each failed region
9. Fix all differences in one batch (do not fix one at a time and regenerate between)
10. Regenerate and re-run both tiers
11. Compare new per-region scores with the previous iteration — if any region dropped, revert and try a different approach
12. Increment iteration counter; loop back to step 4 or escalate on cap

## Revert-on-regression rule

This is the single most important safety mechanism. It operates unconditionally.

Before any fix, every file about to be touched is copied to `/tmp/pw_iter_<N>_backup.*`. After regeneration, the new per-region scores are diffed against the previous iteration's scores. If any region's score dropped, all modified files are restored from the backup.

The AI also tracks tried-and-reverted approaches in memory — a tuple of `(region, approach description, score delta)`. When choosing the next fix, it avoids repeating any approach already marked as reverted on the same region. This prevents two common failure modes: the "try the same thing harder" loop and the "oscillate between two equally broken fixes" loop.

Partial improvements that worsen another region are not kept. The loop prefers to revert and try a different strategy rather than compound regressions.

## Anti-inference rule

Visual fidelity requires observation, not guessing. The loop enforces three specific rules:

- Icons are never inferred from semantic names. A field labelled "Settings" does not automatically mean `Icons.settings` — the reference might use `tune`, `gear`, or a custom SVG. The AI inspects the reference crops or the source DOM (for Lovable, via `tokens.iconography`) before choosing an icon.
- Colors are never assumed from brand associations. "Primary" does not mean blue. The AI reads the actual rendered color from the crop or the extracted token list.
- Components are never built from a semantic category without checking the design system first. "A filter pill" is a type — the project's DS probably already has one.

If observation is impossible (a crop is too small to distinguish an icon, the DOM doesn't expose an icon class), the loop escalates to the user rather than shipping a guess.

## Design system discovery

Before creating any new widget, the loop runs a set of greps to enumerate existing components:

```bash
Grep: "class \\w+ extends (Stateless|Stateful)Widget" in lib/ and packages/
Glob: lib/core/components/*.dart
Glob: lib/design_system/**/*.dart
Glob: packages/*/lib/src/widgets/*.dart
Glob: packages/*_design_system/lib/**/*.dart
```

It builds a one-line catalog of each found widget, then for each visible element in the reference classifies it (button, pill, segmented button, tab, chip, card, toggle, badge) and searches the catalog for a matching type. If a match exists, the loop uses it instead of building a custom version. If the DS lacks something needed, the loop flags it to the user — the user may want to add it to the DS rather than inline it in a feature.

This rule catches the most expensive mistake observed in real-world sessions: the AI builds `_FilterChipsWidget` or `_EmbeddedToggle` when the DS already has `YHAnimatedPillTabGroup` or `YHSegmentedButtonGroup`. The parallel component set then leaks font-family bugs, wrong highlight colors, and missing animations, costing many iterations to recover.

## Escalation report format

When the hard cap fires, stuck detection fails after a fresh fetch, or the anti-inference rule forces a user decision, the loop emits a structured report:

```
ITERATION 15 — STOPPED WITH RESIDUAL DIFF

Converged dimensions:
  ✓ Layout, Colors, Typography

Residual:
  ✗ <region>: <score>% — <root cause hypothesis>
    Suggested fix: <specific suggestion>

Approaches tried and reverted:
  - <approach 1>: worsened <region> from X% to Y%
  - <approach 2>: broke analyzer

Next step: user intervention needed. See heatmap at <path>.
```

The report is deliberately concrete: which region failed, the current score, the hypothesis for the root cause, a suggested fix the user can either apply or reject, and the tried-and-reverted approaches so the user does not retrace wasted work. The path to the worst-offending heatmap is always included so the user can open it directly.

The report is emitted only in the three escalation scenarios — it is not a shortcut to stop early. A loop that has not exhausted 15 iterations cannot emit the report unless stuck detection or anti-inference forces it.

## Working with existing widgets

When the target file already contains code, the loop prefers refactoring over rewriting:

- Extract sub-trees into private `_WidgetName extends StatelessWidget` classes rather than replacing the whole file.
- Preserve real data flow; only mock what the widget cannot reach in a test context (network, platform channels).
- Keep callbacks, state, and navigation intact — visual iteration must not regress functionality.
- If a rewrite is genuinely required, the loop backs up the full file first and lists the behavioral diff in the final report.

## Relation to the rest of the system

The loop is the runtime behavior. It relies on infrastructure that must be set up first:

| Prerequisite | Where it comes from |
|---|---|
| Pinned viewport | `viewport-contract.md` — Phase 0 before the loop starts |
| Per-region crops on the generated side | `crops.md` — `PrintEntry.crops` or `cropsFrom` |
| Reference crops at `<entry>/.reference/crops/` | `smart-extract.md` (for Lovable) or manual copy (for Figma) |
| Objective stop condition | `compare.md` — `print_widget compare` with pixelmatch + Node |
| DS component catalog | Built by greps at loop start, per `conventions.md` in the skill |

Breaking any prerequisite breaks the loop: without a pinned viewport, pixelmatch throws dimension errors; without per-region crops, the loop falls back to full-page comparison and loses detail; without reference crops, compare exits 2 and the loop cannot start.
