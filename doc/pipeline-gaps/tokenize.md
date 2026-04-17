# Tokenize pass

`print_widget tokenize` is Phase 5 of the spec pipeline. It takes a **scaffold** (the literal-value Flutter source emitted by `print_widget scaffold`) plus a **theme-ref.json** and produces a production widget where raw literals have been replaced with design-system tokens. No AI in the loop; substitution rules are deterministic.

The tokenize pass is the second leg of the two-pass architecture:

1. `scaffold` locks **layout** using raw values. Compare against the browser reference, iterate until cross-engine ≥ 0.88.
2. `tokenize` locks **visual parity with the design system** by swapping literals for tokens. The swap is invariant: pixel output should match the scaffold exactly (within ~0.5pp). Any delta indicates a broken token mapping.

## CLI

```
print_widget tokenize --input=<scaffold.dart> --theme=<theme-ref.json>
print_widget tokenize --input=<scaffold.dart> --theme=<theme-ref.json> --output=lib/widgets/kpi_card.dart
print_widget tokenize --input=<scaffold> --theme=<theme> --stdout
print_widget tokenize --input=<scaffold> --theme=<theme> --strategy=near --tolerance=2.0
print_widget tokenize --input=<scaffold> --theme=<theme> --json
print_widget tokenize --input=<scaffold> --theme=<theme> --output=<path> --force
```

### Flags

| Flag | Required | Default | Notes |
|---|---|---|---|
| `-i, --input=<path>` | Yes | — | Path to the scaffold `.dart` file. |
| `-t, --theme=<path>` | Yes | — | Path to the theme-ref JSON file. |
| `-o, --output=<path>` | No | Input with `_scaffold.dart` → `.dart`; else `<stem>_tokenized.dart` | Creates parent dir if missing. |
| `--strategy=exact\|near` | No | `exact` | `near` enables ΔE-CIE76 fuzzy color match. |
| `--tolerance=<N>` | No | `2.0` | ΔE tolerance used when `strategy=near`. |
| `--stdout` | No | false | Print to stdout; skip file I/O. |
| `-f, --force` | No | false | Overwrite `--output` if it already exists. |
| `--json` | No | false | Emit `{output, substitutions, forced, counts}` JSON report. |

## Theme-ref schema (new keys)

`tokenize` extends the existing `theme-ref.json` schema used by `extract.mjs` (which owns `palette`, `semanticOverrides`, `spacingScale`, `typographyScale`, `fontWeightMap`). The new keys are read only by tokenize; the old keys remain untouched so the extract flow keeps working.

```json
{
  "name": "smartsales",

  "colors": {
    "accessor": "context.customColors",
    "tokenMap": {
      "#0BA284": "brand30",
      "#0F1729": "textPrimary",
      "#6B7280": "textMuted",
      "#F3F4F6": "surfaceMuted"
    },
    "semantic": {
      "#0BA284": { "token": "brand30", "role": "primary" }
    }
  },

  "spacing": {
    "class": "YHAppSpacing",
    "prefix": "sp",
    "scale": {
      "0": 0, "4": 1, "8": 2, "12": 3, "16": 4, "20": 5, "24": 6,
      "32": 8, "40": 10, "48": 12
    }
  },

  "radius": {
    "class": "YHAppCornerRadiusV2",
    "prefix": "r",
    "scale": {
      "4": 1, "8": 2, "12": 3, "16": 4, "24": 6, "9999": "full"
    }
  },

  "typography": {
    "helper": "interText",
    "signature": "interText({required double size, required int weight, Color? color, double? height, double? letterSpacing})",
    "import": "package:yh_design_system/typography/inter_text.dart"
  }
}
```

### Field semantics

