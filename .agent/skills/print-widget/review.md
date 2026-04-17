# Visual Review Checklist

Systematic verification of generated screenshots against the reference. **Run this before trusting any `print_widget compare` score.** Pixelmatch is pixel-only and cannot detect truncated text, wrong glyphs, swapped icons, or font fallbacks — all of which leave the numeric score looking "close enough" while the visual is broken.

## Pre-flight: verify the reference is clean

Before running the audit, sanity-check that you're comparing against a valid reference:

1. **No platform chrome** — no Lovable footer, no PWA install banners, no cookie popups, no browser scrollbars captured inside the crop. If present, re-run extract with `--chrome-purge="footer:last-child"` (or the appropriate selector).
2. **Correct font actually loaded** — the reference must render the declared font. Lovable and similar SPAs often declare `font-family: Inter` but never import the font file, so the browser silently falls back to Helvetica/DejaVu. If reference glyphs look subtly wrong (`R`, `a`, `g` in particular), re-run extract with `--force-font="Inter:wght@300;400;500;600;700"`.
3. **Correct viewport** — reference device dimensions match the Flutter `DeviceFrame`. A 1440px-wide capture compared against a 390px iPhone frame will never converge.
4. **No animations in progress** — reference was captured after `settleMs` elapsed. Skeleton loaders, shimmer effects, and fade-ins captured mid-animation produce unstable scores across runs.
5. **Reference origin is known** — check `<.reference>/_origin.json`. If it's `browser`, expect the cross-engine threshold (~0.88) as the convergence gate. If missing, compare treats the reference as browser-originated by default (conservative).

If any of these fail, fix the reference before writing code. Iterating against a bad reference burns iterations.

## The meta-rule (read this first, every time)

**A high pixelmatch score does not imply element coverage.** A card at 94%+ can be missing a circular background behind an icon, a subtitle, a badge, or an entire decorative container — the absent element is small relative to the frame, it falls inside pixelmatch's tolerance, and the score stays high while the visual is objectively incomplete.

The failure mode looks like this: you ship an iteration, score is 94%, user points at a missing element, you fix it, score goes to 94.84% (or stays the same), user points at the next missing element, repeat. That loop is evidence you are not running this checklist — you are reacting to feedback. **Stop, run the outside-in audit below against the reference, enumerate every element, then commit.**

Rules that follow from this:

1. **Never use the score as a substitute for the checklist.** A 99% score with an unchecked element list is worse than an 80% score with a complete list — the first is deceptive, the second is honest.
2. **Never iterate reactively on user-pointed visual misses.** If the user has to point at a missing element, you already failed this gate. Run the checklist yourself BEFORE they see the result.
3. **Enumerate, never summarize.** "All backgrounds match" without a per-element list is a lie you tell yourself under time pressure. Say "shell bg ✓, card bg ✓, pill container bg ✓, icon badge bg ✓" — every element, explicitly.
4. **The `_compare.png` stitched image is too small for subtle details.** A 32px circular badge behind a 16px icon is invisible at 638×448 side-by-side zoom. Read the reference PNG at full resolution when auditing backgrounds, borders, shadows, and small decorative elements.

## The 5-point visual audit (gate before trusting score)

Open the three PNGs side by side: `<entry>/<device>.ref.png`, `<entry>/<device>.png`, `<entry>/<device>.diff.png`. For each of the five checks, the answer must be an unqualified YES before the score matters.

1. **Text complete.** Every string present, every word present, no `...` where the reference has full text, no missing trailing characters (a clipped `%` or `.` at the edge of a pill passes pixelmatch at >95% while being visibly wrong).
2. **Font matches.** Glyph shapes are identical — inspect `R`, `$`, `%`, `a`, `o`, `g` which are the best tells for font fallback. A Helvetica Neue rendering next to a real Inter rendering is visible at a glance.
3. **Layout intact.** No Flutter overflow markers (yellow/black stripes), no misaligned columns, padding and gaps visually consistent, rounded corners where the reference has them.
4. **Colors match.** Primaries, muted, positive/negative deltas visually indistinguishable. Accept only when values average the same, not when they "look about right".
5. **Icons correct.** Same family, same pose, same fill vs stroke style. Material Symbols substituted for Lucide is almost never a visual match — use `flutter_svg` with the Lucide SVG string inline.

If any of the five fails, the entry is **not converged** even if the compare score is 99%. Fix the failing dimension and re-run. Do not mark the entry done with a failing visual audit on the excuse that "the score passes".

