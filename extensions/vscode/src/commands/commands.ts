import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { ScreenshotTreeProvider } from '../tree/screenshot-tree-provider';
import { DeviceNode, FeatureNode, StateNode } from '../tree/tree-items';
import { PreviewPanel } from '../webview/preview-panel';
import { ComparisonPanel } from '../webview/comparison-panel';
import { DiffPanel } from '../webview/diff-panel';
import { FigmaComparisonPanel } from '../webview/figma-comparison-panel';
import { resolveImagePath } from '../manifest/manifest-parser';
import { SourceLinker } from '../source-linker/source-linker';

export function registerCommands(
  context: vscode.ExtensionContext,
  treeProvider: ScreenshotTreeProvider,
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('printWidget.refresh', () => {
      treeProvider.refresh();
    }),

    vscode.commands.registerCommand('printWidget.previewImage', (node: DeviceNode) => {
      if (!node || !node.entry) return;
      PreviewPanel.show(context, node.entry, node.imagePath);
    }),

    vscode.commands.registerCommand('printWidget.compareDevices', (node: FeatureNode | StateNode) => {
      if (node instanceof FeatureNode) {
        const entries = treeProvider.getEntriesForFeature(node.name);
        ComparisonPanel.show(context, node.name, entries, treeProvider.getManifestPath());
      } else if (node instanceof StateNode) {
        ComparisonPanel.show(context, `${node.featureName} (${node.stateName})`, node.entries, treeProvider.getManifestPath());
      }
    }),

    vscode.commands.registerCommand('printWidget.diffWithPrevious', async (node: DeviceNode) => {
      if (!node || !node.entry) return;
      await DiffPanel.show(context, node.entry, node.imagePath);
    }),

    vscode.commands.registerCommand('printWidget.compareWithFigma', async (node: DeviceNode) => {
      if (!node || !node.entry) return;
      await FigmaComparisonPanel.show(context, node.entry, node.imagePath);
    }),

    vscode.commands.registerCommand('printWidget.goToSource', async (node: FeatureNode) => {
      if (!node) return;
      const manifestPath = treeProvider.getManifestPath();
      const linker = new SourceLinker(manifestPath);
      const location = await linker.findDefinition(node.name);
      if (location) {
        const doc = await vscode.workspace.openTextDocument(location.file);
        await vscode.window.showTextDocument(doc, {
          selection: new vscode.Range(location.line, 0, location.line, 0),
        });
      } else {
        vscode.window.showInformationMessage(`Could not find definition for "${node.name}"`);
      }
    }),

    vscode.commands.registerCommand('printWidget.selectManifest', async () => {
      const uris = await vscode.window.showOpenDialog({
        canSelectMany: false,
        filters: { JSON: ['json'] },
        title: 'Select manifest.json',
      });
      if (uris && uris.length > 0) {
        treeProvider.setManifestPath(uris[0].fsPath);
      }
    }),
  );
}
