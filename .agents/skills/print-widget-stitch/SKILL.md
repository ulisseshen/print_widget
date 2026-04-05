---
name: print-widget-stitch
description: Generate UI with Stitch (Google AI) and verify with print_widget screenshots
---

# print_widget: Stitch Design Generation

Input: \$ARGUMENTS

## Workflow

1. Generate a design with Stitch MCP (`mcp__stitch__generate_screen_from_text`)
2. Retrieve the screen with `mcp__stitch__get_screen`
3. Save reference image: `mkdir -p print_widget/output/<name>/.reference && cp <exported_png> print_widget/output/<name>/.reference/<device>.png`
4. Analyze layout, colors (exact hex), typography, and spacing from the Stitch output
5. Build the Flutter widget matching the design
6. Add to `print_widget/config.dart`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
7. Run `print_widget generate --name=<name>`
8. Compare PNG at `print_widget/output/<name>/<device>.png` with the Stitch design. VS Code extension auto-detects `.reference/` for pixel comparison.
9. Ask user to confirm similarity. If not, use `mcp__stitch__edit_screens` to refine or fix the code, then regenerate until it matches.
