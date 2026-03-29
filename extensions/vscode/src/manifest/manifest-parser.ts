import * as fs from 'fs';
import * as path from 'path';

export interface ManifestEntry {
  name: string;
  type: 'page' | 'widget';
  file: string;
  device: string;
  width: number;
  height: number;
  widthPx: number;
  heightPx: number;
  state?: string;
}

export interface Manifest {
  generatedAt: string;
  screenshots: ManifestEntry[];
}

export interface FeatureGroup {
  name: string;
  type: 'page' | 'widget';
  states: Map<string | null, ManifestEntry[]>;
}

export function parseManifest(manifestPath: string): Manifest | null {
  try {
    const content = fs.readFileSync(manifestPath, 'utf-8');
    const data = JSON.parse(content);
    if (!data.generatedAt || !Array.isArray(data.screenshots)) {
      return null;
    }
    return data as Manifest;
  } catch {
    return null;
  }
}

export function groupByFeature(manifest: Manifest): FeatureGroup[] {
  const map = new Map<string, FeatureGroup>();

  for (const entry of manifest.screenshots) {
    let group = map.get(entry.name);
    if (!group) {
      group = { name: entry.name, type: entry.type, states: new Map() };
      map.set(entry.name, group);
    }
    const stateKey = entry.state ?? null;
    const entries = group.states.get(stateKey) ?? [];
    entries.push(entry);
    group.states.set(stateKey, entries);
  }

  return Array.from(map.values());
}

export function resolveImagePath(manifestPath: string, entry: ManifestEntry): string {
  const projectRoot = findProjectRoot(manifestPath);
  return path.join(projectRoot, entry.file);
}

function findProjectRoot(manifestPath: string): string {
  let dir = path.dirname(manifestPath);
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }
  return path.dirname(manifestPath);
}
