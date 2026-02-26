# print_widget

Screenshot Flutter widgets/pages as PNGs. Config: `print_widget/config.dart`. Output: `print_widget/output/`.

## Generate screenshots

```bash
print_widget generate                    # all entries
print_widget generate --name=login_page  # one entry
print_widget generate --all-devices      # all popular devices
print_widget list                        # show entries
print_widget config --device=pixel_7     # change default device
print_widget skills                      # install AI assistant skills
print_widget skills --list               # list available skills
```

## Add a page (full screen)

In `print_widget/config.dart`, add to `printList`:
```dart
page('login_page', const LoginPage()),
```

## Add a widget (centered, custom size)

```dart
widget('product_card', ProductCard(data: mock), size: Size(350, 400)),
```

## Grouped states (multiple visual states of the same page/widget)

Use `pages()` / `widgets()` with `state()` to group visual states under one folder:
```dart
pages('sign_in_screen', states: [
  state('empty', SignInScreen()),
  state('error', SignInScreen(initialError: 'Invalid email')),
  state('filled', SignInScreen(initialEmail: 'user@test.com')),
]),
```
Output depends on `stateOutputMode` set in `printSession`:
- `StateOutputMode.prefix` (default): `print_widget/output/sign_in_screen/empty_<device>.png`
- `StateOutputMode.suffix`: `print_widget/output/sign_in_screen/<device>_empty.png`
- `StateOutputMode.folder`: `print_widget/output/sign_in_screen/empty/<device>.png`

For widgets with states:
```dart
widgets('status_badge', states: [
  state('active', StatusBadge(status: Status.active)),
  state('inactive', StatusBadge(status: Status.inactive)),
], size: Size(120, 40)),
```

## Multi-device

```dart
widget('card', MyCard(), devices: DeviceFrame.popular),
// popular = iphone_15_pro, pixel_7, ipad_pro_11
```

## After generating

Read `print_widget/output/manifest.json` to find PNGs:
```json
{"name": "login_page", "file": "login_page/iphone_15_pro.png", "device": "iphone_15_pro"}
```
Grouped states include a `"state"` field:
```json
{"name": "sign_in_screen", "state": "empty", "file": "sign_in_screen/empty_iphone_15_pro.png", "device": "iphone_15_pro"}
```
View screenshot at: `print_widget/output/<name>/<device>.png` or with states depending on `stateOutputMode`

## Devices

`iphone_se`, `iphone_14`, `iphone_15_pro`, `iphone_16_pro_max`, `ipad_mini`, `ipad_air`, `ipad_pro_11`, `ipad_pro_13`, `pixel_7`, `pixel_8_pro`, `samsung_s24`, `samsung_s24_ultra`
