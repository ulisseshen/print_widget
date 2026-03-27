import * as vscode from 'vscode';
import * as path from 'path';
import { ScreenshotTreeProvider } from './tree/screenshot-tree-provider';
import { ManifestWatcher } from './manifest/manifest-watcher';
import { registerCommands } from './commands/commands';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const manifestPath = await findManifest();
  if (!manifestPath) {
    vscode.window.showInformationMessage(
      'Print Widget: No manifest.json found. Run `print_widget generate` first.',
    );
    return;
  }

  const treeProvider = new ScreenshotTreeProvider(manifestPath);

  const treeView = vscode.window.createTreeView('printWidget.screenshots', {
    treeDataProvider: treeProvider,
    showCollapseAll: true,
  });

  const watcher = new ManifestWatcher(manifestPath);
  watcher.onDidChange(() => treeProvider.refresh());

  registerCommands(context, treeProvider);

  context.subscriptions.push(treeView, watcher);
}

export function deactivate(): void {}

async function findManifest(): Promise<string | null> {
  // Search workspace for manifest.json files that look like print_widget output
  const uris = await vscode.workspace.findFiles('**/manifest.json', '**/node_modules/**', 20);

  for (const uri of uris) {
    try {
      const doc = await vscode.workspace.openTextDocument(uri);
      const content = doc.getText();
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
