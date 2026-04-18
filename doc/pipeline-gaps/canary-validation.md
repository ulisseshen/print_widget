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

### Phase 5 — tokenize ✅ shipped + tested

**Shipped in this branch:**
- `lib/src/cli/commands/tokenize_command.dart` — new `print_widget tokenize` command. Flags: `--input=<scaffold.dart>`, `--theme=<theme-ref.json>`, `--output=<path>`, `--stdout`, `--strategy=exact|near`, `--tolerance=<ΔE>` (default 2.0), `--force`, `--json`.
- `lib/src/codegen/tokenizer.dart` — pure-Dart transformer. Regex + brace-counting MVP (no `package:analyzer` dep). Handles colors (`Color(0xAARRGGBB)`), spacing (`EdgeInsets.all/.symmetric/.fromLTRB`, `SizedBox(width/height)`), radius (`BorderRadius.circular(N)`), typography (`TextStyle` with `fontFamily: 'Inter'` → `interText(...)`). Per-arg FORCE comments when a literal can't be mapped.
- Color rules: exact-match first; `strategy=near` enables ΔE-CIE76 fuzzy fallback; alpha < 0xFF emits `.withValues(alpha: <0.N>)` (modern Flutter API; `withOpacity` is never generated). Pure white / transparent preserved as sentinels unless explicitly mapped.
- `const` propagation: drops `const` from the class constructor when substitutions introduce non-const refs (`context.customColors.*` getter, `interText(...)` call). Inherits SVG-driven const drops from Phase 4.
- Idempotency guard: input containing any of `context.customColors.`, `YHAppSpacing.`, `YHAppCornerRadiusV2.`, `interText(` is rejected — refuses to double-tokenize.
- Output header: 6 lines including scaffold source, theme name, substitution counts, and regenerate command. Typography import auto-added when any TextStyle was rewritten.
- Registered in `cli_runner.dart` AFTER `ScaffoldCommand()`; banner + `--llm-guide` updated with a full "Tokenize pass" section.
- `.claude/skills/print-widget-extract/theme-ref.json` extended with new `colors`, `spacing`, `radius`, `typography` keys alongside the existing `palette`, `semanticOverrides`, `spacingScale`, `typographyScale`, `fontWeightMap` — extract.mjs continues to read the legacy keys unchanged.
- `test/codegen/fixtures/theme-ref.test.json` — canonical test theme wired to the 3 canary fixtures.
- 3 `.tokenized.expected.dart` goldens (icon_badge, delta_indicator, status_badge).
- 20 unit tests (`test/codegen/tokenizer_test.dart`) covering color parsing + alpha rounding, ΔE accept/reject, EdgeInsets (all/symmetric/fromLTRB/SizedBox), radius, TextStyle→interText with FontWeight mapping, non-Inter preservation, const propagation, idempotency, header rewrite — all passing.
- 12 integration tests (`test/codegen/tokenize_integration_test.dart`) via `Process.run` covering 3-canary golden round-trip, `--output`, `--force`, `--json`, `--strategy=near`, idempotency error, missing flags, malformed theme JSON — all passing.
- `doc/pipeline-gaps/tokenize.md` — CLI reference, theme-ref schema (new vs existing keys), per-kind substitution rules, FORCE comments, const propagation, idempotency, known limitations.

**Validation criteria:**
- ✅ `dart analyze lib/src/codegen/tokenizer.dart lib/src/cli/commands/tokenize_command.dart lib/src/cli/cli_runner.dart` — clean
- ✅ `flutter test` globally — 118 tests green (86 prior + 32 new = 20 unit + 12 integration), no regressions
- ✅ `dart run bin/print_widget.dart tokenize --help` — usage prints cleanly
- ✅ `tokenize --input=test/codegen/fixtures/icon_badge.expected.dart --theme=...test.json --stdout` emits `context.customColors.brand30.withValues(alpha: 0.12)`, `YHAppSpacing.sp10`, `BoxShape.circle`, and passes `dart format` unchanged
- ✅ Banner lists `tokenize`; `--llm-guide` has a Tokenize section
- ✅ status_badge's `horizontal: 10` gracefully emits `// FORCE: no token match for 10 in spacing.scale` while the rest of the expression still tokenizes

