# Visual Review Checklist

Systematic verification of generated screenshots against the reference. **Run this before trusting any `print_widget compare` score.** Pixelmatch is pixel-only and cannot detect truncated text, wrong glyphs, swapped icons, or font fallbacks — all of which leave the numeric score looking "close enough" while the visual is broken.

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

### How to run the code review

1. `git status` — list all files you created or modified in this session.
2. For each file, grep for the red-flag patterns:
   - `Color(0x` — raw color literal
   - `const Color _` — private color token
   - `SizedBox(width: `, `SizedBox(height: ` — inspect the literal against the spacing set
   - `BorderRadius.circular(` — inspect the literal against the radius set
   - `EdgeInsets.all(`, `EdgeInsets.symmetric(`, `EdgeInsets.only(` — inspect each literal
   - `TextStyle(fontFamily:` — should go through the project's font helper
   - `Widget _build` — `_buildXxx()` helper method (Check 3)
   - `Widget get ` — widget-returning getter (Check 3)
   - `final Widget ` — widget-typed field (Check 3)
3. Inspect each hit against the rules above. Fix every flagged item in place.
4. Re-run `print_widget generate --name=<entry>` + `print_widget compare --name=<entry>` for every entry whose source you touched. Token swaps are byte-identical, so **any score change means you introduced a bug** — revert and try again.
5. Commit the cleanup as a separate `refactor(...)` commit with a message explaining what was tokenized and why the scores are unchanged.

### Verdict

- **Pass**: every flagged item fixed, pixel scores unchanged, committed.
- **Skip**: you did not create or modify any widget files in this session (unusual — flag it in the final report).
- **Blocked**: a token doesn't exist in the design system for a value that is clearly a design token (not pixel geometry). Stop and ask whether to add a new token or keep the hardcoded value as-is.

This is the **last step** before the pipeline is complete. Do not commit Lovable / Figma / Stitch ports without this review. Pixel convergence alone is not enough.
