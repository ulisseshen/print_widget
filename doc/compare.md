# print_widget compare: pixelmatch-backed visual diff

## What it is and why

`print_widget compare` is the objective stop condition for the visual
iteration loop. Without it, an AI agent that is iterating on a Flutter
screen against a reference design has to eyeball compressed full-page
thumbnails and guess whether the last change got closer or further from
the target. Guessing produces oscillation: the model improves the header,
notices the footer regressed, fixes the footer, the header regresses, and
nothing converges until the hard iteration cap trips.

`compare` replaces the guess with a measurement. It runs
[pixelmatch](https://github.com/mapbox/pixelmatch) v7 on per-region crops
and returns a score per region plus a pass/fail verdict against a
configured threshold. The loop can now terminate on a concrete condition:
all regions above threshold.

The command is deliberately thin. It does not render anything. It does not
re-run `flutter test`. It only reads PNGs from disk, hands them to a
bundled Node helper, and prints the result.

## Prerequisites

| Requirement          | Detail                                                                             |
|----------------------|------------------------------------------------------------------------------------|
| Node.js              | Installed and on `PATH`. Any version that supports ESM dynamic `import()`.         |
| pixelmatch + pngjs   | Installed once in the user's Flutter project: `npm install pixelmatch pngjs`       |
| Reference crops      | Files at `<outputDir>/<entry>/.reference/crops/*.png`                              |
| Generated crops      | Files at `<outputDir>/<entry>/crops/*.png` (requires `crops` or `cropsFrom`)       |
| `print_widget.yaml`  | `reference_dir:` and `compare_threshold:` (defaults: `.reference` and `0.95`)      |

The Node dependencies live in the user's project `node_modules/` directory
because the CLI invokes `node` with the project directory as
`workingDirectory`. A single `npm install pixelmatch pngjs` at the project
root is enough; no package.json entry is required.

If references are missing for an entry but a top-level
`.reference/<device>.png` exists, the CLI falls back to that file (whole
device image) for entries that do not use crops. This is a convenience for
mobile flows that have not adopted crops yet.

## CLI reference

| Command                                           | Effect                                                       |
|----------------------------------------------------|--------------------------------------------------------------|
| `print_widget compare`                             | Compares every entry that has a reference directory         |
| `print_widget compare --name=dashboard`            | Compares one entry by name                                   |
| `print_widget compare --threshold=0.98`            | Override the yaml threshold for this invocation              |
| `print_widget compare --device=web_1440`           | Compare against a specific device preset                     |
| `print_widget compare --json`                      | Emit machine-readable result JSON on stdout                  |
| `print_widget compare --config=path/to/pw.yaml`    | Use a non-default config path                                |

Flags combine freely: `print_widget compare --name=dashboard
--threshold=0.99 --json` runs one entry at a stricter threshold and
returns parseable output.

## Dart to Node handoff

The split is:

1. **Dart plans.** Reads `print_widget.yaml`. Resolves the bundled helper
   script via `Isolate.resolvePackageUri('package:print_widget_flutter/src/tools/pixelmatch_batch.mjs')`
   with fallbacks for local dev checkouts. For each entry being compared,
   walks `.reference/crops/*.png` and pairs each file with its counterpart
   in `crops/*.png` by matching filename. Entries with no matched pairs
   are recorded as errors, not silently skipped.

2. **Dart builds payload.** A JSON document shaped like this:

   ```json
   {
     "threshold": 0.1,
     "includeAA": false,
     "pairs": [
       {
         "name": "dashboard/header",
         "actual":   "test/prints/output/dashboard/crops/header.png",
         "expected": "test/prints/output/dashboard/.reference/crops/header.png",
         "diffOut":  "test/prints/output/dashboard/crops/header_diff.png"
       }
     ]
   }
   ```

3. **Dart spawns Node.** `Process.start('node', [scriptPath],
   workingDirectory: projectDir)`. The payload is written to Node's stdin
   and the stream is closed.

4. **Node runs pixelmatch.** The helper dynamically imports `pixelmatch`
   and `pngjs`. If either import fails, it prints a loud error including
   the exact install command and exits non-zero. For each pair it reads
   both PNGs, validates they have equal width and height, runs
   `pixelmatch(actual, expected, diff, w, h, { threshold: 0.1, includeAA:
   false })`, writes the heatmap PNG to `diffOut`, and records
   `mismatchedPixels` and `totalPixels`.

5. **Node emits result.** A single JSON document on stdout:

   ```json
   {
     "results": [
       { "name": "dashboard/header", "mismatched": 124, "total": 460800,
         "score": 0.99973, "diff": "…/header_diff.png" }
     ],
     "errors": []
   }
   ```

6. **Dart parses and exits.** Computes per-region `score = 1 -
   mismatched/total`, compares against threshold, prints human or JSON
   output, exits with the appropriate code.

## Exit codes

| Code | Meaning                                                                            |
|------|-------------------------------------------------------------------------------------|
| `0`  | All compared regions meet or exceed the threshold. Convergence achieved.           |
| `1`  | One or more regions are below threshold. Not fatal — the loop should iterate.      |
| `2`  | Fatal error: Node not on PATH, pixelmatch/pngjs not installed, reference missing, dimension mismatch, bad config, or the Node helper crashed. |

Exit code 2 is the "stop and fix the setup" signal. Exit code 1 is the
"keep iterating" signal. Exit code 0 is the terminal success of the loop.

## Reading the output

Human output looks like this:

```
print_widget compare
  threshold: 0.97
  entries:   1

  dashboard
    [OK]   header      score=0.99973  mismatched=124     heatmap=crops/header_diff.png
    [OK]   sidebar     score=0.99841  mismatched=3147    heatmap=crops/sidebar_diff.png
    [FAIL] main        score=0.94102  mismatched=132089  heatmap=crops/main_diff.png

  1 of 3 regions below threshold (0.97)
```

The heatmap PNGs are written alongside the generated crops. Red pixels in
the heatmap mark positions where the generated crop diverges from the
reference; transparent or greyed pixels match. The heatmap is the fastest
visual confirmation of where to look next.

JSON output (`--json`) contains the same information in the schema above,
plus the exit code and the effective threshold. Consume this from a
parent script or agent.

## Anti-aliasing suppression

pixelmatch is invoked with `includeAA: false`. This matters for Flutter
text.

Flutter text rendering is sub-pixel: glyph edges are drawn with partial
coverage values that fall on slightly different sub-pixel positions
depending on layout constraints, device pixel ratio, and font scale.
Comparing the same widget rendered twice (or against a reference that was
captured on a different machine) produces dozens of one-channel
differences per glyph — differences that a human could never see.

pixelmatch's algorithm detects pixels that are surrounded by neighbors of
the "correct" color in either image and classifies them as AA pixels. When
`includeAA` is false, these pixels are excluded from the mismatch count
and are drawn in yellow on the heatmap instead of red. Without this,
text-heavy crops would never reach 0.95 even when they are visually
identical to the reference.

The tradeoff is that a few real single-pixel color regressions near
letter edges will also be suppressed. In practice this has not been a
problem: the regressions that matter are not single-pixel.

## Dimension mismatch

The Node helper treats `actual.width != expected.width` or `actual.height
!= expected.height` as a fatal error. It does **not** resize either side.
It does **not** pad. It exits non-zero with a clear message:

```
dimension mismatch on region 'dashboard/header':
  actual   2880x160
  expected 2560x160
```

This is intentional. Automatic resizing would introduce interpolation
artifacts that look like color drift in the diff, hiding real regressions
behind a fuzz of resampling noise. The correct fix is to align the
viewport on both sides before running compare. See viewport.md for the
full contract.

## Threshold interpretation

There are two "thresholds" in this system and they are not the same.

| Threshold               | What it controls                                                 |
|-------------------------|------------------------------------------------------------------|
| pixelmatch `threshold`  | Per-pixel YIQ color distance cutoff. Hard-coded to `0.1` in the helper. Smaller = stricter. |
| `compare_threshold`     | Fraction of pixels that must match. Applied by Dart after the fact. |

`compare_threshold: 0.95` means: after AA suppression, at least 95% of
pixels in the crop were within YIQ distance 0.1 of the reference. It is
an aggregate, not a per-pixel tolerance. Raising it to 0.99 makes the loop
demand near-perfect visual parity; lowering it to 0.90 is useful during
early coarse iteration when only layout is being dialed in.

Do not confuse this with pixelmatch's per-pixel `threshold`. Users who ask
"why won't my compare pass, I set threshold to 0.99" are almost always
confused about which knob they turned.

## yaml configuration

```yaml
reference_dir: .reference
compare_threshold: 0.95              # default, Flutter-native references
cross_engine_threshold: 0.88         # browser-originated references
thresholds:                          # optional per-entry overrides
  home/atoms/kpi_card: 0.90
  home/molecules/complex_table: 0.85
```

All are optional. Defaults shown.

Set the two scalars via CLI:

```bash
print_widget config --reference-dir=.reference --compare-threshold=0.95
```

Per-invocation `--threshold=<N>` always wins over yaml values.

### Threshold resolution priority

When compare runs for an entry, it resolves the threshold in this order (first match wins):

1. `--threshold=<N>` CLI flag
2. `thresholds.<entry>` from yaml
3. `_origin.json` under `<outputDir>/<entry>/<referenceDir>/`:
   - `origin: flutter` (written by `print_widget snapshot`) → `compare_threshold`
   - `origin: browser` (written by `print_widget extract`) → `cross_engine_threshold`
   - File missing or malformed → `cross_engine_threshold` (conservative default)

The resolved threshold + source is printed in the per-entry output so you can see why a widget passed or failed:

```
▸ home/atoms/kpi_card  (threshold: 88.0% — cross-engine (browser reference))
    ✓ kpi_card/iphone_15_pro: 91.23%
```

### Why two thresholds

Skia (Flutter) and Chromium (browser references from Lovable, Figma Make, web captures) render text differently even with the same TTF — subpixel positioning, antialiasing, opsz defaults, kerning. The systematic gap is 5–7% on text-heavy widgets and is NOT fixable by code changes. The pipeline handles it with two knobs:

- **Browser-originated references** (initial iteration, before convergence): use `cross_engine_threshold` (default 0.88)
- **Flutter-native references** (after running `print_widget snapshot` to promote converged output): use `compare_threshold` (default 0.95)

The `_origin.json` marker lets compare pick the right knob automatically — you don't have to remember which entry is in which phase.

## Debugging recipes

### "pixelmatch not installed"

Exit 2, Node stderr says it could not resolve `pixelmatch`. Fix:

```bash
cd <your flutter project>
npm install pixelmatch pngjs
```

Rerun `print_widget compare`. No other setup is needed.

### "dimension mismatch"

Exit 2, Node prints actual vs expected sizes. One side is wrong. The usual
causes:

- `DeviceFrame.pixelRatio` differs between the reference capture and the
  Flutter frame
- `DeviceFrame.size` differs — a 1440 Figma frame compared against a
  1280 Flutter render
- Reference was captured at a different zoom level
- Browser devtools pixel ratio was 1 during extract but Flutter is using 2

Fix the mismatch in the source, not in `compare`. See viewport.md.

### "all regions report 100% but layout looks wrong"

Almost always: the crops being compared are stale. Either generation
never ran for the current Flutter code, or `--name` is pointing at a
different entry than you expect. Run `print_widget generate --name=<entry>`
and rerun compare. Also verify the mtime of the PNGs in `crops/`.

### "I want to see exactly what pixelmatch is doing"

Run with `--json` and read `mismatchedPixels` and `totalPixels` per
region. Open the heatmap `<region>_diff.png` in an image viewer. Red
pixels are real differences, yellow pixels are AA that pixelmatch chose
to ignore. Compare that to the actual crop and the reference crop
side-by-side — this triangulates the precise regression.
