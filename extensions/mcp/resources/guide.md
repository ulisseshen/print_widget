# print_widget — Quick Reference

Screenshot Flutter widgets and pages as PNGs for visual verification.

## CLI Commands

```bash
print_widget init                        # Set up in your Flutter project
print_widget generate                    # Generate all screenshots
print_widget generate --name=login_page  # Generate one entry
print_widget generate --all-devices      # All popular devices
print_widget list                        # Show configured entries
print_widget config                      # View current settings
print_widget config --device=pixel_7     # Change default device
```

## Config Files

| File | Purpose |
|------|---------|
| `print_widget.yaml` | Project-level settings (paths, default device, manifest toggle) |
| `print_widget/config.dart` | Dart runtime config (`printSession` + `printList`) |

### print_widget.yaml keys

| Key | Default | Description |
|-----|---------|-------------|
| `config_file` | `print_widget/config.dart` | Path to Dart config file |
| `output_dir` | `print_widget/output` | PNG output directory |
| `default_device` | `iphone_15_pro` | Device used when none specified |
| `manifest` | `true` | Generate manifest.json |

## Adding Entries

Add entries to the `printList` in your config Dart file.

### Page (full screen)

```dart
page('login_page', const LoginPage()),
```

### Widget (centered, custom size)

```dart
widget('product_card', ProductCard(data: mock), size: Size(350, 400)),
```

### Multi-device

```dart
widget('card', MyCard(), devices: DeviceFrame.popular),
// popular = iphone_15_pro, pixel_7, ipad_pro_11
```

## Output

After generating, read `print_widget/output/manifest.json` to find PNGs:

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

View screenshot at: `print_widget/output/<name>/<device>.png`

## Devices

| Name | Size (dp) | Pixel Ratio |
|------|-----------|-------------|
| `iphone_se` | 375x667 | 2.0 |
| `iphone_14` | 390x844 | 3.0 |
| `iphone_15_pro` | 393x852 | 3.0 |
| `iphone_16_pro_max` | 440x956 | 3.0 |
| `ipad_mini` | 744x1133 | 2.0 |
| `ipad_air` | 820x1180 | 2.0 |
| `ipad_pro_11` | 834x1194 | 2.0 |
| `ipad_pro_13` | 1024x1366 | 2.0 |
| `pixel_7` | 412x915 | 2.625 |
| `pixel_8_pro` | 448x998 | 3.0 |
| `samsung_s24` | 360x780 | 3.0 |
| `samsung_s24_ultra` | 412x915 | 3.0 |
| `small` | 320x480 | 1.0 |
| `medium` | 400x800 | 1.0 |
| `large` | 600x1000 | 1.0 |
| `compact` | 300x300 | 1.0 |

### Preset Groups

| Group | Devices |
|-------|---------|
| `DeviceFrame.popular` | iphone_15_pro, pixel_7, ipad_pro_11 |
| `DeviceFrame.allPhones` | iphone_se, iphone_14, iphone_15_pro, iphone_16_pro_max, pixel_7, pixel_8_pro, samsung_s24, samsung_s24_ultra |
| `DeviceFrame.allTablets` | ipad_mini, ipad_air, ipad_pro_11, ipad_pro_13 |

## Known Limitations

- **Images are auto-precached.** Asset and file images render correctly. Network images require internet access during `generate`.
- **No animations.** Screenshots capture the settled state after `pumpAndSettle()`.
- **No platform channels.** Plugins depending on native code won't work — use mocks.
- **Single frame.** Each entry produces one PNG per device (no multi-state captures).
