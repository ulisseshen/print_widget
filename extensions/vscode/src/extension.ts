import * as vscode from 'vscode';
import * as fs from 'fs';
import { ScreenshotTreeProvider } from './tree/screenshot-tree-provider';
import { ManifestWatcher } from './manifest/manifest-watcher';
import { registerCommands } from './commands/commands';
import { PreviewPanel } from './webview/preview-panel';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const manifestPath = await findManifest();

  const treeProvider = new ScreenshotTreeProvider(manifestPath ?? '');

  const treeView = vscode.window.createTreeView('printWidget.screenshots', {
    treeDataProvider: treeProvider,
    showCollapseAll: true,
  });

  registerCommands(context, treeProvider);

  context.subscriptions.push(treeView);

  if (manifestPath) {
    const watcher = new ManifestWatcher(manifestPath);
    let debounceTimer: ReturnType<typeof setTimeout> | undefined;
    watcher.onDidChange(() => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        treeProvider.refresh();
        PreviewPanel.refreshAll();
      }, 500);
    });
    context.subscriptions.push(watcher);
  }
}

export function deactivate(): void {}

async function findManifest(): Promise<string | null> {
  const uris = await vscode.workspace.findFiles('**/manifest.json', '**/node_modules/**', 20);

  for (const uri of uris) {
    try {
      const content = fs.readFileSync(uri.fsPath, 'utf-8');
      const data = JSON.parse(content);
      if (data.generatedAt && Array.isArray(data.screenshots)) {
        return uri.fsPath;
      }
    } catch {
      // not a valid manifest, skip
    }
  }

  return null;
}
