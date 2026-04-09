# Viewport contract: pin dimensions before comparing

## The problem

Mobile visual regression is easy. There are only so many iPhones and
Pixels, every device has a canonical logical size and pixel ratio, and
the same preset works for the reference and the Flutter render. You set
`DeviceFrame.iPhone15Pro` on both sides and you are done.

Web is not easy. Web references come in arbitrary sizes: a 1440-wide
Figma frame, a 1920-wide Lovable capture, a 1280-wide screenshot someone
dropped in Slack. Flutter web, meanwhile, will render at whatever size
you configure — and if the two sides do not match, nothing downstream
works.

The failure is subtle. A 1440-wide reference compared against a 1280-wide
Flutter render does not just produce a "slightly wrong" diff. It produces
wrong regions in the crop JSON (coordinates no longer map to the same
content), wrong fonts (media queries reflow at different breakpoints),
wrong line wraps (text columns are narrower), and wrong image sizes
(responsive images pick different sources). Every iteration looks like
progress somewhere and regression somewhere else. The loop oscillates
until the hard cap trips, then reports failure, and the user does not
know why.

The compare step will catch this eventually because pixelmatch refuses
to run on mismatched dimensions. But "compare crashes" is the last line
of defense. By the time you see it, you have already wasted a generate
cycle.

## The rule

Pin the viewport on **both** sides before doing anything else. Before
extraction, before implementation, before the first `print_widget
generate`, before the first `print_widget compare`. This is "Phase 0"
because everything else depends on it, and every later phase silently
corrupts if it is wrong.

"Viewport" here means a triple: **width**, **height**, **pixelRatio**.
All three must match. A 1440x900 @1x reference and a 1440x900 @2x Flutter
render will produce 1440x900 vs 2880x1800 PNGs and pixelmatch will
refuse.

## Determining the target viewport

| Source                       | How to read the viewport                                                                |
|------------------------------|------------------------------------------------------------------------------------------|
| Figma                        | `mcp__figma__get_metadata` → read `frame.width`, `frame.height`. Pixel ratio is 1x or 2x depending on export. |
| Lovable via smart-extract    | Extract script writes `viewport: {width, height}` into `tokens.json`; Playwright pins that viewport before capture. |
| User-supplied screenshot     | `identify image.png` (ImageMagick) or `sips -g pixelWidth -g pixelHeight image.png` on macOS. Divide by the capture device's pixel ratio if known. |
| Live URL                     | Inspect `<meta name="viewport">`, or ask the user explicitly which breakpoint they want matched. |
| Previous golden              | Read the PNG dimensions directly — they are the ground truth.                           |

If the source does not tell you the pixel ratio, assume 2x for anything
captured on a modern laptop (Retina, HiDPI), and 1x for CI-generated
captures running in headless browsers without device-scale-factor set.
When in doubt, ask.

## Pinning on the print_widget side

Two options.

### Use a preset

`DeviceFrame` ships with web presets:

```dart
DeviceFrame.web1440   // Size(1440, 900),  pixelRatio: 2.0
DeviceFrame.web1920   // Size(1920, 1080), pixelRatio: 2.0
```

### Define a custom frame inline

```dart
PrintEntry(
  name: 'dashboard',
  builder: (_) => const DashboardPage(),
  devices: [
    DeviceFrame(
      name: 'lovable_1440',
      size: Size(1440, 2400),
      pixelRatio: 2.0,
    ),
  ],
)
```

Custom frames are the normal path for web work. Presets exist for
convenience; real references rarely match them exactly.

## Pinning on the reference side

| Reference type             | How to pin                                                                             |
|----------------------------|-----------------------------------------------------------------------------------------|
| Figma export               | Download at natural frame dimensions. Do not rescale. A 1440 frame exports at 1440x... at 1x, or 2880x... at 2x. |
| Lovable / smart-extract    | Pass `viewport: {width: 1440, height: 2400}` into `states.json`. The extract script sets Playwright viewport and device scale factor before screenshot. |
| User-supplied screenshot   | If it does not match your target, you have to recapture. Never scale.                  |
| Hand screenshot            | Use the same OS device pixel ratio as your target (browser devtools → Device toolbar → set DPR). |