## Verification order (outside-in)

Work through each section in order. Never declare "all colors match" without enumerating EVERY colored element.

### 1. Backgrounds (layer by layer)
- [ ] Shell / page background
- [ ] Sidebar background
- [ ] Content area background
- [ ] Card backgrounds (each card independently)
- [ ] Nested container backgrounds (modals, dropdowns, tooltips)
- [ ] **Icon badge backgrounds** — circular or rounded fills behind individual icons (leading title icons, sort toggles, action icons, status chips). These are the #1 element pixelmatch hides. Walk every icon in the reference and ask "does it sit on a colored fill?" If yes, wrap it in a Container with the matching background.
- [ ] **Pill / chip container backgrounds** — the distinction between "single grouped container around a pill row" vs "individual background on each pill" is visually important and pixelmatch often tolerates it. Enumerate which mode the reference uses.

### 2. Text colors
- [ ] Titles / headings
- [ ] Body text / descriptions
- [ ] Values / metrics (numeric displays)
- [ ] Comparison values (red = negative, green = positive)
- [ ] Links / interactive text
- [ ] Placeholder / hint text
- [ ] Disabled text

### 3. Spacing & padding
- [ ] Shell to sidebar padding
- [ ] Shell to content area padding
- [ ] Internal card padding (top, right, bottom, left)
- [ ] Gaps between cards
- [ ] Gaps between text elements
- [ ] Section spacing

### 4. Borders & dividers
- [ ] Border colors (must use DS tokens, not hardcoded)
- [ ] Border radius values
- [ ] Divider lines (color, thickness)
- [ ] Card elevation / shadows

### 5. Icons
- [ ] Icons render correctly (no squares / missing glyphs)
- [ ] Icon sizes match design
- [ ] Icon colors match design
- [ ] SVG vs MaterialIcon stroke weight consistency

### 6. Typography
- [ ] Font families loaded correctly
- [ ] Font weights (bold, semibold, regular, light)
- [ ] Font sizes match design
- [ ] Line heights / letter spacing
- [ ] Text truncation / overflow behavior

### 7. Layout & alignment
- [ ] Horizontal alignment (start, center, end)
- [ ] Vertical alignment within rows
- [ ] Cards in same Row have equal height (IntrinsicHeight)
- [ ] Responsive behavior across breakpoints
- [ ] Safe areas respected
- [ ] No overflow warnings

## Rules

- **Layer-by-layer**: Verify backgrounds outside-in (Shell > Sidebar > Content > Cards)
- **Enumerate everything**: List every colored element explicitly — do not summarize
- **Track progress**: Mark which sections are verified vs still unchecked
- **Never skip**: Every checkbox must be explicitly passed or flagged as "not applicable"

## Verdict per entry

- **Pass**: All applicable checkboxes verified, no issues
- **Warnings**: Minor issues (tight spacing, slight color mismatch)
- **Needs fix**: Layout broken, text cut off, wrong colors, missing elements

---

## Post-convergence code review (token discipline + composition)

**Run this AFTER the pixel gate passes. This is the last step of the pipeline — before committing.**

Pixel parity does not imply code health. A widget can match the reference byte-identically while leaking hardcoded values across the codebase, nesting builders, or skipping the project's token system. The code review catches all three.

**Scope**: every file you created or modified in this session. Do not scan the whole repo — the review is bounded by your changes (`git status`).

### Check 1 — Token discipline

Flag and fix:

- **Raw `Color(0x...)` literals** — must come from the project's design-system tokens (`context.customColors.*`, `context.customColorsV2.*`, or equivalent). Exceptions: `Colors.transparent`, `Colors.white`, `Colors.black` are framework constants and acceptable when the reference needs pure white/black.
- **Private `_k*` / `_fg` / `_muted` / `_bg` / similar `const Color` declarations** at the top of a widget file or inside a class — these are the symptom of "tokenize later". Delete them and source the values from the design-system getter at every call site.
- **Raw spacing numbers** in `SizedBox(width: N)`, `SizedBox(height: N)`, `EdgeInsets.all(N)`, `EdgeInsets.symmetric(...)`, `EdgeInsets.only(...)`, or `Padding(padding: EdgeInsets...)` — if N matches a token in the project's spacing scale, use the token. **Pixel dimensions** (widget widths/heights like 40, 48, 72, 638, 1288) are geometric layout, not design spacing, and stay as raw numbers.
- **Raw `BorderRadius.circular(N)`** — if N matches a token in the project's radius scale (typical set: 4, 6, 8, 12, 16, 20, 24, 9999), use the token (e.g. `YHAppCornerRadiusV2.rN` / `rPill`).
- **Raw `TextStyle(fontFamily: '<Font>', ...)` constructors** — must go through the project's font helper (e.g. `interText(...)` / `interTextV2(...)`) so variable-font axes (`opsz`, `wght`, `kern`) stay pinned. A raw TextStyle renders slightly differently from the helper-built one and the delta is visible in the pixel diff.

