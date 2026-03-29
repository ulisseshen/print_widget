import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { parseManifest, groupByFeature, Manifest, ManifestEntry } from '../manifest/manifest-parser';

describe('parseManifest', () => {
  let tmpDir: string;
  let manifestPath: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pw-test-'));
    manifestPath = path.join(tmpDir, 'manifest.json');
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('parses a valid manifest', () => {
    const data = {
      generatedAt: '2026-03-26T12:00:00.000Z',
      screenshots: [
        {
          name: 'login_page',
          type: 'page',
          file: 'login_page/iphone_15_pro.png',
          device: 'iphone_15_pro',
          width: 393,
          height: 852,
          widthPx: 1179,
          heightPx: 2556,
        },
      ],
    };
    fs.writeFileSync(manifestPath, JSON.stringify(data));

    const result = parseManifest(manifestPath);
    expect(result).not.toBeNull();
    expect(result!.generatedAt).toBe('2026-03-26T12:00:00.000Z');
    expect(result!.screenshots).toHaveLength(1);
    expect(result!.screenshots[0].name).toBe('login_page');
    expect(result!.screenshots[0].device).toBe('iphone_15_pro');
  });

  it('returns null for invalid JSON', () => {
    fs.writeFileSync(manifestPath, '{ not valid json !!!');

    const result = parseManifest(manifestPath);
    expect(result).toBeNull();
  });

  it('returns null when required fields are missing', () => {
    // Missing generatedAt
    fs.writeFileSync(manifestPath, JSON.stringify({ screenshots: [] }));
    expect(parseManifest(manifestPath)).toBeNull();

    // Missing screenshots array
    fs.writeFileSync(
      manifestPath,
      JSON.stringify({ generatedAt: '2026-01-01T00:00:00Z' }),
    );
    expect(parseManifest(manifestPath)).toBeNull();

    // screenshots is not an array
    fs.writeFileSync(
      manifestPath,
      JSON.stringify({ generatedAt: '2026-01-01T00:00:00Z', screenshots: 'not-array' }),
    );
    expect(parseManifest(manifestPath)).toBeNull();
  });

  it('returns null when file does not exist', () => {
    const result = parseManifest('/nonexistent/manifest.json');
    expect(result).toBeNull();
  });
});

describe('groupByFeature', () => {
  function entry(overrides: Partial<ManifestEntry> & { name: string; device: string }): ManifestEntry {
    return {
      type: 'page',
      file: `${overrides.name}/${overrides.device}.png`,
      width: 393,
      height: 852,
      widthPx: 1179,
      heightPx: 2556,
      ...overrides,
    };
  }

  it('groups entries by feature name', () => {
    const manifest: Manifest = {
      generatedAt: '2026-01-01T00:00:00Z',
      screenshots: [
        entry({ name: 'login', device: 'iphone_15_pro' }),
        entry({ name: 'login', device: 'pixel_7' }),
        entry({ name: 'card', device: 'iphone_15_pro', type: 'widget' }),
      ],
    };

    const groups = groupByFeature(manifest);
    expect(groups).toHaveLength(2);

    const login = groups.find((g) => g.name === 'login')!;
    expect(login.type).toBe('page');
    expect(login.states.get(null)).toHaveLength(2);

    const card = groups.find((g) => g.name === 'card')!;
    expect(card.type).toBe('widget');
    expect(card.states.get(null)).toHaveLength(1);
  });

  it('separates entries with states into state groups', () => {
    const manifest: Manifest = {
      generatedAt: '2026-01-01T00:00:00Z',
      screenshots: [
        entry({ name: 'sign_in', device: 'iphone_15_pro', state: 'empty' }),
        entry({ name: 'sign_in', device: 'iphone_15_pro', state: 'error' }),
        entry({ name: 'sign_in', device: 'pixel_7', state: 'empty' }),
      ],
    };

    const groups = groupByFeature(manifest);
    expect(groups).toHaveLength(1);

    const signIn = groups[0];
    expect(signIn.states.size).toBe(2);
    expect(signIn.states.get('empty')).toHaveLength(2);
    expect(signIn.states.get('error')).toHaveLength(1);
  });

  it('handles mixed entries with and without states', () => {
    const manifest: Manifest = {
      generatedAt: '2026-01-01T00:00:00Z',
      screenshots: [
        entry({ name: 'home', device: 'iphone_15_pro' }),
        entry({ name: 'profile', device: 'pixel_7', state: 'logged_in' }),
        entry({ name: 'profile', device: 'pixel_7', state: 'logged_out' }),
        entry({ name: 'card', device: 'iphone_15_pro', type: 'widget' }),
        entry({ name: 'card', device: 'pixel_7', type: 'widget' }),
      ],
    };

    const groups = groupByFeature(manifest);
    expect(groups).toHaveLength(3);

    const home = groups.find((g) => g.name === 'home')!;
    expect(home.states.size).toBe(1);
    expect(home.states.has(null)).toBe(true);

    const profile = groups.find((g) => g.name === 'profile')!;
    expect(profile.states.size).toBe(2);
    expect(profile.states.has('logged_in')).toBe(true);
    expect(profile.states.has('logged_out')).toBe(true);

    const card = groups.find((g) => g.name === 'card')!;
    expect(card.states.get(null)).toHaveLength(2);
  });
});
