import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { ManifestEntry } from '../manifest/manifest-parser';

export class FigmaComparisonPanel {
  static async show(
    context: vscode.ExtensionContext,
    entry: ManifestEntry,
    screenshotPath: string,
  ): Promise<void> {
    // Auto-detect .reference/ image saved by the AI skill
    const refPath = FigmaComparisonPanel.findReference(screenshotPath, entry);
    let figmaPath: string;

    if (refPath) {
      figmaPath = refPath;
    } else {
      const figmaUri = await vscode.window.showOpenDialog({
        canSelectMany: false,
        filters: { Images: ['png', 'jpg', 'jpeg'] },
        title: 'Select design image to compare',
        openLabel: 'Compare',
      });
      if (!figmaUri || figmaUri.length === 0) return;
      figmaPath = figmaUri[0].fsPath;
    }

    const roots = [path.dirname(screenshotPath), path.dirname(figmaPath)];

    const pixelmatchPath = path.join(context.extensionPath, 'media', 'webview', 'vendor', 'pixelmatch.min.js');
    let pixelmatchSrc = '';
    if (fs.existsSync(pixelmatchPath)) {
      pixelmatchSrc = fs.readFileSync(pixelmatchPath, 'utf-8');
    }

    const panel = vscode.window.createWebviewPanel(
      'printWidget.figmaComparison',
      `Figma Compare: ${entry.name}`,
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        localResourceRoots: roots.map((r) => vscode.Uri.file(r)),
      },
    );

    const ssUri = panel.webview.asWebviewUri(vscode.Uri.file(screenshotPath)).toString();
    const fUri = panel.webview.asWebviewUri(vscode.Uri.file(figmaPath)).toString();

    panel.webview.html = getFigmaComparisonHtml(entry.name, ssUri, fUri, pixelmatchSrc);
    panel.iconPath = new vscode.ThemeIcon('file-media');
  }

  static findReference(screenshotPath: string, entry: ManifestEntry): string | null {
    const dir = path.dirname(screenshotPath);
    const refDir = path.join(dir, '.reference');
    const filename = path.basename(screenshotPath);

    // Try exact match: .reference/<device>.png
    const exact = path.join(refDir, filename);
    if (fs.existsSync(exact)) return exact;

    // Try any image in .reference/
    if (fs.existsSync(refDir)) {
      const files = fs.readdirSync(refDir).filter((f) => /\.(png|jpg|jpeg)$/i.test(f));
      if (files.length === 1) return path.join(refDir, files[0]);
    }

    return null;
  }

  static hasReference(screenshotPath: string, entry: ManifestEntry): boolean {
    return this.findReference(screenshotPath, entry) !== null;
  }
}

