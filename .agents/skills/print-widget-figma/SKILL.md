---
name: print-widget
description: Convert Figma designs to Flutter widgets with print_widget screenshot comparison
---

# print_widget: Figma Design Conversion

Input: $ARGUMENTS

## Workflow

1. Get the Figma design (URL, screenshot, or description from arguments)
2. Save reference image for later comparison:
   - URL/file path: `mkdir -p print_widget/output/<name>/.reference && cp/curl <source> print_widget/output/<name>/.reference/<device>.png`
   - Image pasted: it includes the source file path — copy it directly.
   - Description only: skip.
3. Analyze layout, colors (exact hex), typography, and spacing
4. Build the Flutter widget matching the design
5. Add to `print_widget/config.dart`:
   - Full screen: `page('name', Widget())`
   - Component: `widget('name', Widget(), size: Size(w, h))`
   - Multiple states: `pages('name', states: [state('empty', Widget()), ...])`
6. Run `print_widget generate --name=<name>`
7. Compare PNG at `print_widget/output/<name>/<device>.png` with the original. VS Code extension auto-detects `.reference/` for pixel comparison.
8. Ask user to confirm similarity. If not, fix and regenerate until it matches.
