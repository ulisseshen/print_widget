import * as vscode from 'vscode';
import * as path from 'path';

export class ManifestWatcher implements vscode.Disposable {
  private watcher: vscode.FileSystemWatcher | undefined;
  private readonly _onDidChange = new vscode.EventEmitter<vscode.Uri>();
  readonly onDidChange = this._onDidChange.event;

  constructor(private manifestPath: string) {
    const dir = path.dirname(manifestPath);
    const pattern = new vscode.RelativePattern(dir, '**');
    this.watcher = vscode.workspace.createFileSystemWatcher(pattern);

    this.watcher.onDidChange((uri) => {
      if (uri.fsPath === manifestPath || uri.fsPath.endsWith('.png')) {
        this._onDidChange.fire(uri);
      }
    });
    this.watcher.onDidCreate((uri) => {
      if (uri.fsPath.endsWith('.png') || uri.fsPath.endsWith('manifest.json')) {
        this._onDidChange.fire(uri);
      }
    });
    this.watcher.onDidDelete((uri) => {
      this._onDidChange.fire(uri);
    });
  }

  dispose(): void {
    this.watcher?.dispose();
    this._onDidChange.dispose();
  }
}
