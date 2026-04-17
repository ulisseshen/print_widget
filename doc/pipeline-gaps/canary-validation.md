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

### Phase 1 — extract --spec ⬜ code landed, awaiting empirical validation

**Shipped in this branch:**
- `extractStructureInBrowser(clip)` added to `lib/src/tools/extract.mjs` — per-element DOM walker with computed styles, typography, icon metadata
- `applyChromePurge(page, selectors)` — removes platform UI (Lovable footers, cookie banners) before screenshots
- `captureState()` now emits `<crop>_spec.json` next to every crop PNG, updates `_index.json` with spec filenames
- Envelope: `$version`, `source` (url + state + extractor), `crop` (file + bounds), `root` (the tree)
- Docs: `doc/pipeline-gaps/spec-format.md`
- Skills updated: `print-widget-extract/SKILL.md` (chromePurge + outputs), `print-widget/lovable.md` (read spec FIRST in step 7)
- Dev copy synced: `.claude/skills/print-widget-extract/scripts/extract.mjs`

**Validation criteria (still to run):**
- Emits `_spec.json` per crop alongside the PNG ← *manual smoke test needed*
- Each canary's spec contains: bounds, typography for text leaves, backgroundColor with alpha preserved, borderRadius (including `50%` for circles), icon library + name + svgHtml
- Feeding the spec to a fresh agent produces Flutter that converges in ≤3 iterations (vs 8–15 baseline)

**How to smoke test (one-liner with the new CLI):**
```bash
print_widget extract \
  --url=https://promo-flow-pro-78.lovable.app/ \
  --output=/tmp/spec-smoke \
  --chrome-purge="footer:last-child" \
  --chrome-purge="[class*='lovable-badge']" \
  --force-font="Inter:wght@300;400;500;600;700"

ls /tmp/spec-smoke/01-initial/       # should show *.png AND *_spec.json
cat /tmp/spec-smoke/01-initial/01-*_spec.json | head -40
```

First run downloads Chromium (~60s under `.dart_tool/print_widget/extract-runtime/`); subsequent runs reuse the cache.

Expect the walker log to show `N section(s), N spec(s)`. If the spec count is less than the crop count, spec extraction is failing on some crops — the warning line will tell you which.

### Phase 2 — snapshot ✅ shipped + tested

**Shipped in this branch:**
- `lib/src/cli/commands/snapshot_command.dart` — new `print_widget snapshot` command
- Flags: `--name=<entry>` / `--all`, `--device`, `--force`, `--json`, `--config`
- Copies `<outputDir>/<entry>/<device>.png` + `crops/*.png` (excluding `_diff.png`) → `<outputDir>/<entry>/<referenceDir>/`
- Writes `<referenceDir>/_origin.json` with `origin: "flutter"` + `promoted_at` + `device` + `files[]` — Phase 3 reads this to pick the cross-engine vs flutter-to-flutter threshold
- Refuses to overwrite existing reference files unless `--force`
- Registered in `cli_runner.dart`; banner + `--llm-guide` updated
- 7 integration tests (`test/snapshot_command_test.dart`) — all passing
- `iterate.md` skill: new **Font Rendering Ceiling** section instructing agents to snapshot once the visual audit passes but pixelmatch is stalled in 85–93% on glyph-only diffs

**Validation criteria:**
- ✅ `snapshot --name=X` copies full-page + crops, excludes diff heatmaps
- ✅ `_origin.json` written with expected shape
- ✅ `--force` overwrites, default preserves
- ✅ `--all` iterates entries; `--device` overrides yaml default
- ✅ `--json` mode for programmatic consumption

### Phase 3 — adaptive thresholds ✅ shipped + tested

**Shipped in this branch:**
- `compare_command.dart` reads `cross_engine_threshold` and `thresholds:` map from yaml
- Per-entry threshold resolution with priority: CLI flag > `thresholds.<entry>` > `_origin.json` (flutter vs browser) > `cross_engine_threshold` (conservative fallback for missing file)
- Resolved threshold + source printed per-entry in human report: `▸ kpi_card  (threshold: 88.0% — cross-engine (browser reference))`
- JSON output shape: `entries.<name>` is now an object with `{threshold, thresholdSource, regions: []}` (breaking change vs old shape which was just a list — fixed existing tests)
- `extract.mjs` writes `_origin.json` with `origin: "browser"` in each state dir (copied over to `.reference/` in the handoff step)
- `init` yaml template includes `cross_engine_threshold: 0.88` + commented-out `thresholds:` block
- 6 new integration tests (`test/compare_threshold_test.dart`) covering all 5 priority levels + malformed origin graceful degradation — all passing
- `doc/compare.md` updated with threshold hierarchy + why-two-thresholds explanation

