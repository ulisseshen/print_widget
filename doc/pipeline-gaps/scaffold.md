# Scaffold codegen

`print_widget scaffold` is the Phase 4 compiler of the spec pipeline. It reads a per-element `_spec.json` (emitted by `print_widget extract` — see [`spec-format.md`](spec-format.md)) and writes a **Flutter widget source file with literal values**. No tokens, no design-system components, no AI guessing. Same JSON in, same Dart out, every time.

The scaffold is the intermediate artifact between "exact DOM measurements" (the spec) and "production widget with tokens" (Phase 5 `tokenize`). You compare the scaffold against the browser reference with `print_widget compare` to **lock layout first**, then tokenize as a separate step to lock visual parity with the design system.

## When to use it

1. You ran `print_widget extract` against a URL and have a directory of `*_spec.json` files.
2. You want a mechanical starting point — something to iterate on — rather than staring at a PNG guessing paddings.
3. You want a before/after diff where "scaffold" is the before and the tokenized widget is the after.

If you don't have a `_spec.json`, run `extract` first; `scaffold` cannot guess from pixels.

## CLI

```
print_widget scaffold --spec=<path>                                       # auto class + output
print_widget scaffold --spec=<path> --stdout                              # dry-run, print to stdout
print_widget scaffold --spec=<path> --class-name=_Foo --output=lib/foo.dart
print_widget scaffold --spec=<path> --force                               # overwrite existing file
print_widget scaffold --spec=<path> --json                                # machine-readable result
```

### Flags

| Flag | Required | Default | Notes |
|---|---|---|---|
| `-s, --spec=<path>` | Yes | — | Path to the input `_spec.json`. |
| `--class-name=<name>` | No | `_` + PascalCase(spec stem minus `_spec` / `.spec`) | Generated class name. |
| `-o, --output=<path>` | No | `<cwd>/lib/scaffolds/<slug>_scaffold.dart` | Creates the parent directory if needed. |
| `--stdout` | No | false | Print to stdout, skip file I/O. |
| `-f, --force` | No | false | Overwrite `--output` if it already exists. |
| `--json` | No | false | Emit `{output, className, hasSvg, todoCount}` as JSON. |

### Stem derivation

`foo_spec.json`, `foo.spec.json`, `foo.json` all resolve to stem `foo`. The default class becomes `_FooScaffold` and the default output becomes `lib/scaffolds/foo_scaffold.dart`.

## Codegen rules

Every rule is deterministic. No AI, no heuristics beyond the literal spec value.

| Spec shape | Flutter emission |
|---|---|
| `display: flex, flexDirection: column` | `Column(crossAxisAlignment: ..., children: [...])` |
| `display: flex, flexDirection: row` (or default) | `Row(crossAxisAlignment: ..., children: [...])` |
| `display: grid` | `Wrap(children: [...])` + `// TODO: grid → review` |
| `display: block` single-child wrapper, no styles | the child is emitted directly (wrapper flattened) |
| `gap: N` on a flex parent | `SizedBox(width: N)` (row) or `SizedBox(height: N)` (column) interleaved between children |
| `padding: {t, r, b, l}` | `EdgeInsets.all(N)` if all equal, `.symmetric(h: H, v: V)` if opposing pairs match, else `.fromLTRB(l, t, r, b)` |
| `backgroundColor` + `borderRadius` + `boxShadow` | wrapped in `Container(decoration: BoxDecoration(...))`. Padding (if any) goes **inside** the Container (CSS semantics). |
| `borderRadius: "50%"` or `shape: circle` | `BoxDecoration(shape: BoxShape.circle)` — no `borderRadius:` emitted |
| `borderRadius: N` (number or `"Npx"`) | `BorderRadius.circular(N)` |
| `position: absolute` on a child | ancestor becomes `Stack`, child becomes `Positioned(top/right/bottom/left: N, child: ...)` |
| `text` + `typography` | `Text('...', style: TextStyle(...))` with literal color, family, size, weight, height |
| `svgHtml` | `SvgPicture.string('''...''')` with `width`/`height` from bounds |
| `flexGrow: 1` | wraps the node in `Expanded` |
| `overflow: hidden` + `textOverflow: ellipsis` | `Text(..., overflow: TextOverflow.ellipsis, maxLines: 1)` |
| `alignItems: center` | `crossAxisAlignment: CrossAxisAlignment.center` (also maps `flex-start`/`flex-end`/`stretch`/`baseline`) |
| `justifyContent: space-between` | `mainAxisAlignment: MainAxisAlignment.spaceBetween` (also maps `center`, `flex-start`, `flex-end`, `space-around`, `space-evenly`) |
| Unknown layout with no children | `SizedBox(width: bounds.w, height: bounds.h)` |
| Unknown layout with children | fallback `Column` with `// TODO: manual layout — spec: {json-snippet}` |

### Color handling — the easy-to-miss detail

CSS puts alpha **last**: `rgba(R, G, B, A)` or `#RRGGBBAA`. Flutter's `Color(0xAARRGGBB)` puts alpha **first**. The generator reorders.

