import * as vscode from 'vscode';
import * as path from 'path';
import { ManifestEntry } from '../manifest/manifest-parser';
import { escapeHtml, formatDevice, getNonce, cspMeta, checkerboardBg } from './utils';

export class PreviewPanel {
  private static panels = new Map<string, { panel: vscode.WebviewPanel; entry: ManifestEntry; imagePath: string }>();

  static show(
    context: vscode.ExtensionContext,
    entry: ManifestEntry,
    imagePath: string,
  ): void {
    const key = imagePath;
    const existing = this.panels.get(key);
    if (existing) {
      existing.panel.reveal();
      return;
    }

    const nonce = getNonce();
    const panel = vscode.window.createWebviewPanel(
      'printWidget.preview',
      `${entry.name} — ${formatDevice(entry.device)}`,
      vscode.ViewColumn.One,
      { enableScripts: true, localResourceRoots: [vscode.Uri.file(path.dirname(imagePath))] },
    );

    const imageUri = panel.webview.asWebviewUri(vscode.Uri.file(imagePath));

    panel.webview.html = getPreviewHtml(panel.webview, nonce, entry, imageUri.toString());
    panel.iconPath = new vscode.ThemeIcon('file-media');

    this.panels.set(key, { panel, entry, imagePath });
    panel.onDidDispose(() => this.panels.delete(key));
  }

  static refreshAll(): void {
    for (const [key, { panel, entry, imagePath }] of this.panels) {
      try {
        const nonce = getNonce();
        const imageUri = panel.webview.asWebviewUri(vscode.Uri.file(imagePath));
        panel.webview.html = getPreviewHtml(panel.webview, nonce, entry, imageUri.toString());
      } catch {
        // panel may have been disposed
      }
    }
  }
}

function getPreviewHtml(webview: vscode.Webview, nonce: string, entry: ManifestEntry, imageUri: string): string {
  const device = escapeHtml(formatDevice(entry.device));
  const name = escapeHtml(entry.name);
  const type = escapeHtml(entry.type);
  const state = entry.state ? escapeHtml(entry.state) : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  ${cspMeta(webview, nonce)}
  <style>
    body {
      margin: 0;
      padding: 16px;
      background: var(--vscode-editor-background);
      color: var(--vscode-editor-foreground);
      display: flex;
      flex-direction: column;
      align-items: center;
      font-family: var(--vscode-font-family);
    }
    .info {
      margin-bottom: 12px;
      font-size: 12px;
      opacity: 0.7;
      text-align: center;
    }
    .info span { margin: 0 8px; }
    .container {
      max-width: 100%;
      overflow: auto;
      border: 1px solid var(--vscode-panel-border);
      border-radius: 4px;
      ${checkerboardBg}
      cursor: pointer;
    }
    img {
      display: block;
      max-width: 100%;
      height: auto;
      transition: max-width 0.2s ease;
    }
    img.actual-size {
      max-width: none;
    }
    .zoom-hint {
      font-size: 11px;
      opacity: 0.5;
      margin-top: 8px;
    }
  </style>
</head>
<body>
  <div class="info">
    <span>${device}</span>
    <span>${entry.width}\u00d7${entry.height}</span>
    <span>${entry.widthPx}\u00d7${entry.heightPx}px</span>
    <span>${type}</span>
    ${state ? `<span>state: ${state}</span>` : ''}
  </div>
  <div class="container" id="container">
    <img src="${imageUri}" alt="${name}" id="previewImg" />
  </div>
  <div class="zoom-hint" id="zoomHint">Click image to toggle actual size</div>
  <script nonce="${nonce}">
    var img = document.getElementById('previewImg');
    var container = document.getElementById('container');
    var hint = document.getElementById('zoomHint');
    var isActualSize = false;
    container.addEventListener('click', function() {
      isActualSize = !isActualSize;
      if (isActualSize) {
        img.classList.add('actual-size');
        hint.textContent = 'Click image to fit to width';
      } else {
        img.classList.remove('actual-size');
        hint.textContent = 'Click image to toggle actual size';
      }
    });
  </script>
</body>
</html>`;
}
