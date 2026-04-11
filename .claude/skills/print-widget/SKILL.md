---
name: print-widget
description: Capture Flutter widgets as screenshots — convert Figma designs, generate with Stitch, or self-update
argument-hint: <figma|stitch|update> [url-or-description] [instructions]
---

Capture Flutter widgets as PNG screenshots for visual verification. Route by first argument:

- `figma <url-or-screenshot> [instructions]` — Convert a Figma design into a Flutter widget
- `stitch <description> [instructions]` — Generate a UI with Stitch (Google AI), implement and verify
- `update` — Update print_widget CLI and skill files to latest version

Parse the first word of $ARGUMENTS to determine which workflow to run.

---

# figma workflow

Convert a Figma design into a Flutter widget and verify with print_widget screenshots.

## Input

$ARGUMENTS

The user provides a Figma URL, screenshot path, or design description, optionally followed by instructions.

## Steps

1. **Get the design**: If a Figma URL was given, use the Figma MCP to fetch the frame. If a screenshot path, read the image. If a description, work from that.
   - **Large design context warning**: Figma MCP responses can exceed 100K characters for complex frames. If the response is very large, fetch individual sub-nodes instead of the entire frame.

2. **Save reference image** (MANDATORY — not optional):
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

3. **Extract color mapping** (do this BEFORE writing any code):
   - From the Figma design context, extract ALL `bg-[...]` and `text-[color:...]` values
   - Create a color mapping table: each Figma token → project DS token
   - Example:
     ```
     Figma bg-[#1E1E2E]  → AppColors.surfacePrimary
     Figma text-[#A0A0B0] → AppColors.textSecondary
     Figma bg-[#2A2A3E]  → AppColors.cardBackground
     ```
   - If no DS token exists for a Figma color, flag it to the user — NEVER use hardcoded `Color()` values

4. **Extract padding & spacing**:
   - Search for `gap-[]`, `p-[]`, `px-[]`, `py-[]` in the design context
   - Map each to Flutter `EdgeInsets` values
   - Check shell padding, content padding, and card padding separately

5. **Completeness check**: List ALL sections/components visible in the Figma design. Check each one exists in your planned implementation. Flag any missing sections BEFORE writing code.
   - **5+ independent siblings → parallel agent team**: If the design contains 5 or more independent sibling components (row of KPI cards, grid of tiles, list of chips), stop and read `parallel.md`. Dispatch one agent per slot with the artifact-producing contract instead of building serially. This applies to every provider — figma, stitch, lovable, or a hand-written spec.

6. **Build the Flutter widget**:
   - Use the color mapping from step 3 — DS tokens only, never hardcoded `Color()`
   - **Exact character matching**: Copy exact characters from Figma (breadcrumb separators like ›, currency symbols like $, em dashes, etc.). Do not retype or approximate.
   - **Positive/negative value coloring**: Values with "-" prefix → red (negative/loss color). Values with "+" prefix → green (positive/gain color). This is a universal financial UI pattern.
   - **SVG icon consistency**: MaterialIcons have thick strokes. If mixing with SVG icons, use `stroke-width: 1.2–1.5` on SVGs for visual consistency.
   - Prefer `const` constructors. Follow any additional instructions provided.

7. **Add to print_widget config** at `print_widget/config.dart`:
   - Full screen → `page('screen_name', const ScreenWidget())`
   - Component → `widget('component_name', ComponentWidget(), size: Size(width, height))`
   - Multiple states → `pages('screen_name', states: [state('empty', Widget()), state('filled', Widget())])`

8. **Generate screenshot**:
   ```bash
   print_widget generate --name=<entry_name>
   ```