| Spec value | Emitted |
|---|---|
| `rgb(11, 162, 132)` | `Color(0xFF0BA284)` (alpha implicit 0xFF) |
| `rgba(11, 162, 132, 0.12)` | `Color(0x1F0BA284)` — alpha = round(0.12 * 255) = 31 = 0x1F |
| `#0BA284` | `Color(0xFF0BA284)` |
| `#0BA284FF` | `Color(0xFF0BA284)` |
| `#0BA28480` (50% alpha) | `Color(0x800BA284)` |
| `transparent` / `rgba(0,0,0,0)` | property **omitted** — no backgroundColor emitted at all |

`Colors.white` / `Colors.black` shortcuts are **never** emitted. The output is always a literal `Color(0x...)` so downstream `tokenize` can do an exact-match pass.

### FontWeight mapping

| Spec value | Emitted |
|---|---|
| `400` | `FontWeight.w400` |
| `500` | `FontWeight.w500` |
| `700` | `FontWeight.w700` |
| `"bold"` | `FontWeight.bold` |
| `"normal"` | `FontWeight.w400` |
| anything else (e.g. `450`) | snapped to nearest 100 in [100, 900] |

### Text `height` — lineHeight divided by fontSize

If typography has both `lineHeight` and `fontSize` as numbers, the generator emits `height: lineHeight / fontSize` (rounded to 3 decimals). If either is missing or a string (`"normal"`), `height` is omitted so the consumer's default kicks in.

## `const` propagation

The generated class constructor is `const` unless the tree contains at least one `SvgPicture.string(...)`. `SvgPicture.string` is **not** a const constructor, so emitting `const _Foo()` with an SVG inside would fail to compile. When `hasSvg` is true:

- the class constructor loses its `const` modifier
- the `return ...;` inside `build()` is a non-const instantiation (Flutter handles that just fine)

`hasSvg` is returned via the `--json` output so the consumer can verify at a glance.

## Generated file header

Every output opens with a seven-line banner:

```dart
// AUTO-GENERATED by print_widget scaffold — do not edit.
// Source spec: <relative path to spec>
// Generated: <ISO-8601 UTC timestamp>
// Regenerate: print_widget scaffold --spec=<path> --class-name=<name> --output=<path>
//
// The scaffold uses literal values (no theme tokens, no custom components).
// After layout converges with `print_widget compare`, run `print_widget tokenize`
// to transform this file into the production widget with proper tokens.
```

The `Regenerate:` line always reflects the **actual flags used**, so re-running it produces the same bytes (modulo the timestamp). This means the scaffold is a good fit for a pre-commit check: regenerate, diff — if anything changed that isn't the timestamp, the spec changed underneath you.

## After generation — the two-pass flow

1. **Wire the scaffold into `printList`** (your `print_widget/config.dart`) so `generate` can capture it:
   ```dart
   widget('kpi_card_scaffold', const _KpiCardScaffold(), size: Size(320, 200)),
   ```
2. **Import `flutter_svg` in your consumer's `pubspec.yaml`** if the scaffold uses SVGs — the generator does NOT add it to the print_widget package pubspec.
3. **Generate + compare against the browser reference:**
   ```bash
   print_widget generate --name=kpi_card_scaffold
   print_widget compare --name=kpi_card_scaffold
   ```
   Expect the `cross_engine_threshold` (default 0.88) to pass. If not, the layout has a bug — tweak the scaffold by hand before tokenizing.
4. **Once layout is locked, snapshot:**
   ```bash
   print_widget snapshot --name=kpi_card_scaffold
   ```
   Future comparisons will be Flutter-to-Flutter.
5. **Run `print_widget tokenize`** (Phase 5, not yet landed) to produce the production widget with design-system tokens and convention-compliant widget extraction. The tokenize pass is invariant: every literal → token swap must produce zero pixel difference. Any delta indicates a broken token mapping.

## Regenerating fixtures / expected outputs

The test fixtures live under `test/codegen/fixtures/`. Each scenario has a pair:

- `<name>.spec.json` — the input spec
- `<name>.expected.dart` — the expected output minus the timestamp-bearing file header

When you change the generator and intentionally shift output shape:

1. Run the generator on each fixture via `dart run tool/scaffold_dev.dart test/codegen/fixtures/<name>.spec.json _<Name>Scaffold`.
2. Strip the 8-line file header (everything from `// AUTO-GENERATED` to the blank line before `import`).
3. `dart format` the remainder.
4. Paste into `<name>.expected.dart`.
5. Re-run `flutter test test/codegen/`.

The fixture-golden test comparison is strict — any whitespace or formatting drift will fail until you regenerate.

## Known limitations of v1

- **No border color/width handling yet.** `border: {width, color, style}` from the spec is ignored.
- **Gradients** are not translated. A `backgroundImage: linear-gradient(...)` emits nothing and leaves a gap.
- **`transform`, `opacity`, `zIndex`** are not translated yet. Phase 4.1 if needed.
- **Fixed `Stack` size** — when absolute children are present, the generator emits a bare `Stack` without `fit: StackFit.expand` or explicit size. If the parent doesn't size the stack, the layout may collapse; wrap in a `SizedBox` by hand.
- **SVG `height` and `width`** are pulled from the node's bounds, not from the SVG's own `width`/`height` attributes. This is usually what you want, but for sprite-style SVGs it may produce wrong aspect ratios.

File a TODO in the scaffold output: if a node produced `// TODO:`, the generator explicitly flagged it. Review those cases and either fix the spec or hand-edit the scaffold.
