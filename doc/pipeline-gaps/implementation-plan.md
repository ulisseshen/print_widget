# Spec Pipeline Implementation Plan

**Branch:** `feat/spec-pipeline`
**Goal:** Close the pixel-guessing gap identified in `gaps-analysis.md` by introducing a structured intermediate representation (spec/IR) between extracted designs and Flutter code. Reduce per-widget HITL from ~40% of interventions to ~10% while keeping setup-phase HITL intact.

This plan is ordered by **impact-per-effort**, not by conceptual dependency. Each phase is independently shippable; you get value even if you stop mid-way.

---

## 0. Pre-flight

Before writing any pipeline code:

1. Commit the CRM atom work that's currently dirty in the branch (atoms + promo_flow widgets + config changes). They're the empirical baseline we'll re-run after each phase to measure HITL reduction.
2. Lock down a single "canary atom" from that build — probably `atom_icon_badge` or `atom_delta_indicator` — that's simple enough to trace end-to-end and complex enough to expose bugs (text + icon + background + radius).
3. Capture the current baseline: how many iterations did each atom take in the CRM build? We need the before-number to claim any after-improvement.

**Deliverables:** commit the dirty work, choose canary atom, record baseline iteration counts in `gaps-analysis.md` addendum.

---

## 1. Architecture overview

```
┌───────────────────────────────────────────────────────────────┐
│  EXISTING PIPELINE                                            │
│                                                               │
│  URL/Figma ──► extract ──► crops + _DESIGN.md (agregate)      │
│                              │                                │
│                              ▼                                │
│                         AI writes Flutter (guesses from px)   │
│                              │                                │
│                              ▼                                │
│                     print_widget generate                     │
│                              │                                │
│                              ▼                                │
│                     print_widget compare (pixelmatch)         │
│                              │                                │
│                              ▼                                │
│                       iterate loop (15x cap)                  │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  NEW PIPELINE (this plan)                                     │
│                                                               │
│  URL/Figma ──► extract --spec ──► crops + _DESIGN.md          │
│                               + <crop>_spec.json (NEW)        │
│                              │                                │
│                              ▼                                │
│                  scaffold ──► <name>_scaffold.dart (NEW)      │
│                              │                                │
│                              ▼                                │
│                   print_widget generate + compare             │
│                   (validates LAYOUT of scaffold, Pass 1)      │
│                              │                                │
│                              ▼                                │
│                  tokenize ──► <name>.dart (NEW)               │
│                   (maps raw → theme tokens, AST)              │
│                              │                                │
│                              ▼                                │
│                   print_widget generate + compare             │
│                   (validates TOKEN SWAP, Pass 2)              │
│                              │                                │
│                              ▼                                │
│                  snapshot (NEW) ──► .reference/ Flutter-native │
│                              │                                │
│                              ▼                                │
│                   future iterations: Flutter-to-Flutter        │
│                   (eliminates font ceiling)                    │
└───────────────────────────────────────────────────────────────┘
```

Four new artifacts:

1. **`<crop>_spec.json`** — per-element DOM tree with computed styles (the IR)
2. **`<name>_scaffold.dart`** — mechanical Flutter codegen from spec (raw values, no tokens)
3. **`<name>.dart`** — tokenized production widget (after AST pass)
4. **`.reference/<device>.png` promoted from generated** — Flutter-native baseline

Each is independently useful. You can use `_spec.json` alone with the current AI-writes-Flutter workflow and still get massive gains (the AI has exact values instead of pixel guesses).

---

## 2. Phase 1 — Spec extraction (highest value)

**Why first:** 100% additive. Zero breaking changes. The spec file sits next to the crop PNG; agents can read it if they want, skip it if they don't. The whole rest of the pipeline is a no-op without spec, but the AI can use the spec *today* and skip the pixel-guessing phase.

### 2.1 Scope

Add `extractStructureInBrowser(clipBounds)` to `lib/src/tools/extract.mjs`. Runs once per crop detected by `collectSectionsInBrowser()`. Outputs `<crop>_spec.json` next to each crop PNG.

