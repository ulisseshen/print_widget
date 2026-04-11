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
