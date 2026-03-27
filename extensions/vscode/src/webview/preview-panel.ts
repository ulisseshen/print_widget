import * as vscode from 'vscode';
import * as path from 'path';
import { ManifestEntry } from '../manifest/manifest-parser';

export class PreviewPanel {
  private static panels = new Map<string, vscode.WebviewPanel>();

  static show(
    context: vscode.ExtensionContext,
    entry: ManifestEntry,
    imagePath: string,
  ): void {
    const key = imagePath;
    const existing = this.panels.get(key);
    if (existing) {
      existing.reveal();
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      'printWidget.preview',
      `${entry.name} — ${formatDevice(entry.device)}`,
      vscode.ViewColumn.One,
      { enableScripts: false, localResourceRoots: [vscode.Uri.file(path.dirname(imagePath))] },
    );

    const imageUri = panel.webview.asWebviewUri(vscode.Uri.file(imagePath));

    panel.webview.html = getPreviewHtml(entry, imageUri.toString());
    panel.iconPath = new vscode.ThemeIcon('file-media');

    this.panels.set(key, panel);
    panel.onDidDispose(() => this.panels.delete(key));
  }
}

function getPreviewHtml(entry: ManifestEntry, imageUri: string): string {
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
      background: #1a1a2e;
    }
    img {
      display: block;
      max-width: 100%;
      height: auto;
    }
  </style>
</head>
<body>
  <div class="info">
    <span>${formatDevice(entry.device)}</span>
    <span>${entry.width}×${entry.height}</span>
    <span>${entry.widthPx}×${entry.heightPx}px</span>
    <span>${entry.type}</span>
    ${entry.state ? `<span>state: ${entry.state}</span>` : ''}
  </div>
  <div class="container">
    <img src="${imageUri}" alt="${entry.name}" />
  </div>
</body>
</html>`;
}

function formatDevice(device: string): string {
  return device.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}
