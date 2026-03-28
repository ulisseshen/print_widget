import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import * as cp from 'child_process';
import { ManifestEntry } from '../manifest/manifest-parser';
import { escapeHtml, getNonce, cspMeta } from './utils';

export class DiffPanel {
  private static panels = new Map<string, vscode.WebviewPanel>();

  static async show(
    context: vscode.ExtensionContext,
    entry: ManifestEntry,
    currentImagePath: string,
  ): Promise<void> {
    let previousPath: string | null = null;
    let isTemp = false;

    // Try git-based diff first
    previousPath = await tryGitPrevious(currentImagePath);
    if (previousPath) {
      isTemp = true;
    } else {
      // Fall back to file picker
      const previousUri = await vscode.window.showOpenDialog({
        canSelectMany: false,
        filters: { Images: ['png'] },
        title: 'Select previous screenshot to compare',
        openLabel: 'Compare',
      });

      if (!previousUri || previousUri.length === 0) return;
      previousPath = previousUri[0].fsPath;
    }

    const key = `diff:${currentImagePath}`;
    const existing = this.panels.get(key);
    if (existing) {
      existing.dispose();
      this.panels.delete(key);
    }

    const roots = new Set([path.dirname(currentImagePath), path.dirname(previousPath)]);

    const panel = vscode.window.createWebviewPanel(
      'printWidget.diff',
      `Diff: ${entry.name}`,
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        localResourceRoots: Array.from(roots).map((r) => vscode.Uri.file(r)),
      },
    );

    const nonce = getNonce();
    const currentUri = panel.webview.asWebviewUri(vscode.Uri.file(currentImagePath)).toString();
    const prevUri = panel.webview.asWebviewUri(vscode.Uri.file(previousPath)).toString();

    panel.webview.html = getDiffHtml(panel.webview, nonce, entry.name, currentUri, prevUri);
    panel.iconPath = new vscode.ThemeIcon('diff');

    this.panels.set(key, panel);
    panel.onDidDispose(() => {
      this.panels.delete(key);
      if (isTemp && previousPath) {
        try { fs.unlinkSync(previousPath); } catch { /* ignore */ }
      }
    });
  }
}

function execFileAsync(
  cmd: string,
  args: string[],
  options: cp.ExecFileOptions,
): Promise<Buffer | string> {
  return new Promise((resolve, reject) => {
    cp.execFile(cmd, args, options, (error, stdout) => {
      if (error) { reject(error); return; }
      resolve(stdout);
    });
  });
}

async function tryGitPrevious(filePath: string): Promise<string | null> {
  try {
    const dir = path.dirname(filePath);

    // Check if file is tracked in git
    const logOut = await execFileAsync(
      'git',
      ['log', '--follow', '-1', '--format=%H', '--', filePath],
      { cwd: dir, encoding: 'utf-8' },
    ) as string;
    logOut.trim();

    // Get the relative path from git root
    const gitRoot = (await execFileAsync(
      'git',
      ['rev-parse', '--show-toplevel'],
      { cwd: dir, encoding: 'utf-8' },
    ) as string).trim();

    const relativePath = path.relative(gitRoot, filePath);

    // Extract previous version to temp file
    const buffer = await execFileAsync(
      'git',
      ['show', `HEAD:${relativePath}`],
      { cwd: gitRoot, encoding: 'buffer', maxBuffer: 50 * 1024 * 1024 },
    ) as Buffer;

    if (!buffer || buffer.length === 0) return null;

    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pw-diff-'));
    const tmpFile = path.join(tmpDir, path.basename(filePath));
    fs.writeFileSync(tmpFile, buffer);
    return tmpFile;
  } catch {
    return null;
  }
}

function getDiffHtml(webview: vscode.Webview, nonce: string, name: string, currentUri: string, previousUri: string): string {
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
      font-family: var(--vscode-font-family);
    }
    h2 { margin: 0 0 16px; font-size: 16px; font-weight: 500; }
    .diff-container {
      position: relative;
      display: inline-block;
      border: 1px solid var(--vscode-panel-border);
      border-radius: 6px;
      overflow: hidden;
      max-width: 100%;
    }
    .diff-container img {
      display: block;
      max-width: 100%;
      height: auto;
    }
    .overlay {
      position: absolute;
      top: 0;
      left: 0;
      height: 100%;
      overflow: hidden;
      border-right: 2px solid #ff6b6b;
    }
    .overlay img {
      display: block;
      height: 100%;
      max-width: none;
    }
    .slider {
      position: absolute;
      top: 0;
      left: 50%;
      width: 4px;
      height: 100%;
      cursor: col-resize;
      z-index: 10;
    }
    .slider::before {
      content: '';
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      width: 32px;
      height: 32px;
      background: var(--vscode-button-background);
      border-radius: 50%;
      opacity: 0.9;
    }
    .slider::after {
      content: '\\27F7';
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: var(--vscode-button-foreground);
      font-size: 14px;
      z-index: 11;
    }
    .labels {
      display: flex;
      justify-content: space-between;
      margin-bottom: 8px;
      font-size: 12px;
      opacity: 0.7;
    }
  </style>
</head>
<body>
  <h2>Diff: ${escapeHtml(name)}</h2>
  <div class="labels">
    <span>&larr; Previous</span>
    <span>Current &rarr;</span>
  </div>
  <div class="diff-container" id="diffContainer">
    <img src="${currentUri}" alt="current" id="currentImg" />
    <div class="overlay" id="overlay">
      <img src="${previousUri}" alt="previous" id="prevImg" />
    </div>
    <div class="slider" id="slider"></div>
  </div>
  <script nonce="${nonce}">
    const container = document.getElementById('diffContainer');
    const overlay = document.getElementById('overlay');
    const slider = document.getElementById('slider');
    const currentImg = document.getElementById('currentImg');
    const prevImg = document.getElementById('prevImg');
    let isDragging = false;
    let pos = 0.5;

    function updatePosition(ratio) {
      pos = Math.max(0, Math.min(1, ratio));
      const width = container.offsetWidth;
      overlay.style.width = (pos * width) + 'px';
      slider.style.left = (pos * width) + 'px';
      prevImg.style.width = width + 'px';
    }

    currentImg.addEventListener('load', () => updatePosition(0.5));
    window.addEventListener('resize', () => updatePosition(pos));

    slider.addEventListener('mousedown', () => isDragging = true);
    container.addEventListener('mousedown', (e) => {
      isDragging = true;
      updatePosition(e.offsetX / container.offsetWidth);
    });
    window.addEventListener('mouseup', () => isDragging = false);
    window.addEventListener('mousemove', (e) => {
      if (!isDragging) return;
      const rect = container.getBoundingClientRect();
      updatePosition((e.clientX - rect.left) / rect.width);
    });
  </script>
</body>
</html>`;
}