**When the project has a v2 token layer** (e.g. `context.customColorsV2.*`, `YHAppSpacingV2.*`, `YHAppCornerRadiusV2.*`): prefer v2 for Lovable/Figma-ported widgets so the provisional design-aligned palette stays explicit. Do NOT silently mix v1 and v2 in the same file.

### Check 2 — Composition over nesting

Flag and fix:

- **Nesting depth > 3 levels** in a single `build()` method (Container > Row > Column > Row > Container > Text) without a private `StatelessWidget` extraction. Extract the inner chunk to its own widget class to flatten the tree.
- **Repeated visual patterns** inline in a `build()` method (e.g. the same Container+Row+Text block copy-pasted for three cards) — extract once as a parameterized private `StatelessWidget` and reuse it.

The project convention is: flat widget trees with extracted children, never deep nesting. Max three levels of composition before a section becomes its own class.

### Check 3 — `StatelessWidget` over `Widget buildSomething()` helper methods

This is the single most important code-review rule on Flutter ports. Flag and fix:

- **`Widget _buildXxx()` instance methods** that return a widget tree — extract each one to a private `class _WidgetName extends StatelessWidget` with its own `build(BuildContext context)`. The project convention is **zero** `_buildXxx()` methods: every named visual chunk is a real widget class.
- **Widget-returning getters** (`Widget get xxx => Container(...)`) — same fix, extract to a `StatelessWidget`.
- **Widget-typed fields** (`final Widget xxx = ...`) that hold deferred widget trees — same fix.
- **Local functions inside `build()`** that return widget chunks (`Widget header() => Row(...)` before `return Column(children: [header(), ...])`) — same fix.

Why this matters: a `_buildXxx()` helper method looks like encapsulation but isn't. It shares the outer widget's lifecycle, can't be `const`, doesn't get its own element in the widget tree, can't be rebuilt independently, and makes the outer `build()` longer and harder to scan. A private `StatelessWidget` class fixes all of those for free.

**Allowed helpers (not flagged)**: tiny primitive builders that take parameters and return a single leaf widget — for example `Widget _lucide(String svg, {required double size, required Color color})` that returns one `SvgPicture.string` or `Text _t(String data, {required double fontSize, ...})` that returns one `Text`. These are **primitive factories**, not `_buildXxx()` compositions. The test: a helper is allowed if its body returns one widget with no children or a single leaf child; anything that builds a tree must be a class.

### Check 4 — Component reuse (did you hand-roll something the project already has?)

Component discovery is supposed to happen at the **start** of the pipeline (see `conventions.md` → "Design system component discovery"). This check verifies it actually did. A shippable widget never reinvents a primitive the project already provides.

Flag and fix:

- **Hand-rolled table structures** — a file containing three or more private widgets with names like `_Table`, `_TableHeader*`, `_TableHeaderRow`, `_TableBodyRow`, `_HeaderCell`, `_BodyCell`, `_Row`, `_Cell`, `_Column` is almost always a reinvented table. Check for existing equivalents (`YHAdaptiveTable`, `YHSimpleTable`, `YHDataGrid`, `CardOrdersTable`, and any project-specific `*Table` / `*Grid` / `*List` class).
- **Hand-rolled pagination strips** — private `_Pagination`, `_PageLinks`, `_PageNumbers` — check for DS equivalents.
- **Hand-rolled filter-pill rows** — private `_FilterPills`, `_Pill`, `_TabPills` — check for existing feature-level equivalents (`YHSimpleGroupFilters`, etc.).
- **Hand-rolled list / card-list combos** for data the project renders elsewhere (orders list, clients list, pedidos list) — check the existing feature that shows the same data. The answer is usually a shared component or a feature-specific component that has become the app's pattern.

### How to run Check 4

