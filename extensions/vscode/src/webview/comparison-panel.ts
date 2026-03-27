import * as vscode from 'vscode';
import * as path from 'path';
import { ManifestEntry, resolveImagePath } from '../manifest/manifest-parser';

export class ComparisonPanel {
  static show(
    context: vscode.ExtensionContext,
    featureName: string,
    entries: ManifestEntry[],
    manifestPath: string,
  ): void {
    const roots = new Set<string>();
    const imageData: { device: string; uri: string; width: number; height: number; widthPx: number; heightPx: number; state?: string }[] = [];

    for (const entry of entries) {
      const imgPath = resolveImagePath(manifestPath, entry);
      roots.add(path.dirname(imgPath));
      imageData.push({
        device: formatDevice(entry.device),
        uri: '', // set after panel creation
        width: entry.width,
        height: entry.height,
        widthPx: entry.widthPx,
        heightPx: entry.heightPx,
        state: entry.state,
      });
    }

    const panel = vscode.window.createWebviewPanel(
      'printWidget.comparison',
      `Compare: ${featureName}`,
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        localResourceRoots: Array.from(roots).map((r) => vscode.Uri.file(r)),
      },
    );

    // Resolve URIs after panel creation
    for (let i = 0; i < entries.length; i++) {
      const imgPath = resolveImagePath(manifestPath, entries[i]);
      imageData[i].uri = panel.webview.asWebviewUri(vscode.Uri.file(imgPath)).toString();
    }

    panel.webview.html = getComparisonHtml(featureName, imageData);
    panel.iconPath = new vscode.ThemeIcon('split-horizontal');
  }
}

interface ImageInfo {
  device: string;
  uri: string;
  width: number;
  height: number;
  widthPx: number;
  heightPx: number;
  state?: string;
}

function getComparisonHtml(featureName: string, images: ImageInfo[]): string {
  const cards = images.map((img) => `
    <div class="card">
      <div class="card-header">
        <strong>${img.device}</strong>
        ${img.state ? `<span class="state">${img.state}</span>` : ''}
        <span class="dims">${img.width}×${img.height}</span>
      </div>
      <div class="card-image">
        <img src="${img.uri}" alt="${img.device}" />
      </div>
    </div>
  `).join('');

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
    h2 {
      margin: 0 0 16px;
      font-size: 16px;
      font-weight: 500;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 16px;
    }
    .card {
      border: 1px solid var(--vscode-panel-border);
      border-radius: 6px;
      overflow: hidden;
      background: var(--vscode-editor-background);
    }
    .card-header {
      padding: 8px 12px;
      font-size: 12px;
      border-bottom: 1px solid var(--vscode-panel-border);
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card-header .state {
      background: var(--vscode-badge-background);
      color: var(--vscode-badge-foreground);
      padding: 2px 6px;
      border-radius: 3px;
      font-size: 11px;
    }
    .card-header .dims {
      margin-left: auto;
      opacity: 0.6;
    }
    .card-image {
      background: #1a1a2e;
      display: flex;
      justify-content: center;
    }
    .card-image img {
      max-width: 100%;
      height: auto;
      display: block;
    }
  </style>
</head>
<body>
  <h2>${featureName} — Device Comparison</h2>
  <div class="grid">${cards}</div>
</body>
</html>`;
}

function formatDevice(device: string): string {
  return device.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}
