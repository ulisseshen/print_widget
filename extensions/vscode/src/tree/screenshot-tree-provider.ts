import * as vscode from 'vscode';
import { parseManifest, groupByFeature, resolveImagePath, FeatureGroup, ManifestEntry } from '../manifest/manifest-parser';
import { FeatureNode, StateNode, DeviceNode } from './tree-items';
import { FigmaComparisonPanel } from '../webview/figma-comparison-panel';

export class ScreenshotTreeProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<vscode.TreeItem | undefined>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private features: FeatureGroup[] = [];

  constructor(private manifestPath: string) {
    this.reload();
  }

  refresh(): void {
    this.reload();
    this._onDidChangeTreeData.fire(undefined);
  }

  setManifestPath(manifestPath: string): void {
    this.manifestPath = manifestPath;
    this.refresh();
  }

  private reload(): void {
    const manifest = parseManifest(this.manifestPath);
    this.features = manifest ? groupByFeature(manifest) : [];
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: vscode.TreeItem): vscode.TreeItem[] {
    if (!element) {
      return this.features.map((f) => {
        const allEntries = Array.from(f.states.values()).flat();
        const hasStates = f.states.size > 1 || !f.states.has(null);
        const state = hasStates || allEntries.length > 1
          ? vscode.TreeItemCollapsibleState.Collapsed
          : vscode.TreeItemCollapsibleState.None;

        const node = new FeatureNode(f.name, f.type, allEntries, state);
        if (allEntries.length === 1 && !hasStates) {
          const entry = allEntries[0];
          const imgPath = resolveImagePath(this.manifestPath, entry);
          node.command = {
            command: 'printWidget.previewImage',
            title: 'Preview',
            arguments: [this.createDeviceNode(entry, imgPath, false)],
          };
        }
        return node;
      });
    }

    if (element instanceof FeatureNode) {
      const feature = this.features.find((f) => f.name === element.name);
      if (!feature) return [];

      const hasStates = feature.states.size > 1 || !feature.states.has(null);
      if (hasStates) {
        return Array.from(feature.states.entries()).map(([state, entries]) => {
          if (state === null) {
            return entries.map((e) => this.createDeviceNode(e, resolveImagePath(this.manifestPath, e), false));
          }
          return new StateNode(state, feature.name, entries);
        }).flat();
      }

      const entries = feature.states.get(null) ?? [];
      return entries.map((e) => this.createDeviceNode(e, resolveImagePath(this.manifestPath, e), false));
    }

    if (element instanceof StateNode) {
      return element.entries.map(
        (e) => this.createDeviceNode(e, resolveImagePath(this.manifestPath, e), true),
      );
    }

    return [];
  }

  private createDeviceNode(entry: ManifestEntry, imgPath: string, isStateChild: boolean): DeviceNode {
    const hasRef = FigmaComparisonPanel.hasReference(imgPath, entry);
    return new DeviceNode(entry, imgPath, isStateChild, hasRef);
  }

  getEntries(): ManifestEntry[] {
    return this.features.flatMap((f) => Array.from(f.states.values()).flat());
  }

  getEntriesForFeature(name: string): ManifestEntry[] {
    const feature = this.features.find((f) => f.name === name);
    if (!feature) return [];
    return Array.from(feature.states.values()).flat();
  }

  getManifestPath(): string {
    return this.manifestPath;
  }
}