### 2.2 File-level changes

**`lib/src/tools/extract.mjs`**
- Add `extractStructureInBrowser(clip)` after `extractTokensInBrowser()` (around line 302)
- Modify `captureState()`: after the crop loop (line 454), iterate `cropIndex` again and call `extractStructureInBrowser` via `page.evaluate((c) => extractStructureInBrowser(c), crop)`. Write result as `<crop_basename>_spec.json`
- Add `chromePurge` step early in `runSteps` (before any screenshots), driven by `config.chromePurge: string[]` of CSS selectors to remove from DOM. Use `page.evaluate(sels => { for (const s of sels) document.querySelectorAll(s).forEach(el => el.remove()); }, sels)`

**Spec JSON v1 shape** (permissive, no JSON Schema enforcement yet):

```json
{
  "$version": "1.0",
  "source": { "url": "...", "extractor": "extract.mjs@0.8.0" },
  "crop": { "file": "02-kpi-card.png", "bounds": { "x": 0, "y": 0, "w": 320, "h": 200 } },
  "root": {
    "tag": "div",
    "bounds": { "x": 0, "y": 0, "w": 320, "h": 200 },
    "styles": {
      "display": "flex",
      "flexDirection": "column",
      "padding": { "top": 20, "right": 20, "bottom": 20, "left": 20 },
      "backgroundColor": "rgba(255, 255, 255, 0.7)",
      "borderRadius": 16,
      "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
    },
    "children": [
      {
        "tag": "div",
        "role": "row",
        "styles": { "display": "flex", "alignItems": "center", "gap": 12 },
        "children": [
          {
            "tag": "div",
            "role": "icon_container",
            "bounds": { "w": 40, "h": 40 },
            "styles": {
              "backgroundColor": "rgba(11, 162, 132, 0.12)",
              "borderRadius": "50%",
              "display": "flex",
              "alignItems": "center",
              "justifyContent": "center"
            },
            "children": [
              {
                "tag": "svg",
                "icon": { "library": "lucide", "name": "dollar-sign" },
                "svgHtml": "<svg>...</svg>",
                "bounds": { "w": 20, "h": 20 },
                "styles": { "color": "#0BA284" }
              }
            ]
          },
          {
            "tag": "span",
            "text": "Faturamento",
            "typography": {
              "fontFamily": "Inter",
              "fontSize": 16,
              "fontWeight": 600,
              "lineHeight": 20,
              "letterSpacing": "normal",
              "color": "#0F1729"
            }
          }
        ]
      }
    ]
  }
}
```

