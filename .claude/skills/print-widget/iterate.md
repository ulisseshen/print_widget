# Visual Iteration Loop

This is a **fully autonomous** visual iteration loop. It uses `print_widget compare` as the objective stop condition, **never asks the user mid-loop**, **reverts regressions automatically**, and produces an escalation report **only** when a hard cap is hit. Do not silently accept mismatches. Do not stop at iteration 5 and ask for approval — keep going until convergence or escalation.

## Three-Tier Stop Conditions

The loop exits only when **all active tiers pass**, or when the hard cap triggers an escalation.

- **Tier 1 — STRUCTURAL (AI vision):** Compare the generated PNG against the reference using the `review.md` checklist. Verify layout structure, exact text content, colors mapped to theme tokens, and DS components used where available.
- **Tier 2 — PERCEPTUAL (pixelmatch):** Run `print_widget compare --name=<entry>` and require exit code `0`. All per-region scores must be `>= threshold` (default `0.95`).
- **Tier 3 — STUCK DETECTION:** If the same region score stagnates (±1%) for **2 consecutive iterations**, the loop is stuck and must take recovery action (see Stuck Detection).
- **Hard cap:** **15 iterations maximum** (not 5). On cap, produce the escalation report. **Never silently accept a mismatch.**

## Iteration Steps

1. **Generate:** `print_widget generate --name=<entry>`
2. **Read generated PNG:** `print_widget/output/<entry>/<device>.png`
3. **Read reference PNG:** `print_widget/output/<entry>/<device>.ref.png` (sibling suffix layout) or `print_widget/output/<entry>/.reference/<device>.png` (legacy layout).
4. **Tier 1 check (AI vision):** Compare generated vs reference using the **5-point visual audit** in `review.md`: text complete, fonts match, layout intact, colors match, icons correct. Failing any one is enough to reject even if Tier 2 passes — pixelmatch cannot detect truncated text or wrong glyphs.
5. **Tier 2 check (perceptual):** Run `print_widget compare --name=<entry>` and read the per-region scores from the output.
6. **If Tier 1 AND Tier 2 pass →** Pixel-converged. Proceed to the **post-convergence code review** (see `review.md` → "Post-convergence code review"). Run all four checks against every file touched this session: (1) **token discipline** — hunt hardcoded colors, spacing, radii, and raw TextStyle constructors bypassing the font helper; (2) **composition over nesting** — flatten trees deeper than 3 levels; (3) **`StatelessWidget` over `Widget buildSomething()`** — extract every `_buildXxx()` method, widget-returning getter, and widget field into a private `StatelessWidget` class; (4) **component reuse** — grep for hand-rolled private `_Table` / `_Row` / `_Cell` / `_List` / `_Pagination` / `_FilterPill` clusters; if any exist and the project already has a matching component (`YHAdaptiveTable`, `CardOrdersTable`, etc.), invoke `AskUserQuestion` with the four-option frame (use as-is / improve / V2 / keep hand-rolled) and let the user decide. After each Check 1–3 fix, regenerate + re-compare and confirm **zero score change** (token swaps and extractions must be byte-identical — any delta is a bug, revert and retry). Check 4 refactors are allowed to move the score because the visual primitive changes. Only AFTER the code review passes, STOP. Converged. Emit the final report and exit the loop.
7. **Backup before edit:** Save the current state of every file you are about to touch: `cp lib/features/.../screen.dart /tmp/pw_iter_<N>_backup.dart`. Do this **before** making any changes — it is required for revert.
8. **List ALL differences** from both tiers. Group them as `critical` and `minor`. Reference the heatmap PNGs from `print_widget/output/<entry>/<device>.diff.png` (sibling layout) or `print_widget/output/<entry>/crops/*_diff.png` (legacy) for each region that failed.
9. **Fix ALL differences in one batch.** Do not fix one at a time and regenerate between each — it wastes iterations and hides regressions.
10. **Regenerate and re-compare:** repeat steps 1, 4, 5.
11. **Regression check:** Compare new per-region scores against the previous iteration's scores. If **any region's score dropped**, revert the touched files from the backup: `cp /tmp/pw_iter_<N>_backup.dart lib/features/.../screen.dart`. Record the approach as tried-and-reverted. Try a **different** approach.
12. **Loop back to step 4.** Increment iteration counter. If counter reaches 15, jump to the Escalation Report.

## Revert-on-Regression Rule

This is the single most important safety rule. The loop must never drift into worse code.

- **Before every fix**, back up **all** files being touched to `/tmp/pw_iter_<N>_backup.*`.
- **After regeneration**, diff the new per-region scores against the previous iteration's scores.
- **If any region's score dropped**, revert **all** modified files immediately. Do not keep partial improvements that worsen another region.
- **Track tried-and-reverted approaches** in memory (region + approach + delta). Do not retry the same fix on the same region.
- If you are about to attempt a fix that matches a previously reverted one, pick a different strategy instead.

## Font Rendering Ceiling (stop iterating, snapshot the win)

Skia (Flutter) and Chromium (browser references from Lovable, Figma Make, web captures) render text differently even with the same TTF: subpixel positioning, anti-aliasing, `opsz` axis defaults, and kerning all differ. The practical effect is a **systematic 5–7% gap on text-heavy widgets** that is **NOT fixable by code changes**.

