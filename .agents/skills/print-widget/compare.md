# Using print_widget compare

`print_widget compare` is the **objective stop condition** for the iteration loop. It runs pixelmatch (via Node) on each generated crop against its reference crop, returns per-region similarity scores, and writes heatmap PNGs showing red pixels wherever differences exist.

Without `compare`, the loop has no ground truth — the agent keeps guessing. With it, convergence is measurable.

## Prerequisites

- `node` must be installed and on `PATH`
- In the user's project root, run once:
  ```bash
  npm install pixelmatch pngjs
  ```
  This creates `node_modules/` which `compare` shells into.
- The `PrintEntry` must have `crops:` or `cropsFrom:` set so `generate` produces matched crops on the Flutter side.
- Reference crops must exist at:
  ```
  print_widget/output/<entry>/.reference/crops/*.png
  ```
  A top-level `print_widget/output/<entry>/.reference/<device>.png` is used as fallback when no per-region crops are available.

## Running

```bash
print_widget compare                      # all entries with references
print_widget compare --name=<entry>       # one entry
print_widget compare --threshold=0.98     # override the 0.95 default
print_widget compare --json               # machine-readable output
```

## Reading results

- Per-region score **>= threshold** → ✓ passing
- Per-region score **below threshold** → ✗ failing
- Heatmaps are written to:
  ```
  print_widget/output/<entry>/crops/<region>_diff.png
  ```
  Red pixels mark exactly where the generated output diverges from the reference. Open these first — they tell you *what* is wrong, not just *that* something is wrong.

## When comparison fails

- **Dimension mismatch** → viewport pinning problem. See `viewport.md`. Fix the viewport before anything else; do not try to "average out" a size mismatch.
- **Missing crop** → regenerate with `cropsFrom:` properly set on the `PrintEntry`, or check that `_index.json` references exist.
- **Score below threshold** → read the heatmap, identify what changed (spacing, color, radius, typography), fix it, regenerate, re-compare.

## Integration with the iterate loop

Exit codes are designed for scripting:

- `0` → all regions converged, loop done
- `1` → one or more regions below threshold, loop must continue
- `2` → fatal error (missing Node, bad config, reference not found)

## Never accept mismatch silently

If `compare` fails repeatedly on the same region, do **not** lower the threshold to "make it pass". Escalate with the residual diff report: which region, current score, heatmap path, and the last change that moved the score. Silent tolerance is how visual drift accumulates.