**Walker rules** (from `gaps-analysis.md` §6.1 with refinements):
- Skip nodes outside clip bounds (bounds test against `clip`)
- Skip `display:none`, `visibility:hidden`, zero-size
- Skip `display: contents` wrappers (recurse through them, don't emit a node)
- For text leaves: capture typography explicitly
- For SVGs: capture `outerHTML` + detected icon library/name (reuse existing logic from `extractTokensInBrowser`)
- Depth cap: 12 levels
- Children array only emitted if non-empty

### 2.3 Edge cases to handle in v1

- **Absolute-positioned elements**: capture `position`, `top/left/right/bottom` in styles; scaffold Phase 4 will translate to `Positioned`/`Stack`
- **Flex with `flex: 1`**: capture `flexGrow` so scaffold can emit `Expanded`
- **`text-overflow: ellipsis`**: capture so Flutter can mirror with `overflow: TextOverflow.ellipsis`
- **Background gradients**: capture raw gradient string; scaffold translates to `LinearGradient`/`RadialGradient`
- **Transforms** (rotate/scale): capture; scaffold emits `Transform`

### 2.4 Validation

1. Run against canary atom's URL. Hand-verify the emitted spec matches the DOM (spot-check 3 elements).
2. Run against 3 more CRM atoms. Confirm parent-child relationships, typography, and icon capture are correct.
3. Feed the spec to an agent via a test prompt: "Given this spec, write the Flutter widget." Compare agent output against prior CRM output. Did padding/fontsize errors disappear?

### 2.5 Deliverables

- Updated `lib/src/tools/extract.mjs`
- New `doc/pipeline-gaps/spec-format.md` documenting the spec v1 shape
- Updated `print-widget-extract` skill (`SKILL.md`) to describe the new output
- A canary-atom walkthrough in `doc/pipeline-gaps/canary-validation.md`

---

## 3. Phase 2 — Snapshot command (cheap, high-leverage)

**Why second:** 1 day of work. Solves the font rendering ceiling problem for all subsequent iterations. Doesn't depend on spec.

### 3.1 Scope

New command `print_widget snapshot` that promotes the current generated PNG to the reference position, so future `compare` runs are Flutter-to-Flutter (no Skia vs Chromium gap).

### 3.2 File-level changes

**New `lib/src/cli/commands/snapshot_command.dart`** with:
```bash
print_widget snapshot --name=<entry>         # promotes single entry's generated → .reference/
print_widget snapshot --name=<entry> --device=pixel_7   # device-specific
print_widget snapshot --all                  # promotes every entry with a generated output
print_widget snapshot --force                # overwrite existing reference
```

Behavior:
- Reads `output_dir` and `reference_dir` from `print_widget.yaml`
- For each target entry, copies `<outputDir>/<name>/<device>.png` → `<outputDir>/<name>/<referenceDir>/<device>.png`
- If the entry has `crops/`, also copies `<outputDir>/<name>/crops/*.png` → `<outputDir>/<name>/<referenceDir>/crops/*.png`
- Refuses overwrite unless `--force`
- Prints summary: "Promoted N entries, skipped M (already have reference)"

**Registration:** add `SnapshotCommand()` to `cli_runner.dart`.

### 3.3 Skill integration

Update `iterate.md`:
- After Phase A (layout converges vs browser ref with `cross_engine_threshold`), suggest running `snapshot` before Phase B
- Document the "Flutter-to-Flutter reference" concept explicitly

### 3.4 Deliverables

- `lib/src/cli/commands/snapshot_command.dart`
- Banner + `--llm-guide` updated with the new command
- Integration test: `test/snapshot_command_test.dart`
- Docs: add section to `doc/compare.md`

---

## 4. Phase 3 — Adaptive per-entry thresholds

**Why third:** Another cheap win. Removes agents wasting iterations chasing 0.95 on text-heavy widgets where 0.88 is the real ceiling.

### 4.1 Scope

Support per-entry threshold overrides in `print_widget.yaml`:

```yaml
compare_threshold: 0.95              # default (Flutter-to-Flutter)
cross_engine_threshold: 0.88         # new — used when reference is browser-originated
thresholds:
  home/atoms/performance/delta_badge_positive: 0.90
  home/molecules/performance/kpi_card: 0.85
```

### 4.2 File-level changes

**`lib/src/cli/commands/compare_command.dart`**:
- Read `thresholds:` map and `cross_engine_threshold` from yaml (around line 82)
- For each entry, resolve threshold via priority: CLI `--threshold` > `thresholds.<entry>` > (if reference has `_origin: browser` flag) `cross_engine_threshold` > `compare_threshold`
- Print the resolved threshold in output so users see why a widget stopped below 0.95

**Reference origin marker:**
- When smart-extract skill copies crops to `.reference/`, write `.reference/_origin.json` with `{ "origin": "browser", "url": "...", "extracted_at": "..." }`
- When `snapshot` promotes generated crops, write `.reference/_origin.json` with `{ "origin": "flutter", "promoted_at": "..." }`
- `compare` reads `_origin.json` to pick the threshold

### 4.3 Deliverables

- Updated `compare_command.dart`
- Snapshot and smart-extract both write `_origin.json`
- Updated `doc/compare.md` explaining the threshold hierarchy
- Integration test for threshold resolution priority

---

## 5. Phase 4 — Scaffold codegen

**Why fourth:** Requires spec (Phase 1). Bigger scope than Phases 2–3. Delivers the "mechanical compilation" benefit — the AI never touches the scaffold, so padding/color/fontsize errors become impossible by construction.

### 5.1 Scope

New command `print_widget scaffold` that reads a spec JSON and emits a Flutter widget with literal values (no tokens, no custom components).

```bash
print_widget scaffold \
  --spec=print_widget/output/.specs/kpi_card_spec.json \
  --class-name=_KpiCardScaffold \
  --output=lib/ui/features/home/widgets/kpi_card_scaffold.dart
```

### 5.2 File-level changes

**New `lib/src/cli/commands/scaffold_command.dart`** — thin wrapper, parses args, dispatches to:

**New `lib/src/codegen/scaffold_generator.dart`** — the compiler.

Codegen rules (mechanical, no AI):

| Spec node | Flutter emission |
|---|---|
| `display: flex + flexDirection: column` | `Column(children: [...])` |
| `display: flex + flexDirection: row` | `Row(children: [...])` |
| `display: grid` | `GridView.count` or `Wrap` depending on columns + flexBasis |
| `display: block` with single child | skip the wrapper, emit child directly (flattens) |
| `gap: N` on flex parent | `SizedBox(width/height: N)` interleaved between children |
| `padding: { top, right, bottom, left }` | `Padding(padding: EdgeInsets.fromLTRB(...))` or `EdgeInsets.all(N)` if symmetric |
| `backgroundColor + borderRadius + boxShadow` | wrap in `Container(decoration: BoxDecoration(...))` |
| `position: absolute` | ancestor becomes `Stack`, node becomes `Positioned` |
| `text + typography` | `Text('...', style: TextStyle(...))` |
| `svgHtml` | `SvgPicture.string('''<svg>...</svg>''')` (requires `flutter_svg`) |
| `borderRadius: 50%` or `shape: circle` | `BoxDecoration(shape: BoxShape.circle)` |
| `flexGrow: 1` | wrap in `Expanded` |
| `overflow: hidden + text-overflow: ellipsis` | `Text(..., overflow: TextOverflow.ellipsis)` |
| unknown/unhandled | emit `// TODO: manual layout — spec node: {type}` with a `SizedBox` placeholder |

### 5.3 Color literal format

Spec stores `"rgba(255,255,255,0.7)"` or `"#0F1729"`. Generator emits `Color(0xB3FFFFFF)` (alpha-first ARGB). Always a literal — no theme lookups in scaffold.

### 5.4 File header

Every generated file gets:
```dart
// AUTO-GENERATED by print_widget scaffold — do not edit.
// Source spec: <path>
// Generated: <timestamp>
// To re-generate: print_widget scaffold --spec=<path> --class-name=<name> --output=<path>
```

### 5.5 Validation

- Codegen golden tests: 5 spec JSONs → 5 expected Dart files
- Round-trip: generate from spec → run `print_widget generate` on the scaffold → compare against original browser reference. Target: Phase 1 threshold (cross_engine ≥ 0.85).
- Canary atom end-to-end: does scaffold match the reference layout without AI touching it?

### 5.6 Deliverables

- `lib/src/cli/commands/scaffold_command.dart`
- `lib/src/codegen/scaffold_generator.dart` (pure Dart, no external deps besides `package:path`)
- Tests: `test/codegen/scaffold_generator_test.dart` with spec→dart fixtures in `test/codegen/fixtures/`
- `doc/pipeline-gaps/scaffold.md` with examples + codegen rules table
- Banner + `--llm-guide` updated

---

## 6. Phase 5 — Tokenize pass (AST-based)

**Why fifth:** Needs scaffold (Phase 4). Closes the "hardcoded values" feedback loop — takes a scaffold (raw literals) and a theme ref and produces a production widget with tokens.

### 6.1 Scope

New command `print_widget tokenize`:

```bash
print_widget tokenize \
  --input=lib/ui/features/home/widgets/kpi_card_scaffold.dart \
  --theme=print_widget/theme-ref.json \
  --output=lib/ui/features/home/widgets/kpi_card.dart \
  --strategy=exact          # or 'near' to use ΔE < 2.0 fuzzy match
```

### 6.2 Theme reference format

`theme-ref.json` is manually authored for the MVP (later a generator). Shape:

```json
{
  "name": "smartsales",
  "colors": {
    "palette": {
      "#0BA284": "primary500",
      "#0F1729": "text.primary",
      "#6B7280": "text.muted",
      "#F3F4F6": "surface.muted"
    },
    "accessor": "context.customColors"
  },
  "spacing": {
    "scale": { "0": 0, "4": 1, "8": 2, "12": 3, "16": 4, "20": 5, "24": 6, "32": 8 },
    "class": "YHAppSpacing",
    "prefix": "sp"
  },
  "radius": {
    "scale": { "4": 1, "8": 2, "12": 3, "16": 4, "9999": "full" },
    "class": "YHAppCornerRadiusV2",
    "prefix": "r"
  },
  "typography": {
    "helper": "interText",
    "signature": "interText({required double size, required int weight, Color? color, double? height})"
  }
}
```

A matching `theme-ref.json` is already in `.claude/skills/print-widget/theme-ref.json` — we extend its shape.

### 6.3 Implementation

**MVP (phase 5a):** regex-based transformer in `lib/src/codegen/tokenizer.dart`. Handles:
- `Color(0xFFXXXXXX)` → `context.customColors.<token>` (or leave as-is with `// FORCE: no token match`)
- `EdgeInsets.all(N)` / `.symmetric` / `.fromLTRB` → `EdgeInsets.all(YHAppSpacing.sp<N>)`
- `BorderRadius.circular(N)` → `BorderRadius.circular(YHAppCornerRadiusV2.r<N>)`
- `TextStyle(fontSize: N, fontWeight: FontWeight.wN, ...)` → `interText(size: N, weight: N, ...)`

**Upgrade (phase 5b, if needed):** AST via `package:analyzer` for precise scope handling and multi-line TextStyle detection. Only do this if regex produces false positives in real code.

Output header:
```dart
// TOKENIZED from kpi_card_scaffold.dart
// Theme: smartsales
// Substitutions: 12 colors, 8 spacing, 3 radius, 5 typography
// Forced (no token match): 1 color (Color(0xFF8FC3C3))
```

### 6.4 Validation

- Unit tests per substitution kind
- Integration: tokenize the scaffold output from Phase 4's canary atom → run generate+compare → score MUST be identical (within 0.5pp) to the scaffold's score. Any delta = regression in the tokenizer.

### 6.5 Deliverables

- `lib/src/cli/commands/tokenize_command.dart`
- `lib/src/codegen/tokenizer.dart`
- Tests: `test/codegen/tokenizer_test.dart` with before/after fixtures
- `doc/pipeline-gaps/tokenize.md` with theme-ref schema + examples
- Example `theme-ref.json` for the example project

---

## 7. Phase 6 — Skills integration (two-pass awareness)

**Why sixth:** With Phases 1–5 in place, the skills need to know the new commands exist and how to use them.

### 7.1 Scope

Update `.claude/skills/print-widget/*.md` (then regenerate the local AI skill files committed in the repo):

**`iterate.md`** — add:
- "Pass A / Pass B" section explaining scaffold-first then tokenize
- "Font rendering ceiling" section with recognition pattern + stop condition (already partially exists, formalize it)
- "Heatmap interpretation guide" — lookup table mapping pink patterns to code changes (full table is in `gaps-analysis.md` §7.4)
- Stop conditions checklist

**`review.md`** — add:
- "Pre-flight: reference hygiene" — verify no platform chrome, correct font loaded, correct viewport
- "Post-tokenize invariant" — verify token swaps didn't change pixel score

**`conventions.md`** — add:
- "Scaffold-first development" section — start from generated scaffold, never from scratch, tokenize as a separate commit

**`lovable.md`** — update to reference new `--spec` flag of `extract.mjs`.

**`parallel.md`** — add rule: "never run `generate --delete-old` without `--name`; never edit `.claude/skills/` during parallel session."

Then run `print_widget skills --update` locally to regenerate the variants for Cursor/Codex/Antigravity.

### 7.2 Deliverables

- Updated skill .md files
- Regenerated local AI skill files (the `chore(skills): regenerate local AI skill files` commit pattern)
- Test: install fresh skill in mogadishu worktree, run canary build, confirm new flow

---

## 8. Phase 7 — Figma side (stretch)

Defer unless explicitly prioritized. The gaps-analysis proposes a Figma adapter that normalizes MCP output into the same spec v1 shape. That's 1–2 weeks of work and only valuable if we have a Figma-sourced project to validate against. For now, spec coverage is browser-only (Lovable/web).

Placeholder: `doc/pipeline-gaps/figma-adapter.md` with the design, blocked until there's a real driver.

---

## 9. Docs and README updates

### 9.1 Root-level docs

**`README.md`** (project root, not this folder) — update:
- Command list: add `scaffold`, `tokenize`, `snapshot`
- Pipeline diagram: show the new spec-first flow
- "How it works" section: two-pass architecture

**`CLAUDE.md`** — update:
- CLI commands table: add the three new commands
- "How generation works" section: mention spec + scaffold + tokenize
- Keep "Key conventions" intact

**`lib/src/cli/cli_runner.dart`** — update:
- `_printBanner()`: add the three new commands to the list
- `_printLlmGuide()`: add a new section for spec/scaffold/tokenize with examples

### 9.2 Per-feature docs in `doc/`

New files:
- `doc/pipeline-gaps/spec-format.md` — the spec v1 schema + examples (from Phase 1)
- `doc/pipeline-gaps/canary-validation.md` — baseline and results (from Phase 0 + each phase's validation)
- `doc/pipeline-gaps/scaffold.md` — scaffold codegen reference (from Phase 4)
- `doc/pipeline-gaps/tokenize.md` — tokenize pass reference (from Phase 5)

Updates to existing:
- `doc/compare.md` — threshold hierarchy (Phase 3), `_origin.json` convention (Phase 3)
- `doc/smart-extract.md` — `--spec` flag + `chromePurge` option (Phase 1)
- `doc/big-picture.md` — update pipeline diagram (after Phase 4)
- `doc/architecture.md` — add IR-layer rationale

### 9.3 Skills (already covered in Phase 6)

---

## 10. Validation strategy

Each phase's validation feeds into a single living document: `doc/pipeline-gaps/canary-validation.md`.

Metrics captured per phase, per canary atom:
- **Iterations to converge** (current pipeline: N; new pipeline: M)
- **Human interventions during build** (count of corrections, redirections, visual audit catches)
- **Final pixelmatch score**
- **HITL reduction %** — ratio of (interventions new / interventions old)

Target at the end of Phase 5: **≥70% reduction in per-atom interventions** on the canary set (3–5 atoms).

---

## 11. Risks and unknowns

| Risk | Mitigation |
|---|---|
| Spec misses edge cases (weird Lovable DOM patterns) | Start permissive; emit unknown patterns as raw strings + `// TODO: manual` in scaffold |
| Scaffold codegen produces ugly Dart that's hard to review | Add a `dart format` pass at the end; accept ugliness as transitional (tokenize cleans up) |
| Tokenizer false positives (e.g. `Color(0xFF000000)` used as a sentinel, not a design color) | Regex MVP will have false positives; gate with `--strategy=exact` and escape hatch comments; upgrade to AST when measured |
| Theme-ref.json drift from actual theme code | Longer term: auto-generate from Dart source; for MVP, manual with a linter |
| Flutter version differences in generated code (const constructors, new widget APIs) | Lock to the user's installed Flutter version during codegen; emit same style as the existing project |
| SVG handling (`flutter_svg` not always in the project) | Detect from pubspec; fall back to `Icon()` placeholder if not present |

---

## 12. Decision points requiring your input

These shape the implementation. Answers before Phase 1 starts:

1. **Spec schema enforcement**: v1 permissive (no JSON Schema validator) vs strict from day 1?
   → **Recommendation: permissive v1; add JSON Schema in v1.1 once the shape stabilizes.**

2. **Scaffold output location**: emit next to the production widget as `_scaffold.dart`, or under `<outputDir>/.scaffolds/`?
   → **Recommendation: next to production as `_scaffold.dart`. Easier to git-track and diff during tokenize.**

3. **Tokenize MVP language**: regex-based or go straight to AST via `package:analyzer`?
   → **Recommendation: regex MVP. Upgrade only if we hit false positives in real code.**

4. **Theme-ref.json authoring**: manual for MVP, auto-generator later?
   → **Recommendation: manual MVP. Ship the smartsales theme-ref.json as a fixture. Auto-gen is Phase 8+.**

5. **Branch strategy**: one big PR at the end, or per-phase PRs?
   → **Recommendation: per-phase commits on this branch; squash-merge at phase 5 when we have end-to-end evidence. Optional early merge after Phase 2+3 (snapshot + thresholds) since those are standalone.**

6. **Phase 6 skills update**: update skills alongside commands (synchronized), or delay until all commands land?
   → **Recommendation: update skills incrementally per phase. Phase 1 skill update teaches agents to read `_spec.json`; they can ignore the later phases until those land.**

7. **Canary atom choice**: which specific atom(s) from the CRM build do we use as the end-to-end test?
   → **Need input: `atom_icon_badge`? `atom_kpi_card`? Pick 2–3 that span the complexity range.**

---

## 13. Implementation order summary

```
Phase 0:  commit CRM work + pick canary + record baseline   [half day]
Phase 1:  extract --spec + _spec.json                       [3–5 days]
Phase 2:  snapshot command                                  [1 day]
Phase 3:  per-entry thresholds + _origin.json               [1 day]
Phase 4:  scaffold command + codegen                        [1–2 weeks]
Phase 5:  tokenize command + theme-ref                      [1 week]
Phase 6:  skills + docs update                              [2–3 days]
Phase 7:  Figma adapter (stretch, deferred)                 [—]

Total:  ~4–5 weeks focused work, 6–8 weeks calendar.
```

Kill switches: after Phase 2+3 you can stop and ship — snapshot + thresholds alone solve the font ceiling and stop-iteration-too-early problems. Phase 1 alone gives agents exact values. Phases 4–5 are the full autonomy play.

---

## Appendix A — File inventory (new + modified)

**New files:**
- `lib/src/cli/commands/snapshot_command.dart`
- `lib/src/cli/commands/scaffold_command.dart`
- `lib/src/cli/commands/tokenize_command.dart`
- `lib/src/codegen/scaffold_generator.dart`
- `lib/src/codegen/tokenizer.dart`
- `test/codegen/scaffold_generator_test.dart`
- `test/codegen/tokenizer_test.dart`
- `test/codegen/fixtures/*` (spec→dart, scaffold→tokenized fixtures)
- `doc/pipeline-gaps/spec-format.md`
- `doc/pipeline-gaps/scaffold.md`
- `doc/pipeline-gaps/tokenize.md`
- `doc/pipeline-gaps/canary-validation.md`

**Modified files:**
- `lib/src/tools/extract.mjs` (spec extractor + chromePurge)
- `lib/src/cli/cli_runner.dart` (register new commands, banner, --llm-guide)
- `lib/src/cli/commands/compare_command.dart` (per-entry thresholds, _origin.json)
- `README.md`
- `CLAUDE.md`
- `doc/compare.md`
- `doc/smart-extract.md`
- `doc/big-picture.md`
- `doc/architecture.md`
- `.claude/skills/print-widget/iterate.md`
- `.claude/skills/print-widget/review.md`
- `.claude/skills/print-widget/conventions.md`
- `.claude/skills/print-widget-extract/SKILL.md`
- `.claude/skills/print-widget/parallel.md`
- All regenerated skill files under `.claude/skills/**`, `.cursor/rules/**`, `.agents/skills/**`, etc.
