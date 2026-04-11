# Viewport Contract (Phase 0)

## Why this matters

Flutter and the reference source must render at **exactly** the same dimensions. Any mismatch causes pixelmatch to throw a dimension error, and the iteration loop either gets stuck or — worse — drifts in the wrong direction while appearing to make progress.

This is specifically the **web-divergence problem**: mobile targets are constrained by device presets, but web viewports are arbitrary. A 1440-wide reference against a 1280-wide Flutter render will *never* converge, no matter how many iterations you run.

## Rule

**Pin the viewport before writing any code.** Not before generation, not before compare — before *extraction*, before *implementation*, before anything else. Phase 0 is called Phase 0 because it blocks all later phases.

## Determining the target viewport

- **Figma**: call `mcp__figma__get_metadata` → read `frame.width` x `frame.height`.
- **Lovable (Playwright extract)**: read `tokens.json` → the `viewport: {width, height}` field set by the extract script.
- **Screenshot upload**: read image dimensions via `identify <file>` (ImageMagick) or `sips -g pixelWidth -g pixelHeight <file>` on macOS.
- **User-supplied URL**: detect via the page's `<meta name="viewport">` tag, or ask the user directly. Do not assume.

## Pinning on the print_widget side

Either use a matching DeviceFrame preset:

```dart
devices: [DeviceFrame.web1440]
```

or define a custom one inline:

```dart
DeviceFrame(
  name: 'custom_lovable',
  size: Size(1440, 900),
  pixelRatio: 2.0,
)
```

Pass it via the `devices:` parameter of the `PrintEntry` in `print_widget/config.dart`.

## Pinning on the reference side

- **Lovable extract**: pass `viewport: {width, height}` to the extract script's `states.json`. The Playwright run will set `page.setViewportSize(...)` before capture.
- **Figma**: download the PNG at the frame's natural dimensions (1x), do not rescale.
- **Screenshot**: use the file as-is; do not resize.

## HARD STOP

If the two dimensions do not match, **do not proceed**. Do not generate, do not compare, do not "see how close it gets". Fix the viewport first. The iteration loop cannot converge against a mismatched target; every change you make will look like progress on some regions and regression on others, and the loop will oscillate until the hard cap.

## Fallback for tall scrolling pages

If the reference is a non-standard scrolling capture (e.g. 1440 x 2400), configure print_widget with:

```dart
DeviceFrame(
  name: 'lovable_scroll',
  size: Size(1440, 2400),
  pixelRatio: 2.0,
)
// and on the entry:
scrollExtent: 2400,
```

so the rendered Flutter widget matches the full-page screenshot rather than just the above-the-fold viewport.