## Tall scrolling pages

A dashboard does not fit in 900 pixels. Lovable captures the full
scrolled page — say 1440x2400 — and the Flutter render needs to match.

Use `scrollExtent:` on `PrintEntry` to tell print_widget to capture a
taller canvas:

```dart
PrintEntry(
  name: 'dashboard',
  builder: (_) => const DashboardPage(),
  devices: [
    DeviceFrame(
      name: 'lovable_1440',
      size: Size(1440, 900),
      pixelRatio: 2.0,
    ),
  ],
  scrollExtent: 2400,
)
```

The widget is laid out at 1440x900 as usual, but the render surface is
extended to 1440x2400 so scrollable content is captured in full. The
resulting PNG matches the 1440x2400 reference at the same pixel ratio.

## Hard-stop diagnostic

When dimensions do not match, `print_widget compare` fails with exit 2
and a message naming both sizes:

```
dimension mismatch on region 'dashboard/header':
  actual   2880x160
  expected 2560x160
```

This is intentional. The Node helper will never resize either side. The
reason is simple: interpolation artifacts look exactly like real color
regressions in a diff, and once they are in the heatmap you cannot tell
the two apart. Silent resize would produce a loop that converges on the
wrong target — one iteration passes at 95%, the next fails at 94%, no
code change between them, and the model has no signal to act on.

Fix the viewport instead. It is always cheaper than debugging a poisoned
compare.

## Common mistakes

| Symptom                                           | Root cause                                                         | Fix                                            |
|---------------------------------------------------|--------------------------------------------------------------------|------------------------------------------------|
| Compare reports dimension mismatch immediately   | Reference is 1920 wide, `DeviceFrame` is 1440                       | Pick one and update the other                  |
| Generated PNG is half the size of the reference   | `pixelRatio: 1.0` on the frame, reference captured at 2x            | Set `pixelRatio: 2.0`                          |
| Crops hit content above the fold only             | `scrollExtent` missing, reference is a full-page capture            | Set `scrollExtent` to the reference height     |
| Regions drift between iterations                  | Lovable media query reflows at 1280 but target is 1440              | Force Lovable to 1440 during extract           |
| Fonts wrap differently than the reference         | Viewport width mismatch changes line breaks                         | Pin width exactly, including scrollbar offset  |

## Worked example

A Lovable URL needs a pixel-accurate Flutter port.

Step 1 — extract the reference and pin the viewport:

```bash
# smart-extract uses Playwright; viewport is set from states.json
# states.json includes: "viewport": { "width": 1440, "height": 2400 }
npx smart-extract https://example.lovable.app --out=design/dashboard
```

The extract writes PNGs at 1440x2400 @2x (physical 2880x4800) and a
`_index.json` describing each region.

Step 2 — declare the Flutter entry with the matching viewport:

```dart
PrintEntry(
  name: 'dashboard',
  builder: (_) => const DashboardPage(),
  devices: [
    DeviceFrame(
      name: 'lovable_1440',
      size: Size(1440, 2400),
      pixelRatio: 2.0,
    ),
  ],
  scrollExtent: 2400,
  cropsFrom: 'design/dashboard/_index.json',
)
```

Step 3 — copy the extracted crops into `.reference/crops/` so compare
can find them:

```bash
cp design/dashboard/*.png test/prints/output/dashboard/.reference/crops/
```

Step 4 — generate and compare:

```bash
print_widget generate --name=dashboard
print_widget compare  --name=dashboard --threshold=0.95
```

From here on the loop is purely about code quality, not about viewport
setup. The viewport is pinned, the crops pair one-to-one, and any diff
pixelmatch reports is a real regression that can be acted on.
