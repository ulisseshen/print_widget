# Visual Review Checklist

Systematic, layer-by-layer verification of generated screenshots against the design.

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
