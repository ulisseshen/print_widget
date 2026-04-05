# Visual Iteration Loop

1. Generate: `print_widget generate --name=<entry>`
2. Read PNGs from `print_widget/output/manifest.json`
3. Review: layout, colors, spacing, typography
4. Ask user what needs fixing
5. Fix code, regenerate with `--delete-old`
6. Confirm with user. Repeat until satisfied.

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets
- **Mock as little as possible**: Use real data, theme, components
- **Preserve behavior**: Keep callbacks, state management, navigation intact