**Validation still pending (empirical):**
- End-to-end: scaffold a canary atom from its `_spec.json`, tokenize against the project theme-ref, wire into `printList`, compare against the snapshotted reference. Target: tokenize introduces ZERO pixel delta (substitutions must be visually equivalent).

### Phase 6 — skills + docs update ✅ shipped

**Shipped in this branch:**
- `README.md`: new CLI command list (extract/snapshot/scaffold/tokenize), new "Spec pipeline" section with ASCII diagram, links to `doc/pipeline-gaps/*`.
- `CLAUDE.md` (project): new CLI commands + "Spec pipeline" section explaining each command and the `theme-ref.json` schema extension.
- `lib/src/cli/commands/skills_command.dart` (canonical source for skills) updated:
  - `review.md`: new "Pre-flight: verify the reference is clean" section (5 checks — chrome, fonts, viewport, animations, origin); new "Post-tokenize invariant" section (zero-score-change rule after tokenize).
  - `iterate.md`: new "Pass-Aware Iteration" section (Phase A scaffold + Phase B tokenize); new "Font Rendering Ceiling" recognition + action; new "Heatmap Interpretation Guide" with 10-row lookup table.
  - `conventions.md`: new "Scaffold-first development" section with step-by-step + "when NOT to scaffold-first" list.
  - `parallel.md`: 3 new safety rules (never `--delete-old` without `--name`; never edit `.claude/skills/` during parallel; never edit shared files outside assignment).
- Regenerated installed variants via `print_widget skills --update`: 8 skills × 4 AI tools (Claude, Cursor, Codex, Antigravity).

**Validation criteria:**
- ✅ All skill edits propagated to `.claude/skills/print-widget/*.md` (verified with grep: 10 matches across 4 files).
- ✅ `dart analyze lib/` clean.
- ✅ `flutter test` — 118 tests still green, no regressions.

### Phase 7 — Figma adapter ⬜ shipped (code; empirical validation pending)

**Shipped in this branch:**
- `lib/src/codegen/figma_to_spec.dart` — pure-Dart adapter. Input: decoded Figma MCP `get_design_context` Map. Output: spec v1 envelope Map (same shape as `extract.mjs` emits). No file I/O, no network.
- `lib/src/cli/commands/figma_spec_command.dart` — new `print_widget figma-spec` command. Flags: `--input=<figma-mcp-response.json>`, `--output=<path>`, `--stdout`, `--force`, `--json`, `--source-url=<url>`, `--state-name=<label>`.
- Envelope byte-compatible with `extract.mjs` output: same `$version`, `source` (url/state/extractor), `crop` (file/text/bounds), `root` tree. `source.extractor` is `"figma_to_spec"`; crop bounds are viewport-absolute; descendant bounds are root-relative integers.
- Normalization rules implemented: VERTICAL/HORIZONTAL/NONE layout mapping (+ absolute positioning on child styles when parent has no `layoutMode`), `primaryAxisAlignItems`/`counterAxisAlignItems` → `justifyContent`/`alignItems`, `itemSpacing` → `gap`, `padding*` → `padding:{top,right,bottom,left}`, `fills[0]` SOLID with alpha × `fill.opacity` → CSS `rgb()/rgba()`, `GRADIENT_LINEAR` → `linear-gradient(<deg>, <stops>)` (other gradients fall back to first-stop solid), `strokes[0]` → `border:{width,color,style,align}`, uniform/mixed `cornerRadius`/`rectangleCornerRadii` with circle detection (`"50%"` for square-ish shapes with half-side radius), `effects[]` DROP_SHADOW/INNER_SHADOW composed into `boxShadow` (comma-joined + `inset` prefix), `opacity < 1` → `styles.opacity`, `visible: false` nodes dropped, TEXT with `typography` (lineHeightPercent → px conversion, `textAlignHorizontal`/`textCase` normalization, 500-char clip), INSTANCE icon detection (`Lucide/`/`Phosphor/`/`Heroicon(s)/`/`LucideIcon/` case-insensitive prefix) + VECTOR/BOOLEAN_OPERATION ≤64×64 anonymous icons with kebab-case names, `svgHtml` read from `svg`/`svgString`/`exportSettings[].svg` when present (never synthesized).
- Recursion control: walks FRAME/GROUP/COMPONENT/COMPONENT_SET/INSTANCE/SECTION; SLICE/STICKY/CONNECTOR/SHAPE_WITH_TEXT/CODE_BLOCK/WIDGET/STAMP silently omitted.
- Idempotency: stable key insertion order (`tag`, `bounds`, `text`, `typography`, `icon`, `svgHtml`, `styles`, `children`) + 2-decimal alpha rounding + trimmed trailing zeros. Running twice produces byte-identical output.
- Registered in `cli_runner.dart` AFTER `TokenizeCommand()`; banner + `--llm-guide` updated with "Figma to spec with `print_widget figma-spec`" section covering rules table + chain examples.
- 3 synthetic MCP fixtures + matching expected specs under `test/codegen/figma_fixtures/`:
  - `flex_card` — FRAME (VERTICAL) with padding 20, gap 12, `cornerRadius 16`, white 70% bg, drop shadow; 2 TEXT children (16px/600/Inter title, 24px/700/Inter value). Validates layout + align + shadow composition + alpha multiplication.
  - `icon_row` — FRAME (HORIZONTAL) with gap 8, padding 4. Contains `Lucide/DollarSign` INSTANCE (40×40) + TEXT. Validates icon detection + HORIZONTAL row default + counterAxis CENTER → `alignItems: center`.
  - `absolute_badge` — FRAME (`layoutMode: NONE`) 200×120 with centered TEXT + corner RECTANGLE badge (`cornerRadius 9999`, 20×20, absolute). Validates position:relative on parent, position:absolute + top/left on children, circle detection (radius ≥ half-side).
