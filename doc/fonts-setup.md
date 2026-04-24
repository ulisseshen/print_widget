# Fonts setup

How fonts travel from the browser into the Flutter project so generated screenshots match the extracted reference.

## The problem

`print_widget extract` renders Lovable/Figma-Make/any web page via Playwright. When the page declares `font-family: Inter`, the browser either imports Inter via `@font-face` or falls back to a system font. Either way, the screenshot is correct *in the browser*.

The Flutter project is a different universe. `TextStyle(fontFamily: 'Inter')` only renders Inter if:

1. Inter TTFs live inside the project (`assets/fonts/`, `google_fonts/`, or a package), **and**
2. they're registered with Flutter's `FontLoader` before the test paints.

If Inter is missing, Flutter silently falls back to Roboto (Flutter's default) or renders `Ahem` (black rectangles). `pixelmatch` then blames your layout code, when the real bug is a font gap. This cascade is invisible without instrumentation — it just shows up as "I fixed the same spacing 4 times and the score is still 78%".

**`print_widget fonts`** is the bridge: it reads the `(family, weight)` pairs the browser actually used and downloads them into the project.

## The contract

`print_widget extract` writes `_fonts.json` next to every state's `fullpage.png`. Shape:

```json
{
  "$version": "1.0",
  "source": { "url": "...", "state": "initial", "extractor": "extract.mjs" },
  "families": [
    { "family": "Inter", "weights": [400, 500, 600, 700], "sources": ["detected"] },
    { "family": "Geist Mono", "weights": [400], "sources": ["forced"] }
  ],
  "googleFontsCssUrl": "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Geist+Mono:wght@400&display=swap",
  "forceFontSpecs": ["Geist Mono:wght@400"]
}
```

- `families` is the merge of two sources:
  - **detected** — pairs observed on text nodes in the DOM (`getComputedStyle.fontFamily` + `fontWeight`)
  - **forced** — entries from `--force-font=<spec>` or `states.json` `forceFonts`
- System fonts (`sans-serif`, `system-ui`, `helvetica`, …) are filtered. We only record downloadable families.
- `googleFontsCssUrl` is a single CSS2 URL covering every family × weight — useful for manual `curl` inspection.

## The command

```bash
# Default — scans print_widget.yaml output_dir for every _fonts.json and
# downloads to google_fonts/. loadPrintWidgetFonts picks up that directory
# automatically, no pubspec change needed.
print_widget fonts

# Explicit source (a single _fonts.json or a directory to walk):
print_widget fonts --source=print_widget/output/home/.reference/

# Install into assets/fonts and append a flutter.fonts block to pubspec.yaml:
print_widget fonts --dest=assets/fonts

# Same as above, but leave pubspec alone:
print_widget fonts --dest=assets/fonts --no-pubspec

# Preview without fetching; machine-readable:
print_widget fonts --dry-run --json

# Overwrite files that already exist locally:
print_widget fonts --force
```

## Where fonts land — and why `google_fonts/` is the default

| Destination | `pubspec.yaml` change | Picked up by tests | Picked up by the app at runtime |
|---|---|---|---|
| `google_fonts/` (default) | none | yes — `loadPrintWidgetFonts` auto-scans it | only if the `google_fonts` package is used with `GoogleFonts.asset()` |
| `assets/fonts/` + pubspec block | required | yes — via the `flutter.fonts` section | yes — Flutter bundles them |
| `assets/fonts/` without pubspec | none | yes — fallback scan in `loadPrintWidgetFonts` | no — not bundled |

The default is `google_fonts/` because:

1. It's the smallest change — no pubspec diff, no Flutter rebuild required for tests to pick them up.
2. `loadPrintWidgetFonts` already registers both the bare family name (`Inter`) and the variant-qualified names (`Inter_regular`, `Inter_400regular`) expected by the `google_fonts` package. So the same TTFs work whether your app renders via `TextStyle(fontFamily: 'Inter')` or `GoogleFonts.inter()`.
3. The fonts are a development artifact for visual verification — not necessarily something you want shipped in the production bundle.

Switch to `--dest=assets/fonts` when you want the fonts live at app runtime, not just during tests.

## Filename convention

TTFs are saved as `<Family>-<WeightName>.ttf` following the Google Fonts convention:

| Weight | Name |
|---|---|
| 100 | `Thin` |
| 200 | `ExtraLight` |
| 300 | `Light` |
| 400 | `Regular` |
| 500 | `Medium` |
| 600 | `SemiBold` |
| 700 | `Bold` |
| 800 | `ExtraBold` |
| 900 | `Black` |

Examples: `Inter-Regular.ttf`, `Inter-SemiBold.ttf`, `Geist Mono-Regular.ttf`. `font_loader.dart::_parseGoogleFontFilename` splits on the last `-` to recover `(family, weight)` at test startup.

## TTF vs woff2 — why we use an old User-Agent

Google Fonts CSS2 returns **woff2** for modern browsers (smaller, but Flutter's `FontLoader` doesn't accept it) and **ttf** for older clients. `fonts_command.dart` sets:

```
User-Agent: Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.10) Gecko/2009042523 Firefox/3.0.10
```

which triggers the TTF branch. If Google changes this behavior, fix `_ttfUserAgent` in `lib/src/cli/commands/fonts_command.dart`. There's no official TTF-force API.

## Where this fits the pipeline

```
┌──────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│  extract         │ →   │  fonts            │ →   │  generate + cmp   │
│  _fonts.json     │     │  TTFs in project  │     │  Inter renders ✓  │
└──────────────────┘     └───────────────────┘     └───────────────────┘
```

Run `fonts` **once**, right after `extract` (or any time `_fonts.json` changes). `loadPrintWidgetFonts` does the rest at test time — no manual registration, no `loadFonts` callback needed.

## Troubleshooting

**"Text rendered as Ahem (black rectangles)"**
`loadPrintWidgetFonts` prints a summary line at test startup: `[print_widget] Loaded N font registration(s): ...`. If your family isn't there, run `print_widget fonts` and re-run the test. If the download itself fails, check that the family exists on Google Fonts and that the weights requested are supported there.

**"TTF saved but Flutter still uses Roboto"**
The file name must match `<Family>-<Weight>.ttf` exactly. Custom families that aren't on Google Fonts (design-system private fonts) aren't downloadable — add them manually under `assets/fonts/` and declare in `pubspec.yaml`, or ship them in the design-system package whose `pubspec.yaml` already lists them (loaded automatically).

**"The browser rendered Inter but `_fonts.json` is empty"**
`extract.mjs` filters system fonts. If the page declares `font-family: Inter, system-ui, sans-serif` and never loads Inter, the browser falls back to `system-ui` and `getComputedStyle().fontFamily` reports the first entry (`Inter`), but if the page's `document.fonts` doesn't include Inter, the family won't be there. Pass `--force-font="Inter:wght@400;500;600;700"` to `extract` so the browser loads Inter before screenshots AND the spec records it.

**"Google Fonts returns HTTP 400"**
A weight you requested isn't published for that family. Run the `googleFontsCssUrl` from `_fonts.json` in a browser to see which weights Google Fonts actually has — then adjust `forceFonts` (or the page's own `@import`) to stay within supported values.

**"Private/corporate font never downloads"**
`fonts` only knows Google Fonts. For private fonts, skip this command and put the TTFs directly in `assets/fonts/` (declared in `pubspec.yaml`) or in a design-system package dependency that `loadPrintWidgetFonts` auto-detects from `package_config.json`.