function getFigmaComparisonHtml(
  name: string,
  screenshotUri: string,
  figmaUri: string,
  pixelmatchSrc: string,
): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      margin: 0;
      padding: 16px;
      background: var(--vscode-editor-background);
      color: var(--vscode-editor-foreground);
      font-family: var(--vscode-font-family);
    }
    h2 { margin: 0 0 4px; font-size: 16px; font-weight: 500; }
    .subtitle { font-size: 12px; opacity: 0.6; margin-bottom: 16px; }
    .score-bar {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 16px;
      padding: 12px 16px;
      border-radius: 6px;
      border: 1px solid var(--vscode-panel-border);
    }
    .score-value {
      font-size: 28px;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
    }
    .score-label { font-size: 12px; opacity: 0.7; }
    .score-bar.high { border-color: #4caf50; }
    .score-bar.medium { border-color: #ff9800; }
    .score-bar.low { border-color: #f44336; }
    .score-bar.high .score-value { color: #4caf50; }
    .score-bar.medium .score-value { color: #ff9800; }
    .score-bar.low .score-value { color: #f44336; }
    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr 1fr;
      gap: 12px;
    }
    .panel-label {
      font-size: 12px;
      font-weight: 600;
      margin-bottom: 6px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      opacity: 0.7;
    }
    .panel-img {
      border: 1px solid var(--vscode-panel-border);
      border-radius: 4px;
      overflow: hidden;
      background: #1a1a2e;
    }
    .panel-img img, .panel-img canvas {
      display: block;
      width: 100%;
      height: auto;
    }
    .threshold-row {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 16px;
      font-size: 12px;
    }
    .threshold-row input[type="range"] { width: 200px; }
    .loading {
      text-align: center;
      padding: 40px;
      font-size: 14px;
      opacity: 0.6;
    }
    .warning {
      background: var(--vscode-inputValidation-warningBackground);
      border: 1px solid var(--vscode-inputValidation-warningBorder);
      padding: 8px 12px;
      border-radius: 4px;
      font-size: 12px;
      margin-bottom: 12px;
    }
  </style>
</head>
<body>
  <h2>Figma Comparison: ${name}</h2>
  <div class="subtitle">Screenshot vs Figma design — differences highlighted in red</div>

  <div id="loading" class="loading">Analyzing images...</div>
  <div id="warning" class="warning" style="display:none"></div>

  <div id="results" style="display:none">
    <div class="score-bar" id="scoreBar">
      <div>
        <div class="score-value" id="scoreValue">—</div>
        <div class="score-label">similarity</div>
      </div>
      <div>
        <div id="pixelInfo" style="font-size:12px; opacity:0.7"></div>
      </div>
    </div>

    <div class="threshold-row">
      <label>Threshold:</label>
      <input type="range" id="threshold" min="0" max="50" value="10" />
      <span id="thresholdValue">0.10</span>
    </div>

    <div class="grid">
      <div>
        <div class="panel-label">Screenshot</div>
        <div class="panel-img"><img id="ssImg" /></div>
      </div>
      <div>
        <div class="panel-label">Figma Design</div>
        <div class="panel-img"><img id="figmaImg" /></div>
      </div>
      <div>
        <div class="panel-label">Differences</div>
        <div class="panel-img"><canvas id="diffCanvas"></canvas></div>
      </div>
    </div>
  </div>

  <script>
    ${pixelmatchSrc || '// pixelmatch not bundled — using inline fallback'}

    ${!pixelmatchSrc ? getPixelmatchFallback() : ''}

    const ssImg = document.getElementById('ssImg');
    const figmaImg = document.getElementById('figmaImg');
    const diffCanvas = document.getElementById('diffCanvas');
    const scoreBar = document.getElementById('scoreBar');
    const scoreValue = document.getElementById('scoreValue');
    const pixelInfo = document.getElementById('pixelInfo');
    const loading = document.getElementById('loading');
    const results = document.getElementById('results');
    const warning = document.getElementById('warning');
    const thresholdInput = document.getElementById('threshold');
    const thresholdValue = document.getElementById('thresholdValue');

    let ssData, figmaData, width, height;

    function loadImage(src) {
      return new Promise((resolve, reject) => {
        const img = new Image();
        img.crossOrigin = 'anonymous';
        img.onload = () => resolve(img);
        img.onerror = reject;
        img.src = src;
      });
    }

    function getImageData(img, w, h) {
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0, w, h);
      return ctx.getImageData(0, 0, w, h);
    }

    function runComparison(threshold) {
      const diff = new ImageData(width, height);
      const numDiff = pixelmatch(
        ssData.data, figmaData.data, diff.data,
        width, height,
        { threshold, alpha: 0.3, diffColor: [255, 60, 60] }
      );

      const total = width * height;
      const similarity = ((1 - numDiff / total) * 100).toFixed(1);

      scoreValue.textContent = similarity + '%';
      pixelInfo.textContent = numDiff.toLocaleString() + ' / ' + total.toLocaleString() + ' pixels differ';

      scoreBar.className = 'score-bar';
      if (parseFloat(similarity) >= 95) scoreBar.classList.add('high');
      else if (parseFloat(similarity) >= 80) scoreBar.classList.add('medium');
      else scoreBar.classList.add('low');

      diffCanvas.width = width;
      diffCanvas.height = height;
      diffCanvas.getContext('2d').putImageData(diff, 0, 0);
    }

    async function init() {
      try {
        const [ssImgEl, figmaImgEl] = await Promise.all([
          loadImage('${screenshotUri}'),
          loadImage('${figmaUri}'),
        ]);

        width = ssImgEl.naturalWidth;
        height = ssImgEl.naturalHeight;

        if (figmaImgEl.naturalWidth !== width || figmaImgEl.naturalHeight !== height) {
          warning.style.display = 'block';
          warning.textContent = 'Images have different dimensions. Figma image ('
            + figmaImgEl.naturalWidth + '×' + figmaImgEl.naturalHeight
            + ') was scaled to match screenshot (' + width + '×' + height + ').';
        }

        ssImg.src = '${screenshotUri}';
        figmaImg.src = '${figmaUri}';

        ssData = getImageData(ssImgEl, width, height);
        figmaData = getImageData(figmaImgEl, width, height);

        runComparison(0.1);

        loading.style.display = 'none';
        results.style.display = 'block';

        thresholdInput.addEventListener('input', () => {
          const t = thresholdInput.value / 100;
          thresholdValue.textContent = t.toFixed(2);
          runComparison(t);
        });
      } catch (err) {
        loading.textContent = 'Failed to load images: ' + err.message;
      }
    }

    init();
  </script>
</body>
</html>`;
}

function getPixelmatchFallback(): string {
  // Inline minimal pixelmatch implementation for when the vendor file is not bundled
  return `
    function pixelmatch(img1, img2, output, width, height, options) {
      const threshold = (options && options.threshold !== undefined) ? options.threshold : 0.1;
      const diffColor = (options && options.diffColor) || [255, 60, 60];
      const maxDelta = 35215 * threshold * threshold;
      let diff = 0;

      for (let i = 0; i < img1.length; i += 4) {
        const r1 = img1[i], g1 = img1[i+1], b1 = img1[i+2], a1 = img1[i+3];
        const r2 = img2[i], g2 = img2[i+1], b2 = img2[i+2], a2 = img2[i+3];

        const dr = r1 - r2, dg = g1 - g2, db = b1 - b2, da = a1 - a2;
        const delta = dr*dr*0.299 + dg*dg*0.587 + db*db*0.114 + da*da;

        if (delta > maxDelta) {
          output[i] = diffColor[0];
          output[i+1] = diffColor[1];
          output[i+2] = diffColor[2];
          output[i+3] = 255;
          diff++;
        } else {
          const avg = (r1 + g1 + b1) / 3;
          output[i] = avg;
          output[i+1] = avg;
          output[i+2] = avg;
          output[i+3] = 64;
        }
      }
      return diff;
    }
  `;
}