1. Open every source file you created in this session.
2. Count the number of private widgets in each file whose name matches the patterns `_*Table*`, `_*Grid*`, `_*List*`, `_*Row*`, `_*Cell*`, `_*Column*`, `_*Header*`, `_*Body*`, `_*Pagination*`, `_*Filter*Pill*`. If the count is ≥3 in one file, it is almost certainly a reinvented primitive.
3. Run the Tier B grep from `conventions.md`:

   ```bash
   Grep: "class \w*Table\b|class \w*Grid\b|class \w*List\b"
   ```

   Search both `packages/*_design_system/` and `lib/ui/features/`. If a match exists and the reference shows the same kind of content, that component was the correct choice — not the hand-rolled one.

4. If you find an existing component that fits: invoke `AskUserQuestion` with the four-option frame from `conventions.md` (use as-is / improve in place / create V2 / keep hand-rolled). Let the user decide. **Do not silently refactor** to the shared component — the user may have reasons the hand-rolled version is correct (locked card dimensions, different interaction model).
5. If the user picks reuse / improve / V2, refactor the widget, regenerate + re-compare, confirm the pixel score is within tolerance (a reuse refactor is allowed to move the score because the visual primitive changes; a token refactor is not), and commit as `refactor(<feature>): adopt <Component>`.

**When to skip Check 4**: the widget you built is a pure primitive (single icon, single badge, one label) with no repeated structure. If there are no `_Table` / `_Row` / `_Cell` / `_List` patterns in the file, there's nothing to reuse and Check 4 is a no-op.

### How to run the code review

1. `git status` — list all files you created or modified in this session.
2. For each file, grep for the red-flag patterns:
   - `Color(0x` — raw color literal (Check 1)
   - `const Color _` — private color token (Check 1)
   - `SizedBox(width: `, `SizedBox(height: ` — inspect the literal against the spacing set (Check 1)
   - `BorderRadius.circular(` — inspect the literal against the radius set (Check 1)
   - `EdgeInsets.all(`, `EdgeInsets.symmetric(`, `EdgeInsets.only(` — inspect each literal (Check 1)
   - `TextStyle(fontFamily:` — should go through the project's font helper (Check 1)
   - `Widget _build` — `_buildXxx()` helper method (Check 3)
   - `Widget get ` — widget-returning getter (Check 3)
   - `final Widget ` — widget-typed field (Check 3)
   - `class _\w*(Table|Grid|List|Row|Cell|Column|Header|Body|Pagination|FilterPill)` — potential reinvented primitive (Check 4)
3. Inspect each hit against the rules above. Fix every flagged item in place.
4. Re-run `print_widget generate --name=<entry>` + `print_widget compare --name=<entry>` for every entry whose source you touched. Token swaps are byte-identical, so **any score change means you introduced a bug** — revert and try again.
5. Commit the cleanup as a separate `refactor(...)` commit with a message explaining what was tokenized and why the scores are unchanged.

### Verdict

- **Pass**: every flagged item fixed, pixel scores unchanged, committed.
- **Skip**: you did not create or modify any widget files in this session (unusual — flag it in the final report).
- **Blocked**: a token doesn't exist in the design system for a value that is clearly a design token (not pixel geometry). Stop and ask whether to add a new token or keep the hardcoded value as-is.

This is the **last step** before the pipeline is complete. Do not commit Lovable / Figma / Stitch ports without this review. Pixel convergence alone is not enough.

## Post-tokenize invariant (when using `print_widget tokenize`)

If the feature was built via the scaffold → tokenize pipeline (see `conventions.md` → Scaffold-first development), a mechanical invariant applies: **tokenizing cannot change the pixel score.** A token swap replaces `Color(0xFF0BA284)` with `context.customColors.brand30`, but both resolve to the same `Color(0xFF0BA284)` at runtime. Same for spacing, radius, typography helpers.

Procedure:

1. Before running tokenize: capture per-region scores via `print_widget compare --name=<entry> --json`
2. Run tokenize.
3. Run `print_widget generate --name=<entry>` + `print_widget compare --name=<entry>`
4. Diff the new per-region scores against the pre-tokenize snapshot. Any delta > 0.1% means the tokenizer introduced a visual change — that's a bug in the theme-ref mapping (wrong token name, wrong scale value) or in the tokenizer itself (regex false positive).
5. If scores differ: revert the tokenized file, inspect the FORCE comments in the tokenize output to find the bad mapping, fix the theme-ref.json or the scaffold, re-run.

The invariant is also the stop condition for Pass B in two-pass iteration (see `iterate.md` → Pass-Aware Iteration). If you can't reach zero delta after tokenize, don't ship — something upstream is lying about the value.
