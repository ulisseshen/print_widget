import * as vscode from 'vscode';
import { ManifestEntry } from '../manifest/manifest-parser';
import { formatDevice } from '../webview/utils';

export class FeatureNode extends vscode.TreeItem {
  constructor(
    public readonly name: string,
    public readonly type: 'page' | 'widget',
    public readonly entries: ManifestEntry[],
    collapsibleState: vscode.TreeItemCollapsibleState,
  ) {
    super(name, collapsibleState);
    this.contextValue = 'feature';
    this.description = type;
    this.iconPath = new vscode.ThemeIcon(type === 'page' ? 'browser' : 'symbol-misc');
    this.tooltip = `${name} (${type}) — ${entries.length} screenshot${entries.length > 1 ? 's' : ''}`;
  }
}

export class StateNode extends vscode.TreeItem {
  constructor(
    public readonly stateName: string,
    public readonly featureName: string,
    public readonly entries: ManifestEntry[],
  ) {
    super(stateName, vscode.TreeItemCollapsibleState.Expanded);
    this.contextValue = 'state';
    this.iconPath = new vscode.ThemeIcon('layers');
    this.description = `${entries.length} device${entries.length > 1 ? 's' : ''}`;
  }
}

export class DeviceNode extends vscode.TreeItem {
  public readonly hasReference: boolean;

  constructor(
    public readonly entry: ManifestEntry,
    public readonly imagePath: string,
    public readonly isStateChild: boolean,
    hasReference: boolean = false,
  ) {
    super(formatDevice(entry.device), vscode.TreeItemCollapsibleState.None);
    this.hasReference = hasReference;
    this.contextValue = isStateChild ? 'stateDevice' : 'device';
    this.description = `${entry.width}×${entry.height}${hasReference ? ' (ref)' : ''}`;
    this.iconPath = new vscode.ThemeIcon(getDeviceIcon(entry.device));
    this.tooltip = `${formatDevice(entry.device)}\n${entry.width}×${entry.height} (${entry.widthPx}×${entry.heightPx}px)${hasReference ? '\nReference image available' : ''}`;
    this.command = {
      command: 'printWidget.previewImage',
      title: 'Preview',
      arguments: [this],
    };
  }
}


function getDeviceIcon(device: string): string {
  if (device.includes('ipad') || device.includes('tablet')) return 'device-mobile';
  if (device.includes('iphone') || device.includes('pixel') || device.includes('samsung')) return 'device-mobile';
  return 'device-desktop';
}