- 44 unit tests (`test/codegen/figma_to_spec_test.dart`) covering each rule in isolation: envelope shape, color/alpha/opacity normalization, gradient parsing + fallback, radius collapse + circle heuristic, drop shadow composition (multi-shadow + INNER_SHADOW inset), typography (lineHeightPercent, textAlign/textCase, 500-char clip, letterSpacing omission), layout/align mapping (all 4 primary + counter axes), icon detection (lucide/phosphor/heroicons case-insensitive + VECTOR anonymous), bounds relativization, invisible/zero-size skipping, idempotency.
- 19 integration tests (`test/codegen/figma_integration_test.dart`) via `Process.run`: 3 golden fixture matches (stdout JSON-equals expected), `--output`/`--source-url`/`--state-name`/`--force`/`--json` flag behavior, error paths (missing input, malformed JSON, non-object root, no recognizable node), **plus 3 `figma-spec → scaffold` chain tests asserting no TODO markers** on simple fixtures (the consumability gate — the generated spec has to drive scaffold cleanly).
- `doc/pipeline-gaps/figma-adapter.md` — CLI reference, normalization rules table, known limits (no live REST, no SVG synthesis, no variant resolution beyond string matching), follow-up work.

**Validation criteria:**
- ✅ `dart analyze lib/src/codegen/figma_to_spec.dart lib/src/cli/commands/figma_spec_command.dart lib/src/cli/cli_runner.dart` — clean
- ✅ `flutter test test/codegen/figma_to_spec_test.dart test/codegen/figma_integration_test.dart` — 63 tests green (44 unit + 19 integration)
- ✅ `flutter test` globally — 181 tests green (118 prior + 63 new), no regressions
- ✅ `dart run bin/print_widget.dart figma-spec --help` — usage prints cleanly
- ✅ Banner lists `figma-spec`; `--llm-guide` has a "Figma to spec" section
- ✅ All 3 synthetic fixtures produce expected envelopes byte-for-byte; each one chains through `scaffold` without TODO markers

**Validation still pending (empirical):**
- Drive the adapter against a **real** Figma MCP response from `get_design_context` on an actual file. Target: the emitted spec scaffolds to a Flutter widget that renders close to the Figma frame on first `generate + compare`. The first Figma-sourced project this ships alongside becomes the canary.
- Explicitly punted for MVP: live Figma REST calls (pure-data normalization only), SVG synthesis from vector path data, variant / InstanceSwap resolution beyond string-matching on `mainComponent.name`/`componentProperties`/node `name`.

## Final gate (end of Phase 5)

Target: **≥70% reduction in per-atom human interventions** on the canary set. Measured as:

- Per-atom iteration count (captured by `compare --json` logs)
- Per-atom intervention count (captured from session transcripts, same methodology as the April 2026 analysis)

If we don't hit 70%, the plan needs revisiting before shelving Phase 7 (Figma adapter).