- **`colors.accessor`** — prefix for the emitted reference. `context.customColors` is the common case; setting it to `AppColors` produces static references.
- **`colors.tokenMap`** — `"#RRGGBB": "<tokenName>"`. Hex keys are uppercase, no alpha (alpha is handled by the tokenizer via `withValues(alpha:)`).
- **`spacing.scale`** — `"<px>": "<suffix>"`. The suffix is appended to `<class>.<prefix>`. `"16": 4` emits `YHAppSpacing.sp4`. Numeric and string suffixes both work — `"9999": "full"` emits `YHAppCornerRadiusV2.rfull`.
- **`radius.scale`** — same shape as spacing.scale.
- **`typography.helper`** — function name used in place of `TextStyle(...)`. If set, only `TextStyle` blocks with `fontFamily: 'Inter'` are rewritten; other font families remain as `TextStyle` (with their color still tokenized).
- **`typography.import`** — Dart import statement added to the output when any TextStyle → helper rewrite fires.

## Substitution rules

### Colors

Input: `Color(0xAARRGGBB)`.

1. Split into alpha (`AA`) and RGB (`RRGGBB`).
2. Normalize `#RRGGBB` uppercase.
3. Look up in `colors.tokenMap`.
   - **`strategy=exact` + no match** → preserve the literal, prepend `// FORCE: no token match for Color(0xFF...) in colors.tokenMap`.
   - **`strategy=near` + no exact** → find the token with lowest ΔE-CIE76; accept if ΔE ≤ tolerance; record a `"near ΔE=1.7 → brand30"` note.
4. Emit `context.customColors.<token>` when alpha == 0xFF.
5. Emit `context.customColors.<token>.withValues(alpha: <0.N>)` when alpha < 0xFF. `<0.N>` is `alpha / 255` rounded to 2 decimals. Note: `withValues(alpha:)` is the modern Flutter API — the deprecated `withOpacity` is **never** emitted.
6. **Sentinels preserved:** `Color(0xFFFFFFFF)` and `Color(0x00000000)` pass through unchanged unless explicitly mapped in `tokenMap`.

### Spacing

Input: `EdgeInsets.all(N)`, `.symmetric(horizontal: H, vertical: V)` (either order), `.fromLTRB(l, t, r, b)`, `SizedBox(width: N, height: N)`, standalone `width: N,` / `height: N,` arguments.

1. For each numeric arg, look up `N` in `spacing.scale`.
2. On match, substitute `<class>.<prefix><suffix>` — e.g. `YHAppSpacing.sp4`.
3. On miss, keep the literal AND record a per-arg FORCE entry. A single line may emit one FORCE comment covering all missing values.

Example (from the canary `status_badge`):

```dart
// FORCE: no token match for 10 in spacing.scale
padding: EdgeInsets.symmetric(horizontal: 10, vertical: YHAppSpacing.sp1),
```

### Radius

Input: `BorderRadius.circular(N)`.

1. Look up `N` in `radius.scale`.
2. Emit `BorderRadius.circular(<class>.<prefix><suffix>)` — e.g. `BorderRadius.circular(YHAppCornerRadiusV2.r4)`.
3. `"9999": "full"` → `BorderRadius.circular(YHAppCornerRadiusV2.rfull)` (canonical pill shape).
4. `BoxShape.circle` — pass through, no substitution required.
5. On miss — FORCE comment.

### Typography

Input: scaffold's `TextStyle(fontFamily: 'Inter', fontSize, fontWeight, color, height, letterSpacing)`.

Output: `interText(size:, weight:, color:, height:, letterSpacing:)`.

Rules:
- Only `fontFamily: 'Inter'` rewrites to `interText`. Other fonts preserve `TextStyle` (but inner `color` still tokenizes).
- `FontWeight.wN` → `weight: N`. `FontWeight.bold` → `weight: 700`. `FontWeight.normal` → `weight: 400`.
- Inner `Color(0xAARRGGBB)` recursively tokenizes via the color rules.
- All original keys that appeared are preserved — nothing is dropped silently.

### SVG

`SvgPicture.string(''' ... ''', width: N, height: N)` — the **SVG markup inside the triple-quote string is never touched** (hex values like `fill="#0BA284"` are SVG attributes, not Dart tokens). The `width:` / `height:` args are tokenized via the generic width/height rule when they map to the spacing scale.

