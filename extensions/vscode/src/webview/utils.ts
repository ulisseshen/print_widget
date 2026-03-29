import * as crypto from 'crypto';
import type * as vscode from 'vscode';

export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

export function formatDevice(device: string): string {
  return device
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

export function getNonce(): string {
  return crypto.randomBytes(16).toString('hex');
}

export function cspMeta(webview: vscode.Webview, nonce: string): string {
  return `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${webview.cspSource} data:; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">`;
}

/** Shared checkerboard transparency background CSS properties. */
export const checkerboardBg = `background-color: var(--vscode-editor-background);
      background-image:
        linear-gradient(45deg, rgba(128,128,128,0.1) 25%, transparent 25%),
        linear-gradient(-45deg, rgba(128,128,128,0.1) 25%, transparent 25%),
        linear-gradient(45deg, transparent 75%, rgba(128,128,128,0.1) 75%),
        linear-gradient(-45deg, transparent 75%, rgba(128,128,128,0.1) 75%);
      background-size: 16px 16px;
      background-position: 0 0, 0 8px, 8px -8px, -8px 0px;`;