**Recognition pattern:**
- Score stalled in the 85–93% band for 2+ iterations
- Heatmap diffs are concentrated **exclusively on text glyphs** (not on spacing, backgrounds, layout, icons)
- The 5-point visual audit (`review.md`) passes — text content, font, weight, size all correct
- You've already tried `forceFonts`, `fontVariations('opsz', fontSize)`, and `fontFeatures.enable('kern')`

**Action when ceiling is reached:**
1. **Confirm the visual audit passes** on the current generated output
2. **Promote the generated PNG to reference**:
   ```bash
   print_widget snapshot --name=<entry>
   ```
   This copies `<outputDir>/<entry>/<device>.png` + all `crops/*.png` (excluding `*_diff.png`) into `<referenceDir>/`, and writes `_origin.json` marking the reference as Flutter-native.
3. **Future iterations compare Flutter-to-Flutter** — no cross-engine gap. Run `print_widget compare` again; scores should now be at or near the full threshold.
4. **Emit the converged report** noting the ceiling: "Converged at X% vs browser reference; snapshotted to Flutter-native reference. Any future regression will be measured against this snapshot at full threshold."

**When NOT to snapshot:**
- Visual audit still failing (missing element, wrong text, wrong layout) — fix the code, don't snapshot over the bug
- Heatmap shows diff outside text glyphs (spacing, colors, layout) — that IS a code bug, not the ceiling
- Agent was about to try a fresh recovery approach (fresh reference, different font variation) that hadn't been tried yet

Snapshotting prematurely is a footgun — it bakes the current Flutter output in as the golden, hiding real bugs from future comparisons.

## Stuck Detection

- If the same region has the same score (±1%) for **2 iterations in a row**, the loop is stuck.
- **Recovery actions (in order):**
  1. **Font safety check** — verify the reference was captured with the real declared font. Lovable and similar SPAs declare `font-family: Inter` without importing the font; the browser silently falls back to Helvetica/DejaVu. If the reference looks subtly "off" in glyph shapes, re-run extract with `forceFonts: ["Inter:wght@..."]` in `states.json` to inject the Google Fonts stylesheet before capture.
  2. **Fresh reference** — re-run the smart-extract for Lovable, or re-fetch the Figma MCP node for Figma. The reference crop may be stale or the crop region may be wrong.
  3. **Font variation / kerning** — if both the reference and the Flutter render use real Inter but widths still differ, the TextStyle needs `fontVariations: [FontVariation('opsz', fontSize)]` and `fontFeatures: [FontFeature.enable('kern')]`. Chromium applies these by default; Flutter does not.
- Re-run the compare after each recovery action.
- If still stuck after all three, **escalate** (emit the escalation report and stop).

## Anti-Inference Rule (Critical)

Visual fidelity requires observation, not guessing.

- **NEVER infer** icons, colors, or component choices from semantic names (e.g., do not assume `settings` means a gear icon, or `primary` means blue).
- **ALWAYS observe** the reference crops visually at full resolution before choosing an icon, color, or component.
- If a crop is too small to distinguish an icon, **inspect the source**: Chrome DOM for Lovable, Figma design context for Figma. Never guess.
- If inference is the only remaining option, **escalate to the user**. Do not ship a guess.

## DS Component Discovery (Run Before Every Iteration)

- Before creating a new widget, **grep existing components** in:
  - `lib/core/components/`
  - `packages/*/lib/src/widgets/`
  - `lib/design_system/`
- If a similar component already exists, **use it**. Do not duplicate.
- If the design system lacks something the reference needs, **flag it to the user** in the final report — do not silently build a one-off.

## Per-Iteration Checklist

The loop exits only when **every** box checks:

```
□ Every text string matches (exact characters, no approximations)
□ Every color maps to a theme token (no raw Color() or hex literals)
□ Every spacing maps to a token (no raw EdgeInsets values)
□ Every icon matches visual observation (not inferred from name)
□ DS components used where they exist
□ print_widget compare: all regions >= threshold
□ dart analyze: 0 errors, 0 warnings on modified files
```

If any box is unchecked at iteration 15, do **not** check it — emit the escalation report instead.

## Escalation Report Format

Emit this **only** when the hard cap (15 iterations) is hit, when stuck detection fails after a fresh reference fetch, or when the anti-inference rule forces a user decision. Never emit it as a shortcut to stop early.

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

Include the path to the worst-offending heatmap PNG from `print_widget/output/<entry>/crops/` so the user can inspect it directly. Reference the config at `print_widget/config.dart` if configuration changes are part of the suggested fix.

## Working With Existing Widgets

When the target file already contains code:

- **Extract, don’t rewrite.** Pull sub-trees into private `_WidgetName extends StatelessWidget` classes rather than replacing the whole file.
- **Mock as little as possible.** Preserve real data flow; only mock what the widget cannot reach in a test context (network, platform channels).
- **Preserve behavior.** Callbacks, state, and navigation must continue to work — visual iteration must not regress functionality.
- If a rewrite is genuinely required, back up the full file first and list the behavioral diff in the final report.
