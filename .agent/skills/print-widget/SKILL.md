---
name: print-widget
description: Capture Flutter widgets as screenshots — figma conversion, stitch generation, or self-update
---

# print_widget

Input: $ARGUMENTS

Route by first word: `figma`, `stitch`, or `update`.

## figma workflow

1. Get the Figma design (URL, screenshot, or description)
2. Save reference image (MANDATORY):
   - URL/file path: `mkdir -p print_widget/output/<name>/.reference && cp/curl <source> print_widget/output/<name>/.reference/<device>.png`
   - Image pasted: copy from source path. Description only: skip.
3. Extract ALL colors and padding. Map to DS tokens — never hardcoded `Color()`. Copy exact chars.
4. List ALL sections. Verify each will be implemented. If 5+ independent sibling components (row of cards, grid of tiles), stop and read `parallel.md` — dispatch one agent per slot instead of building serially.
5. Build widget using DS tokens. Positive values → green, negative → red. Wrap every widget root in `Material(type: MaterialType.transparency)` to avoid yellow underlines under text.
6. Add to `print_widget/config.dart`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
7. Run `print_widget generate --name=<name>`
8. Read generated PNG at `print_widget/output/<name>/<device>.png`. Compare layer-by-layer: backgrounds → text colors → padding → borders → icons → typography → layout.
9. List ALL differences, fix them, regenerate, repeat until match (max 5). Show user final result.
10. Save novel patterns to CLAUDE.md for future sessions.

## stitch workflow

1. Generate design with Stitch MCP (`mcp__stitch__generate_screen_from_text`)
2. Save reference image: `mkdir -p print_widget/output/<name>/.reference && cp <png> print_widget/output/<name>/.reference/<device>.png`
3. Analyze layout, colors, typography, spacing from Stitch output. If 5+ independent sibling components, read `parallel.md` and dispatch an agent team.
4. Build widget using DS tokens. Same validation loop as figma. Wrap every widget root in `Material(type: MaterialType.transparency)` to avoid yellow underlines.
5. Add to `print_widget/config.dart` (same format as figma).
6. Generate, compare, iterate (max 5). Show final result.

Stitch MCP tools: `generate_screen_from_text`, `edit_screens`, `generate_variants`, `apply_design_system`, `get_screen`.

## update workflow

1. Update CLI: `dart pub global activate print_widget_flutter`
2. Update skills: `print_widget skills --update`
3. Verify: `print_widget generate`