9. **Visual validation loop** (autonomous — do NOT ask the user). Follow `iterate.md`:
   a. Read the generated PNG at `print_widget/output/<name>/<device>.png`
   b. **Tier 1 (structural):** Compare against the Figma reference using the review.md checklist (backgrounds, text colors, padding, borders, icons, typography, layout)
   c. **Tier 2 (perceptual):** Run `print_widget compare --name=<entry_name>` — this invokes pixelmatch against `print_widget/output/<name>/.reference/` and prints per-region scores. Exit 0 = converged, exit 1 = regions below threshold (default 0.95), heatmaps at `print_widget/output/<name>/crops/*_diff.png`
   d. List ALL remaining differences from both tiers — never stop at the first one
   e. **Back up files** before editing: `cp <file> /tmp/pw_iter_<N>_backup.dart`
   f. Fix ALL differences in one batch, then regenerate: `print_widget generate --name=<entry_name>`
   g. Re-run compare. **Revert on regression:** if any region's score dropped vs the previous iteration, restore from backup and try a different approach
   h. Repeat until BOTH tiers pass OR the 15-iteration hard cap is reached
   i. On cap: produce the escalation report from `iterate.md` — never silently accept mismatches
   j. After convergence: show the user the final screenshot with a verification report

10. **Save novel patterns**: If you discovered a new workaround or pattern during this task, save it to the project’s CLAUDE.md for future sessions.

## Working with existing widgets

If the target widget already exists in the codebase:
- **Extract, don't rewrite**: Refactor the existing widget to match the design. Extract sub-widgets into private `StatelessWidget` classes.
- **Mock as little as possible**: Use real data models, real theme, real components. Only mock external dependencies (network, platform channels).
- **Preserve behavior**: Keep existing callbacks, state management connections, and navigation intact. Only change the visual layer.

## Internal references

Read these files for detailed guidelines. They are bundled alongside this skill:
- `conventions.md` — Widget structure rules (composition, extraction, DS discovery, behavioral rules)
- `screen.md` — Screen patterns (callbacks, providers, mock data, toggle states)
- `review.md` — Visual review checklist (layer-by-layer verification)
- `iterate.md` — Autonomous visual iteration loop (3-tier stop conditions, revert-on-regression, escalation)
- `compare.md` — How to use `print_widget compare` and read pixelmatch heatmaps
- `viewport.md` — Phase 0 viewport contract (critical for web references)
- `parallel.md` — Parallel agent teams for building 5+ sibling components at once (works for figma, stitch, lovable, or any provider)
- `lovable.md` — Adapter for Lovable.dev URLs (uses smart-extract + compare; adds Lovable-specific bits on top of `parallel.md`)

## Tips

- Match exact hex colors from the design — always via DS tokens
- For responsive designs, generate with `--all-devices` to test multiple screen sizes
- If the design has multiple states (empty, loading, error, filled), use `pages()` with `state()` to capture all of them
- Read `print_widget/output/manifest.json` to find all generated PNG paths

---

# stitch workflow

Generate a UI screen with Stitch (Google AI), implement it in Flutter, and verify with print_widget screenshots.

## Steps

1. **Generate design with Stitch**: Use `mcp__stitch__generate_screen_from_text` with the description.
   - Optionally use `mcp__stitch__generate_variants` for alternatives.
   - Apply design system with `mcp__stitch__apply_design_system` if available.

2. **Save reference image**: Export the Stitch screen as PNG:
   ```bash
   mkdir -p print_widget/output/<name>/.reference
   cp "<exported_png_path>" print_widget/output/<name>/.reference/<device>.png
   ```

3. **Analyze the design**: Extract layout, colors, typography, spacing from the Stitch output.
   - **5+ independent siblings → parallel agent team**: If the Stitch output contains 5 or more independent sibling components, stop and read `parallel.md`. Dispatch one agent per slot instead of building serially.

4. **Build the Flutter widget**: Match the Stitch design using DS tokens. Follow all conventions from the figma workflow (color mapping, exact chars, etc.).

5. **Add to print_widget config** at `print_widget/config.dart` (same as figma workflow).

6. **Generate and validate**: Same visual validation loop as figma (generate, read PNG, verify with review.md checklist, fix, repeat).

## Stitch MCP tools

- `mcp__stitch__generate_screen_from_text` — Generate screen from text
- `mcp__stitch__edit_screens` — Edit existing screens
- `mcp__stitch__generate_variants` — Generate design variants
- `mcp__stitch__create_design_system` / `apply_design_system` — DS management
- `mcp__stitch__get_screen` / `list_screens` — Read screens

---

# update workflow

Update print_widget to the latest version.

## Steps

1. **Update the CLI**: `dart pub global activate print_widget_flutter`
2. **Verify version**: `print_widget --version`
3. **Update installed skills**: `print_widget skills --update`
4. **Verify**: `print_widget generate`
