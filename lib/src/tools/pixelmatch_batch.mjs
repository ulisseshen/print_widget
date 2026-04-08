#!/usr/bin/env node
// Batched pixel diff helper for print_widget.
//
// Usage:
//   node pixelmatch_batch.mjs < payload.json
//
// Payload (stdin, JSON):
// {
//   "threshold": 0.1,               // YIQ per-pixel cutoff (0.0–1.0), default 0.1
//   "includeAA": false,             // treat anti-aliased pixels as equal (recommended)
//   "pairs": [
//     {
//       "name": "header",
//       "actual": "/abs/path/to/generated/header.png",
//       "expected": "/abs/path/to/reference/header.png",
//       "diffOut": "/abs/path/to/generated/header_diff.png"   // optional
//     }
//   ]
// }
//
// Result (stdout, JSON, one object):
// {
//   "success": true,
//   "results": [
//     {
//       "name": "header",
//       "similarity": 0.973,         // 1 - (mismatched / total)
//       "mismatchedPixels": 1247,
//       "totalPixels": 46080,
//       "width": 1440,
//       "height": 32,
//       "diffPath": "/abs/path/to/generated/header_diff.png",
//       "error": null
//     }
//   ],
//   "errors": []
// }
//
// Exits 0 on success (including "some regions below threshold"), 2 on fatal error.
// Threshold checking is the caller's job — this helper only measures.
//
// Dependencies: pixelmatch@^7.1.0, pngjs@^7.0.0

import fs from 'node:fs';
import path from 'node:path';

async function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

function loadPng(PNG, filePath) {
  const buf = fs.readFileSync(filePath);
  return PNG.sync.read(buf);
}

function savePng(PNG, png, filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, PNG.sync.write(png));
}

async function main() {
  let pixelmatch;
  let PNG;
  try {
    pixelmatch = (await import('pixelmatch')).default;
    PNG = (await import('pngjs')).PNG;
  } catch (err) {
    const msg =
      'pixelmatch_batch: missing npm deps. Install with:\n' +
      '  npm install pixelmatch pngjs\n' +
      '(run in the directory containing package.json)\n\n' +
      'Underlying error: ' +
      err.message;
    process.stdout.write(
      JSON.stringify({ success: false, results: [], errors: [msg] })
    );
    process.exit(2);
  }

  let raw;
  try {
    raw = await readStdin();
  } catch (err) {
    process.stdout.write(
      JSON.stringify({
        success: false,
        results: [],
        errors: ['Failed to read stdin: ' + err.message],
      })
    );
    process.exit(2);
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch (err) {
    process.stdout.write(
      JSON.stringify({
        success: false,
        results: [],
        errors: ['Invalid JSON payload: ' + err.message],
      })
    );
    process.exit(2);
  }

  const threshold =
    typeof payload.threshold === 'number' ? payload.threshold : 0.1;
  const includeAA =
    typeof payload.includeAA === 'boolean' ? payload.includeAA : false;
  const pairs = Array.isArray(payload.pairs) ? payload.pairs : [];

  const results = [];
  const errors = [];

  for (const pair of pairs) {
    const name = pair.name || 'unnamed';
    try {
      if (!fs.existsSync(pair.actual)) {
        results.push({
          name,
          error: `actual image not found: ${pair.actual}`,
          similarity: 0,
        });
        continue;
      }
      if (!fs.existsSync(pair.expected)) {
        results.push({
          name,
          error: `expected image not found: ${pair.expected}`,
          similarity: 0,
        });
        continue;
      }

      const actual = loadPng(PNG, pair.actual);
      const expected = loadPng(PNG, pair.expected);

      if (actual.width !== expected.width || actual.height !== expected.height) {
        results.push({
          name,
          error:
            `dimension mismatch: actual ${actual.width}×${actual.height} vs ` +
            `expected ${expected.width}×${expected.height} — ` +
            'pin the viewport before comparing',
          similarity: 0,
          actualWidth: actual.width,
          actualHeight: actual.height,
          expectedWidth: expected.width,
          expectedHeight: expected.height,
        });
        continue;
      }

      const { width, height } = actual;
      const diff = new PNG({ width, height });
      const mismatchedPixels = pixelmatch(
        actual.data,
        expected.data,
        diff.data,
        width,
        height,
        { threshold, includeAA, alpha: 0.1, diffColor: [255, 0, 0] }
      );

      const totalPixels = width * height;
      const similarity = totalPixels > 0 ? 1 - mismatchedPixels / totalPixels : 1;

      let diffPath = null;
      if (pair.diffOut) {
        savePng(PNG, diff, pair.diffOut);
        diffPath = pair.diffOut;
      }

      results.push({
        name,
        similarity,
        mismatchedPixels,
        totalPixels,
        width,
        height,
        diffPath,
        error: null,
      });
    } catch (err) {
      results.push({
        name,
        error: err.message || String(err),
        similarity: 0,
      });
      errors.push(`${name}: ${err.message || err}`);
    }
  }

  process.stdout.write(
    JSON.stringify(
      { success: true, results, errors },
      null,
      2
    )
  );
  process.exit(0);
}

main();