## Output header

Every tokenize output starts with:

```dart
// Tokenized by print_widget tokenize — do not edit.
// Scaffold source: lib/scaffolds/kpi_card_scaffold.dart
// Theme: smartsales
// Substitutions: 4 colors, 3 spacing, 1 radius, 2 typography
// Forced (no token match): 1 — see // FORCE: comments below
// Regenerate: print_widget tokenize --input=... --theme=... --output=...

import 'package:flutter/material.dart';
import 'package:yh_design_system/typography/inter_text.dart';
```

The scaffold's `AUTO-GENERATED` banner is replaced, not kept. The typography import is only added when any TextStyle → helper rewrite fired.

## `const` propagation

The scaffold emits `const _KpiCardScaffold({super.key});` unless it contains a non-const node (`SvgPicture.string`, for example). Tokenize introduces its own non-const references:

- `context.customColors.X` — instance getter
- `interText(...)` — regular function call

So: when any substitution lands a reference of either kind in the tree, the class constructor's `const` modifier is **dropped** automatically. This keeps the analyzer happy without the user having to fix it by hand.

## FORCE comments

When a literal can't be mapped, tokenize:

1. Preserves the literal in the output (it's valid Dart, just not a token reference).
2. Prepends a comment line above the offending line:
   ```dart
   // FORCE: no token match for Color(0xFF8FC3C3) in colors.tokenMap
   color: Color(0xFF8FC3C3),
   ```
3. Adds the literal to the `forced` list in the JSON report and to the header "Forced" summary.

The reviewer then has three choices:
- Add the hex to `colors.tokenMap` and re-tokenize.
- Keep the literal with the FORCE comment as a deliberate exception.
- Use `--strategy=near` to accept a close match (FORCE is replaced with a `near` note when ΔE ≤ tolerance).

## Idempotency

Running `tokenize` on an already-tokenized file is an error:

```
tokenize: input already contains tokenized references (context.customColors / YHAppSpacing / interText). Refusing to double-tokenize. Edit the scaffold, not the production widget.
```

Detection is a simple substring check for `context.customColors.`, `YHAppSpacing.`, `YHAppCornerRadiusV2.`, and `interText(`. This prevents chains of tokenization on drift (e.g. running tokenize on the output of tokenize).

## Implementation

MVP (v1): regex + brace counting on source text. Grammatically simple because scaffold output is deterministic — every `Color(0x...)` / `EdgeInsets.X(N)` / `TextStyle(...)` comes from one code path in `scaffold_generator.dart`. Comments in `lib/src/codegen/tokenizer.dart` mark the places where an AST pass via `package:analyzer` would be cleaner — those are the v1.1 upgrade paths.

## Integration with the pipeline

```
extract (--spec) ──► <crop>_spec.json
                         │
                         ▼
scaffold ──► <name>_scaffold.dart ──► generate + compare (cross-engine ≥ 0.88)
                         │
                         ▼
tokenize ──► <name>.dart        ──► generate + compare (pixel parity invariant)
                         │
                         ▼
snapshot (if not already)  ──► .reference/ Flutter-native baseline
```

## Known limitations of v1

- **Only `Color(0xAARRGGBB)` literal form** is rewritten. `Color.fromARGB`, `Color.fromRGBO`, and named Material colors (`Colors.teal`) are passed through. Scaffold never emits these, so this only matters if someone hand-edited the scaffold.
- **Non-Inter TextStyles** keep their `TextStyle(...)` shape. An explicit mapping per font family is a v1.1 feature.
- **No automatic `dart format`** — run `dart format` on the output yourself. The tokenizer aims for output that's *format-compatible*, not pre-formatted.
- **Regex misses if input drifts from scaffold's emission shape.** If you paste hand-written Flutter through tokenize, it mostly works, but weird whitespace around `TextStyle(` / `EdgeInsets.all(` can defeat the scanners. The fix is to run through `dart format` before tokenize.
