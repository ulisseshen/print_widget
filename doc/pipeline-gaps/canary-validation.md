# Canary Validation

Living document tracking the spec/IR pipeline's impact on the CRM atoms from the April 2026 Lovable build. Updated after each implementation phase.

## Canary atoms

Three atoms from `example/lib/widgets/promo_flow/atoms/` span the complexity range we need to validate:

| Atom | Complexity driver | Why picked |
|---|---|---|
| `icon_badge` | Circle container + background color + centered SVG | Simplest shape. If spec can't capture circle + bg alpha + icon svg, we've got a fundamental problem. |
| `delta_indicator` | Horizontal row + small text + arrow icon + color coding for positive/negative | Text-heavy, exposes font rendering ceiling. Multi-state (positive/negative/neutral). |
| `status_badge` | Pill-shaped container + text + optional icon + color variants | Tokenization target — pill radius (9999), small padding tokens, text color + bg color pair. Perfect for measuring tokenize precision. |

Source URL: `https://promo-flow-pro-78.lovable.app/`

## Baseline (before spec pipeline)

Captured from the April 2026 build residual — memory files, session transcripts, gaps-analysis post-mortem. Not precise per-atom iteration counts (we didn't instrument that at the time); qualitative observations only.

| Metric | Observation |
|---|---|
| Typical iterations per atom | 8–15 (15-cap hit on ~20% of atoms) |
| Human interventions during build | Distributed across ~15 atoms and ~23 molecules; pattern enumerated in `gaps-analysis.md` §2 |
| Pixelmatch score distribution | 67–95%, with text-heavy atoms stuck at 85–93% (font rendering ceiling) |
| Convergence gate | `compare_threshold: 0.95`, relaxed manually to 0.85–0.90 for text-heavy atoms |
| Time-per-atom (rough) | 15–45 min including visual audit and re-iteration |

Recorded here so that after each phase lands we can compare qualitatively and — once phases 1+ instrument iteration counts — quantitatively.

## Phase-by-phase results

### Phase 0 — Pre-flight ✅

- Committed CRM atom work to the branch (3 commits)
- Picked canary set (icon_badge, delta_indicator, status_badge)
- Recorded qualitative baseline

Next up: Phase 1 — extract --spec.

### Phase 1 — extract --spec

_Not yet started._

Validation criteria:
- Emits `_spec.json` per crop alongside the PNG
- Each canary's spec contains: bounds, typography for text leaves, backgroundColor with alpha preserved, borderRadius (including `50%` for circles), icon library + name + svgHtml
- Feeding the spec to a fresh agent produces Flutter that converges in ≤3 iterations (vs 8–15 baseline)

### Phase 2 — snapshot

_Not yet started._

### Phase 3 — adaptive thresholds

_Not yet started._

### Phase 4 — scaffold

_Not yet started._

### Phase 5 — tokenize

_Not yet started._

## Final gate (end of Phase 5)

Target: **≥70% reduction in per-atom human interventions** on the canary set. Measured as:

- Per-atom iteration count (captured by `compare --json` logs)
- Per-atom intervention count (captured from session transcripts, same methodology as the April 2026 analysis)

If we don't hit 70%, the plan needs revisiting before shelving Phase 7 (Figma adapter).
