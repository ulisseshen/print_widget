# Generate Screenshots and Compare with Design

Workflow for generating PNGs, viewing them, and iterating until they match the target design.

## Steps

### 1. Generate the screenshot

Run for a specific entry:

```bash
print_widget generate --name=<entry_name>
```

Or generate all entries:

```bash
print_widget generate
```

### 2. Find the PNG path

Read the manifest to locate the generated file:

```bash
cat print_widget/output/manifest.json
```

The manifest contains entries like:

```json
{
  "name": "login_page",
  "type": "page",
  "file": "print_widget/output/login_page/iphone_15_pro.png",
  "device": "iphone_15_pro",
  "width": 393.0,
  "height": 852.0,
  "widthPx": 1179,
  "heightPx": 2556
}
```

### 3. View the screenshot

Open or read the PNG file at the path from the manifest:

```
print_widget/output/<name>/<device>.png
```

### 4. Compare with the design

Compare the screenshot against the Figma design (or other reference). Check:

- **Colors** — background, text, accent colors match the design tokens
- **Spacing** — padding, margins, gaps between elements
- **Typography** — font size, weight, line height, letter spacing
- **Layout** — element positioning, alignment, proportions
- **Icons** — correct icon, size, and color
- **States** — the widget shows the correct state (empty, loaded, error, etc.)

### 5. If differences exist — iterate

1. Update the widget code to fix the differences
2. Re-generate:
   ```bash
   print_widget generate --name=<entry_name>
   ```
3. View the new screenshot
4. Compare again with the design
5. Repeat until the screenshot matches

### 6. Multi-device verification

Once the design matches on the default device, check other screen sizes:

```bash
print_widget generate --name=<entry_name> --all-devices
```

Or add `devices: DeviceFrame.popular` to the entry for iPhone, Pixel, and iPad coverage.

## Tips

- Use `--name=<entry_name>` to regenerate only the entry you're working on (faster iteration).
- If the widget depends on providers or state, make sure the `appWrapper` in `printSession` provides mock data.
- Network images require internet during generation. Use asset images or placeholders for offline development.