**Validation criteria:**
- ✅ `origin: flutter` → `compare_threshold` (0.95 default)
- ✅ `origin: browser` → `cross_engine_threshold` (0.88 default)
- ✅ Missing `_origin.json` → falls back to cross-engine (conservative)
- ✅ `thresholds.<entry>` overrides origin-based
- ✅ CLI `--threshold` overrides all
- ✅ Malformed `_origin.json` degrades gracefully (no crash)

### Phase 4 — scaffold ✅ shipped + tested

**Shipped in this branch:**
- `lib/src/cli/commands/scaffold_command.dart` — new `print_widget scaffold` command. Flags: `--spec=<path>`, `--class-name`, `--output`, `--stdout`, `--force`, `--json`.
- `lib/src/codegen/scaffold_generator.dart` — pure-Dart compiler. Decoded spec Map → Dart source String. No file I/O.
- Codegen rules implemented: flex → Row/Column, gap → SizedBox interleave, padding collapsing (`.all` / `.symmetric` / `.fromLTRB`), decoration with optional inside-the-container padding (CSS semantics), circle vs borderRadius, text + typography with `height = lineHeight / fontSize`, SvgPicture.string for svgHtml, Expanded for flexGrow:1, TextOverflow.ellipsis, Stack+Positioned for absolute children, grid fallback to Wrap+TODO, unknown layout fallback to Column+TODO.
- Color parsing: CSS `rgba(R,G,B,A)` / `#RRGGBBAA` reordered to Flutter alpha-first `Color(0xAARRGGBB)`. `transparent` / `rgba(0,0,0,0)` omitted. Never uses `Colors.white/black` shortcuts.
- `const` propagation: class constructor drops `const` when tree contains `SvgPicture.string(...)`.
- File header: 8-line banner with spec path, ISO-8601 UTC timestamp, and exact regenerate command.
- Auto-derivation: class name defaults to `_` + PascalCase(stem minus `_spec` or `.spec`); output defaults to `<cwd>/lib/scaffolds/<slug>_scaffold.dart` (parent dir created).
- Registered in `cli_runner.dart`; banner + `--llm-guide` updated with a "Scaffold codegen with `print_widget scaffold`" section.
- 27 unit tests (`test/codegen/scaffold_generator_test.dart`) covering color parsing (6 cases), EdgeInsets collapsing (3), FontWeight mapping (5), gap interleaving (2), circle vs borderRadius (2), unknown-node fallback (4), file header (1), + 3 fixture-golden tests and 1 TODO-count assertion — all passing.
- 11 integration tests (`test/codegen/scaffold_integration_test.dart`) via `Process.run` covering stdout, --output, --force, --json, auto-derivation, missing spec, malformed JSON — all passing.
- 3 canary fixtures under `test/codegen/fixtures/`:
  - `icon_badge` — circle container + bg alpha + centered SVG (lucide dollar-sign). Validates `BoxShape.circle`, alpha reordering, `SvgPicture.string`, const-dropping.
  - `delta_indicator` — Row with text + text, `gap: 4`. Validates gap interleaving, typography height, font weight 500/600.
  - `status_badge` — pill (`borderRadius: 9999`) with padding + text. Validates inside-the-Container padding, `.symmetric` collapsing, `BorderRadius.circular(9999)`.
- `doc/pipeline-gaps/scaffold.md` — CLI reference, codegen rules table, file header convention, post-scaffold workflow, regenerate-fixtures guide, known limitations.
- `analysis_options.yaml` — excludes `test/codegen/fixtures/**` (literal `.dart` goldens that import flutter_svg, which print_widget doesn't depend on).

**Validation criteria:**
- ✅ `dart analyze lib/src/codegen/ lib/src/cli/commands/scaffold_command.dart lib/src/cli/cli_runner.dart` — clean
- ✅ `flutter test test/codegen/` — 38 tests green
- ✅ `flutter test` globally — 86 tests green (no regressions in compare/snapshot/compare_threshold/etc)
- ✅ `dart run bin/print_widget.dart scaffold --help` — shows usage cleanly
- ✅ All 3 canary fixtures emit `todoCount: 0` and survive `dart format`
- ✅ Banner lists the new command; `--llm-guide` has the Scaffold section

**Validation still pending (empirical):**
- Feed real `_spec.json` outputs from the Lovable canary extract into `scaffold`, confirm the resulting widget renders close to the browser reference on first `generate + compare` (target: cross-engine ≥ 0.85 before any hand edits).

### Phase 5 — tokenize

_Not yet started._

## Final gate (end of Phase 5)

Target: **≥70% reduction in per-atom human interventions** on the canary set. Measured as:

- Per-atom iteration count (captured by `compare --json` logs)
- Per-atom intervention count (captured from session transcripts, same methodology as the April 2026 analysis)

If we don't hit 70%, the plan needs revisiting before shelving Phase 7 (Figma adapter).
