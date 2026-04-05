---
name: print-widget
description: Convert a Figma design into a Flutter widget with screenshot comparison loop
argument-hint: <figma-url-or-screenshot> [instructions]
---

Convert a Figma design into a Flutter widget and verify with print_widget screenshots.

## Input

$ARGUMENTS

The user provides a Figma URL, screenshot path, or design description, optionally followed by instructions.

## Steps

1. **Get the design**: If a Figma URL was given, use the Figma MCP to fetch the frame. If a screenshot path, read the image. If a description, work from that.

2. **Save reference image** (for later visual comparison in VS Code):
   - **Figma URL**: After fetching the frame via MCP, download the exported PNG using Bash:
     ```bash
     mkdir -p print_widget/output/<name>/.reference
     curl -sL "<export_url>" -o print_widget/output/<name>/.reference/<device>.png
     ```
   - **File path provided**: Copy the image using Bash:
     ```bash
     mkdir -p print_widget/output/<name>/.reference
     cp "<provided_path>" print_widget/output/<name>/.reference/<device>.png
     ```
   - **Image pasted in chat**: The pasted image includes its source file path. Copy it using Bash:
     ```bash
     mkdir -p print_widget/output/<name>/.reference
     cp "<source_path_from_pasted_image>" print_widget/output/<name>/.reference/<device>.png
     ```
   - **Description only**: No reference image to save, skip this step.

3. **Analyze the design**: Identify layout structure, colors (exact hex), typography, spacing, and components.

4. **Build the Flutter widget**: Match the design using the project's theme and design system. Prefer `const` constructors. Follow any additional instructions provided.

5. **Add to print_widget config** at `print_widget/config.dart`:
   - Full screen → `page('screen_name', const ScreenWidget())`
   - Component → `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states → `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

6. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

7. **Compare**: Read the generated PNG at `print_widget/output/<name>/<device>.png` and compare with the original design. If a reference image was saved to `.reference/`, the VS Code Print Widget extension will auto-detect it for side-by-side pixel comparison with similarity percentage. Ask the user to confirm similarity.

8. **Iterate**: If the user says it doesn't match, fix differences and regenerate. Repeat until the user confirms it matches.

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

- Match exact hex colors from the design
- For responsive designs, generate with `--all-devices` to test multiple screen sizes
- If the design has multiple states (empty, loading, error, filled), use `pages()` with `state()` to capture all of them
- Read `print_widget/output/manifest.json` to find all generated PNG paths
