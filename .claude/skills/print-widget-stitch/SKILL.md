---
name: print-widget-stitch
description: Generate a UI screen with Stitch (Google AI) and verify with print_widget screenshots
argument-hint: <screen-description> [instructions]
---

Generate a UI screen with Stitch (Google AI), implement it in Flutter, and verify with print_widget screenshots.

## Input

$ARGUMENTS

The user provides a screen description or requirements, optionally followed by additional instructions.

## Steps

1. **Generate design with Stitch**: Use the Stitch MCP to generate a design screen from the description.
   - Call `mcp__stitch__generate_screen_from_text` with the user's description to create a design.
   - If the user wants variants, call `mcp__stitch__generate_variants`.
   - If a design system should be applied, use `mcp__stitch__create_design_system` or `mcp__stitch__apply_design_system`.

2. **Save reference image** (for later visual comparison in VS Code):
   - Call `mcp__stitch__get_screen` to retrieve the generated screen.
   - Export the Stitch screen as PNG and save it:
     ```bash
     mkdir -p print_widget/output/<name>/.reference
     # Save the exported PNG from Stitch
     cp "<exported_png_path>" print_widget/output/<name>/.reference/<device>.png
     ```
   - If export is not available, skip this step.

3. **Analyze the design**: Identify layout structure, colors (exact hex), typography, spacing, and components from the Stitch output.

4. **Build the Flutter widget**: Match the Stitch design using the project's theme and design system. Prefer `const` constructors. Follow any additional instructions provided.

5. **Add to print_widget config** at `print_widget/config.dart`:
   - Full screen → `page('screen_name', const ScreenWidget())`
   - Component → `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states → `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

6. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

7. **Compare**: Read the generated PNG at `print_widget/output/<name>/<device>.png` and compare with the Stitch design. If a reference image was saved to `.reference/`, the VS Code Print Widget extension will auto-detect it for side-by-side pixel comparison with similarity percentage. Ask the user to confirm similarity.

8. **Iterate**: If the user says it doesn't match, use `mcp__stitch__edit_screens` to refine the Stitch design or fix the Flutter code, then regenerate. Repeat until the user confirms it matches.

## Stitch MCP tools reference

- `mcp__stitch__generate_screen_from_text` — Generate a screen from a text description
- `mcp__stitch__edit_screens` — Edit existing screens
- `mcp__stitch__generate_variants` — Generate design variants
- `mcp__stitch__create_design_system` / `apply_design_system` — Design system management
- `mcp__stitch__get_screen` / `list_screens` — Read screens
- `mcp__stitch__create_project` / `get_project` / `list_projects` — Project management

## Working with existing widgets

If the target widget already exists in the codebase:
- **Extract, don't rewrite**: Refactor the existing widget to match the design. Extract sub-widgets into private `StatelessWidget` classes.
- **Mock as little as possible**: Use real data models, real theme, real components. Only mock external dependencies (network, platform channels).
- **Preserve behavior**: Keep existing callbacks, state management connections, and navigation intact. Only change the visual layer.

## Internal references

Read these files for detailed guidelines. They are bundled alongside this skill:
- `conventions.md` — Widget structure rules (composition over nesting, extraction, const constructors)
- `screen.md` — Screen patterns (callbacks, screen-provider separation, mock data for print_widget)
- `review.md` — Visual review checklist for auditing screenshots
- `iterate.md` — Visual iteration loop for refining the UI

## Tips

- Match exact hex colors from the Stitch design
- For responsive designs, generate with `--all-devices` to test multiple screen sizes
- If the design has multiple states (empty, loading, error, filled), use `pages()` with `state()` to capture all of them
- Read `print_widget/output/manifest.json` to find all generated PNG paths
- Use `mcp__stitch__generate_variants` to explore alternative designs before committing to one
