# Add a Widget or Page Entry

Instructions for adding new entries to the print_widget print list.

## Adding a Page (Full Screen)

Pages fill the entire device screen. Use for routes/screens.

In `print_widget/config.dart`, add to `printList`:

```dart
page('settings_page', const SettingsPage()),
```

With multi-device rendering:

```dart
page('settings_page', const SettingsPage(), devices: DeviceFrame.popular),
```

## Adding a Widget (Component)

Widgets are centered on screen. Use for cards, buttons, and other components.

```dart
widget('user_avatar', const UserAvatar(name: 'John'), size: Size(100, 100)),
```

Without a custom size (renders at full device screen size, widget centered):

```dart
widget('search_bar', SearchBar(controller: TextEditingController())),
```

With multi-device:

```dart
widget('product_card', ProductCard(data: mockData),
  size: Size(350, 400),
  devices: DeviceFrame.popular,
),
```

## Optional: Printable Mixin

Add `with Printable` to a widget class so it declares its own print metadata:

```dart
class ProductCard extends StatelessWidget with Printable {
  @override
  String get printName => 'product_card';

  @override
  PrintType get printType => PrintType.widget;

  // ... widget build method
}
```

## Test a Single Entry

Generate only the new entry to verify it quickly:

```bash
print_widget generate --name=settings_page
```

## Device Options

| Preset | Devices |
|--------|---------|
| `DeviceFrame.popular` | iphone_15_pro, pixel_7, ipad_pro_11 |
| `DeviceFrame.allPhones` | 8 phone devices |
| `DeviceFrame.allTablets` | 4 tablet devices |

Or specify a single device:

```dart
page('login', const LoginPage(), devices: [DeviceFrame.pixel7]),
```
