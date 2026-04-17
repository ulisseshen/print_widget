// Generic design extractor — screenshot, section crops, and token extraction per state.
//
// Usage: node extract.mjs <states.json> [--theme=<theme-ref.json>]
//
// states.json schema:
// {
//   "url": "https://example.com/",         // base URL (optional if every state has its own goto)
//   "viewport": { "width": 1440, "height": 2400 },
//   "deviceScaleFactor": 2,
//   "output": "/tmp/extract-design",
//   "states": [
//     {
//       "name": "initial",
//       "steps": []                          // no actions — captures base URL
//     },
//     {
//       "name": "foco-na-meta",
//       "steps": [
//         { "action": "click", "selector": "text=Minha Home" },
//         { "action": "wait", "ms": 500 },
//         { "action": "click", "selector": "text=Foco na Meta" },
//         { "action": "wait", "ms": 1000 }
//       ]
//     },
//     {
//       "name": "settings-page",
//       "steps": [
//         { "action": "goto", "url": "https://example.com/settings" }
//       ]
//     }
//   ]
// }
//
// Action types:
//   { action: "goto",  url: string }
//   { action: "click", selector: string, nth?: number }   (playwright selector)
//   { action: "fill",  selector: string, text: string }
//   { action: "wait",  ms: number }
//   { action: "scroll", y: number }
//   { action: "press", key: string }
//
// Output per state in <output>/<NN-name>/:
//   fullpage.png         — full page screenshot
//   <NN-slug>.png        — one crop per detected section/group
//   <NN-slug>_spec.json  — per-element structural spec for each crop (DOM tree
//                          with computed styles, typography, icons — the IR
//                          that scaffold codegen consumes)
//   _index.json          — bounding boxes of each crop (+ spec filename)
//   tokens.json          — raw design tokens (colors, typography, spacing, effects, iconography)
//   _DESIGN.md           — human-readable token summary mapped to theme (if --theme given)
//
// Top-level states.json keys:
//   chromePurge: string[]   CSS selectors removed from DOM before screenshots
//                           (per-state override via state.chromePurge).
//                           Use to strip platform chrome like Lovable's footer,
//                           cookie banners, or PWA install prompts.

import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
const configPath = args.find((a) => !a.startsWith('--'));
const themeArg = args.find((a) => a.startsWith('--theme='));
const themePath = themeArg ? themeArg.slice('--theme='.length) : null;

if (!configPath) {
  console.error('Usage: node extract.mjs <states.json> [--theme=<theme-ref.json>]');
  process.exit(2);
}

const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
const theme = themePath ? JSON.parse(await fs.readFile(themePath, 'utf8')) : null;
const OUT = config.output || '/tmp/extract-design';
const VIEWPORT = config.viewport || { width: 1440, height: 2400 };
const DPR = config.deviceScaleFactor || 2;

const slug = (s) =>
  (s || '')
    .toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 50) || 'state';

// ============================================================================
// Page actions
// ============================================================================

async function runSteps(page, steps) {
  for (const step of steps || []) {
    switch (step.action) {
      case 'goto':
        await page.goto(step.url, { waitUntil: 'networkidle', timeout: 60_000 });
        break;
      case 'click': {
        const loc = step.nth != null
          ? page.locator(step.selector).nth(step.nth)
          : page.locator(step.selector).first();
        await loc.click({ timeout: 10_000 });
        break;
      }
      case 'fill':
        await page.locator(step.selector).first().fill(step.text);
        break;
      case 'wait':
        await page.waitForTimeout(step.ms || 500);
        break;
      case 'scroll':
        await page.evaluate((y) => window.scrollTo(0, y), step.y || 0);
        break;
      case 'press':
        await page.keyboard.press(step.key);
        break;
      default:
        console.warn(`  ! unknown action: ${step.action}`);
    }
  }
}

// ============================================================================
// Section detection (in-browser)
// ============================================================================

function collectSectionsInBrowser() {
  const main = document.querySelector('main') || document.body;
  const vw = window.innerWidth;

  const isVisible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 200 || r.height < 60) return false;
    const cs = getComputedStyle(el);
    return cs.visibility !== 'hidden' && cs.display !== 'none' && parseFloat(cs.opacity) > 0.01;
  };

  // Walk down while root has only 1 meaningful child (skip generic wrappers)
  let root = main;
  while (true) {
    const kids = [...root.children].filter(isVisible);
    if (kids.length === 1) root = kids[0];
    else break;
  }

  let sections = [...root.children].filter(isVisible);
  if (sections.length <= 2 && sections[0]) {
    const deeper = [...sections[0].children].filter(isVisible);
    if (deeper.length >= 3) sections = deeper;
  }

  sections = sections.filter((el) => {
    const r = el.getBoundingClientRect();
    return r.width >= vw * 0.3 && r.height >= 60;
  });

  const final = sections.map((el) => {
    const r = el.getBoundingClientRect();
    const text = (el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 80);
    return {
      x: Math.max(0, r.left),
      y: Math.max(0, r.top),
      w: r.width,
      h: r.height,
      text,
      tag: el.tagName.toLowerCase(),
    };
  });
  final.sort((a, b) => a.y - b.y || a.x - b.x);
  return final;
}

// ============================================================================
// Token extraction (in-browser)
// ============================================================================

function extractTokensInBrowser() {
  const main = document.querySelector('main') || document.body;
  const nodes = [...main.querySelectorAll('*')];

  const m = {
    color: new Map(), bg: new Map(), border: new Map(), gradient: new Map(),
    family: new Map(), size: new Map(), weight: new Map(), lineHeight: new Map(),
    radius: new Map(), shadow: new Map(),
    padding: new Map(), gap: new Map(),
  };
  const bump = (map, key) => { if (key) map.set(key, (map.get(key) || 0) + 1); };
  const norm = (c) => (!c || c === 'rgba(0, 0, 0, 0)' || c === 'transparent') ? null : c;

  // Parse a CSS background-image string and extract each color stop.
  // Handles linear-gradient, radial-gradient, conic-gradient with hex/rgb(a) stops.
  // Returns the full gradient string (for the gradient map) AND an array of
  // individual stop colors (so they're counted as regular background colors).
  const parseGradient = (bgImage) => {
    if (!bgImage || bgImage === 'none') return null;
    if (!/^(linear|radial|conic)-gradient/.test(bgImage)) return null;
    const stops = [];
    // Match rgb/rgba first so the numbers inside don't leak into the hex regex
    const rgbaRe = /rgba?\([^)]+\)/g;
    let match;
    while ((match = rgbaRe.exec(bgImage))) stops.push(match[0]);
    const cleaned = bgImage.replace(rgbaRe, '');
    const hexRe = /#[0-9a-fA-F]{3,8}\b/g;
    while ((match = hexRe.exec(cleaned))) stops.push(match[0]);
    return { full: bgImage, stops };
  };

  for (const el of nodes) {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) continue;

    const hasText = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim().length > 0);
    if (hasText) {
      bump(m.color, norm(cs.color));
      bump(m.family, cs.fontFamily.split(',')[0].trim().replace(/["']/g, ''));
      bump(m.size, cs.fontSize);
      bump(m.weight, cs.fontWeight);
      bump(m.lineHeight, cs.lineHeight);
    }
    bump(m.bg, norm(cs.backgroundColor));
    const grad = parseGradient(cs.backgroundImage);
    if (grad) {
      bump(m.gradient, grad.full);
      for (const stop of grad.stops) bump(m.bg, stop);
    }
    if (parseFloat(cs.borderTopWidth) > 0) bump(m.border, norm(cs.borderTopColor));
    if (parseFloat(cs.borderRadius) > 0) bump(m.radius, `${parseFloat(cs.borderRadius)}px`);
    if (cs.boxShadow && cs.boxShadow !== 'none') bump(m.shadow, cs.boxShadow);
    if (el.children.length > 0) {
      for (const s of ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft']) {
        const v = parseFloat(cs[s]);
        if (v > 0) bump(m.padding, `${v}px`);
      }
      const gap = parseFloat(cs.gap);
      if (gap > 0) bump(m.gap, `${gap}px`);
    }
  }

  // ----- Iconography detection -----
  const icons = [];
  const libsSet = new Set();

  const detectLibrary = (cls) => {
    if (!cls) return 'unknown';
    const c = cls.trim();
    if (/^lucide(\s|-|$)/.test(c)) return 'lucide';
    if (/^ph(\s|-|$)/.test(c)) return 'phosphor';
    if (/heroicon/.test(c)) return 'heroicons';
    return 'unknown';
  };

  const extractIconName = (cls) => {
    if (!cls) return null;
    const words = cls.trim().split(/\s+/);
    // Prefer the second word (e.g. "lucide lucide-globe" -> "lucide-globe" -> "globe")
    const target = words[1] || words[0] || '';
    // Strip known prefixes
    const stripped = target.replace(/^(lucide-|ph-|heroicon-|heroicons-)/, '');
    return stripped || null;
  };

  for (const svg of document.querySelectorAll('svg')) {
    const r = svg.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) continue;

    const cls = svg.getAttribute('class') || '';
    let library = detectLibrary(cls);
    let name = extractIconName(cls);

    // Walk <use> elements referencing sprite IDs (e.g. xlink:href="#icon-globe")
    const useEls = [...svg.querySelectorAll('use')];
    if (useEls.length > 0 && !name) {
      for (const useEl of useEls) {
        const href =
          useEl.getAttribute('href') ||
          useEl.getAttribute('xlink:href') ||
          '';
        if (href.startsWith('#')) {
          const id = href.slice(1);
          // e.g. "icon-globe" -> "globe"; "lucide-globe" -> "globe"
          const stripped = id.replace(/^(icon-|lucide-|ph-|heroicon-|heroicons-)/, '');
          if (!name) name = stripped;
          if (library === 'unknown') {
            if (/^lucide/.test(id)) library = 'lucide';
            else if (/^ph/.test(id)) library = 'phosphor';
            else if (/heroicon/.test(id)) library = 'heroicons';
            else if (/^icon-/.test(id)) library = 'sprite';
          }
        }
      }
    }

    if (!name && cls) name = cls.trim().split(/\s+/)[0] || null;
    if (!name) continue;

    libsSet.add(library);
    icons.push({
      library,
      name,
      at: { x: Math.round(r.left), y: Math.round(r.top) },
      size: { w: Math.round(r.width), h: Math.round(r.height) },
    });
  }

  const topN = (map, n = 15) => [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);
  return {
    colors: { text: topN(m.color), background: topN(m.bg), border: topN(m.border), gradient: topN(m.gradient, 10) },
    typography: { families: topN(m.family, 6), sizes: topN(m.size), weights: topN(m.weight, 8), lineHeights: topN(m.lineHeight, 10) },
    spacing: { padding: topN(m.padding), gap: topN(m.gap) },
    effects: { radii: topN(m.radius, 10), shadows: topN(m.shadow, 6) },
    iconography: { libraries: [...libsSet], icons },
  };
}

// ============================================================================
// Per-crop design spec extraction (in-browser)
// ============================================================================
//
// Walks the DOM subtree intersecting a crop's bounds and emits a structured
// tree: per-element bounds, computed styles (only non-default), typography
// for text leaves, and icon metadata + outerHTML for SVGs. This is the IR
// that downstream tooling (scaffold codegen, agents reading exact values
// instead of guessing from pixels) consumes.
//
// The function is serialized into the page context by Playwright, so it
// cannot reference anything outside its own scope.

function extractStructureInBrowser(clip) {
  const DEPTH_CAP = 12;
  const { x: cx, y: cy, w: cw, h: ch } = clip;

  const intersects = (r) =>
    r.right > cx && r.left < cx + cw && r.bottom > cy && r.top < cy + ch;

  const hasDirectText = (el) =>
    [...el.childNodes].some(
      (n) => n.nodeType === 3 && n.textContent.trim().length > 0,
    );

  const pxNum = (v) => {
    if (v == null) return null;
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : null;
  };

  const normColor = (c) =>
    !c || c === 'rgba(0, 0, 0, 0)' || c === 'transparent' ? null : c;

  const detectIcon = (svg) => {
    const cls = svg.getAttribute('class') || '';
    let library = 'unknown';
    let name = null;

    if (/(^|\s)lucide(\s|-|$)/.test(cls)) library = 'lucide';
    else if (/(^|\s)ph(\s|-|$)/.test(cls)) library = 'phosphor';
    else if (/heroicon/.test(cls)) library = 'heroicons';

    const words = cls.trim().split(/\s+/).filter(Boolean);
    const target = words[1] || words[0] || '';
    const stripped = target.replace(
      /^(lucide-|ph-|heroicon-|heroicons-)/,
      '',
    );
    if (stripped) name = stripped;

    if (!name) {
      for (const use of svg.querySelectorAll('use')) {
        const href =
          use.getAttribute('href') || use.getAttribute('xlink:href') || '';
        if (href.startsWith('#')) {
          const id = href.slice(1);
          const stripped = id.replace(
            /^(icon-|lucide-|ph-|heroicon-|heroicons-)/,
            '',
          );
          if (stripped) {
            name = stripped;
            if (library === 'unknown') {
              if (/^lucide/.test(id)) library = 'lucide';
              else if (/^ph/.test(id)) library = 'phosphor';
              else if (/heroicon/.test(id)) library = 'heroicons';
              else if (/^icon-/.test(id)) library = 'sprite';
            }
            break;
          }
        }
      }
    }
    return name ? { library, name } : null;
  };

  function walk(el, depth) {
    if (depth > DEPTH_CAP) return null;

    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return null;
    if (parseFloat(cs.opacity) <= 0.01) return null;

    // display: contents — element produces no box; flatten children up.
    if (cs.display === 'contents') {
      const kids = [];
      for (const child of el.children) {
        const w = walk(child, depth + 1);
        if (!w) continue;
        Array.isArray(w) ? kids.push(...w) : kids.push(w);
      }
      return kids.length > 0 ? kids : null;
    }

    const r = el.getBoundingClientRect();
    if (r.width < 0.5 || r.height < 0.5) return null;
    if (!intersects(r)) return null;

    const tag = el.tagName.toLowerCase();
    const isSvg = tag === 'svg';
    const isText = !isSvg && hasDirectText(el);

    const node = {
      tag,
      bounds: {
        x: Math.round(r.left - cx),
        y: Math.round(r.top - cy),
        w: Math.round(r.width),
        h: Math.round(r.height),
      },
    };

    // Styles — only capture non-default values so specs stay readable.
    const styles = {};

    const display = cs.display;
    if (display && display !== 'block' && display !== 'inline') {
      styles.display = display;
      if (display === 'flex' || display === 'inline-flex') {
        if (cs.flexDirection && cs.flexDirection !== 'row')
          styles.flexDirection = cs.flexDirection;
        if (cs.alignItems && cs.alignItems !== 'normal' && cs.alignItems !== 'stretch')
          styles.alignItems = cs.alignItems;
        if (cs.justifyContent && cs.justifyContent !== 'normal')
          styles.justifyContent = cs.justifyContent;
        const gap = pxNum(cs.gap);
        if (gap && gap > 0) styles.gap = gap;
        if (cs.flexWrap && cs.flexWrap !== 'nowrap')
          styles.flexWrap = cs.flexWrap;
      }
    }

    const flexGrow = pxNum(cs.flexGrow);
    if (flexGrow && flexGrow > 0) styles.flexGrow = flexGrow;

    const pad = {
      top: pxNum(cs.paddingTop) || 0,
      right: pxNum(cs.paddingRight) || 0,
      bottom: pxNum(cs.paddingBottom) || 0,
      left: pxNum(cs.paddingLeft) || 0,
    };
    if (pad.top || pad.right || pad.bottom || pad.left) styles.padding = pad;

    const mgn = {
      top: pxNum(cs.marginTop) || 0,
      right: pxNum(cs.marginRight) || 0,
      bottom: pxNum(cs.marginBottom) || 0,
      left: pxNum(cs.marginLeft) || 0,
    };
    if (mgn.top || mgn.right || mgn.bottom || mgn.left) styles.margin = mgn;

    const bgColor = normColor(cs.backgroundColor);
    if (bgColor) styles.backgroundColor = bgColor;

    if (cs.backgroundImage && cs.backgroundImage !== 'none')
      styles.backgroundImage = cs.backgroundImage;

    // Border radius: preserve percent (e.g. 50% for circles) vs px.
    const radiusRaw = cs.borderRadius;
    if (radiusRaw && radiusRaw !== '0px') {
      const radiusNum = pxNum(radiusRaw);
      styles.borderRadius =
        radiusRaw.includes('%') || radiusNum == null ? radiusRaw : radiusNum;
    }

    const bw = pxNum(cs.borderTopWidth);
    if (bw && bw > 0) {
      styles.border = {
        width: bw,
        color: normColor(cs.borderTopColor),
        style: cs.borderTopStyle,
      };
    }

    if (cs.boxShadow && cs.boxShadow !== 'none')
      styles.boxShadow = cs.boxShadow;

    const position = cs.position;
    if (position && position !== 'static') {
      styles.position = position;
      for (const side of ['top', 'right', 'bottom', 'left']) {
        const v = cs[side];
        if (v && v !== 'auto') styles[side] = v;
      }
    }

    if (cs.overflow && cs.overflow !== 'visible')
      styles.overflow = cs.overflow;
    if (cs.transform && cs.transform !== 'none')
      styles.transform = cs.transform;
    if (cs.zIndex && cs.zIndex !== 'auto') styles.zIndex = cs.zIndex;
    if (cs.opacity && parseFloat(cs.opacity) < 1)
      styles.opacity = parseFloat(cs.opacity);

    // Typography — capture on text leaves only.
    if (isText) {
      node.text = (el.innerText || '').trim().slice(0, 500);
      const typography = {
        fontFamily: cs.fontFamily.split(',')[0].trim().replace(/["']/g, ''),
        fontSize: pxNum(cs.fontSize),
        fontWeight: parseInt(cs.fontWeight, 10) || cs.fontWeight,
        lineHeight: pxNum(cs.lineHeight) || cs.lineHeight,
        color: normColor(cs.color),
      };
      if (cs.letterSpacing && cs.letterSpacing !== 'normal')
        typography.letterSpacing = cs.letterSpacing;
      if (cs.textAlign && cs.textAlign !== 'start')
        typography.textAlign = cs.textAlign;
      if (cs.textTransform && cs.textTransform !== 'none')
        typography.textTransform = cs.textTransform;
      node.typography = typography;

      if (cs.textOverflow === 'ellipsis') styles.textOverflow = 'ellipsis';
    }

    if (Object.keys(styles).length > 0) node.styles = styles;

    // SVG — capture icon metadata + outerHTML, do not recurse into paths.
    if (isSvg) {
      const icon = detectIcon(el);
      if (icon) node.icon = icon;
      node.svgHtml = el.outerHTML;
      return node;
    }

    // Recurse into element children (text nodes are folded into this node).
    const kids = [];
    for (const child of el.children) {
      const w = walk(child, depth + 1);
      if (!w) continue;
      Array.isArray(w) ? kids.push(...w) : kids.push(w);
    }
    if (kids.length > 0) node.children = kids;

    return node;
  }

  // Pick a root: start from the element at the crop center, walk up while
  // the parent still fits within ~1.5x the crop (so we don't grab the whole
  // page) and doesn't shrink to a subtree smaller than the crop itself.
  const cxCenter = cx + cw / 2;
  const cyCenter = cy + ch / 2;
  let centerEl = document.elementFromPoint(cxCenter, cyCenter);
  if (!centerEl) {
    for (const [dx, dy] of [[0, -20], [0, 20], [-20, 0], [20, 0], [0, -60], [0, 60]]) {
      centerEl = document.elementFromPoint(cxCenter + dx, cyCenter + dy);
      if (centerEl) break;
    }
  }

  let root = centerEl || document.body;
  while (
    root.parentElement &&
    root.parentElement !== document.documentElement &&
    root.parentElement !== document.body
  ) {
    const pr = root.parentElement.getBoundingClientRect();
    // Parent is bigger than crop by >1.5x — stop; we've covered the crop.
    if (pr.width > cw * 1.5 || pr.height > ch * 1.5) break;
    root = root.parentElement;
  }

  const result = walk(root, 0);
  if (!result) return null;
  return Array.isArray(result) ? result[0] || null : result;
}

// ============================================================================
// Chrome purge (remove platform UI from DOM before screenshots)
// ============================================================================

async function applyChromePurge(page, selectors) {
  if (!selectors || selectors.length === 0) return;
  await page.evaluate((sels) => {
    for (const sel of sels) {
      try {
        document.querySelectorAll(sel).forEach((el) => el.remove());
      } catch (_) {
        // Invalid selector — skip silently.
      }
    }
  }, selectors);
}

// ============================================================================
// Theme mapping (uses theme-ref.json if provided)
// ============================================================================

function rgbToHex(rgb) {
  if (!rgb) return null;
  const m = rgb.match(/rgba?\(([^)]+)\)/);
  if (!m) return null;
  const [r, g, b, a = 1] = m[1].split(',').map((s) => parseFloat(s.trim()));
  const hex = '#' + [r, g, b].map((x) => Math.round(x).toString(16).padStart(2, '0').toUpperCase()).join('');
  return { hex, a };
}

function hexDistance(a, b) {
  const p = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const [ar, ag, ab] = p(a);
  const [br, bg, bb] = p(b);
  return Math.sqrt((ar - br) ** 2 + (ag - bg) ** 2 + (ab - bb) ** 2);
}

function matchColor(rgb, theme) {
  const c = rgbToHex(rgb);
  if (!c || !theme) return { hex: c?.hex, alpha: c?.a, raw: rgb };
  const target = c.hex.toUpperCase();
  if (theme.semanticOverrides?.[target]) {
    const o = theme.semanticOverrides[target];
    return { hex: target, alpha: c.a, token: o.token, role: o.role, override: true };
  }
  if (theme.palette?.[target]) {
    return { hex: target, alpha: c.a, token: theme.palette[target], exact: true };
  }
  let best = null;
  for (const [pal, name] of Object.entries(theme.palette || {})) {
    if (pal.startsWith('__')) continue;
    const d = hexDistance(target, pal);
    if (!best || d < best.d) best = { d, pal, name };
  }
  return {
    hex: target, alpha: c.a,
    near: best && best.d < 20 ? `${best.name} (${best.pal}, Δ${best.d.toFixed(0)})` : null,
    nearest: best,
  };
}

function buildDesignMd(stateName, tokens, theme) {
  const fmtColor = ([rgb, count]) => {
    const m = matchColor(rgb, theme);
    if (!m.hex) return `- \`${rgb}\` · ${count}×`;
    const alpha = m.alpha < 1 ? ` (α ${m.alpha})` : '';
    const badge = m.override ? '🎨' : m.exact ? '✅' : m.near ? '⚠️' : '❌';
    const tok = m.token ? ` → **${m.token}**` : m.near ? ` → ${m.near}` : ' → _new color_';
    return `- ${badge} \`${m.hex}${alpha}\`${tok} · ${count}×`;
  };

  const lines = [];
  lines.push(`# ${stateName} — Design Tokens`);
  lines.push('');
  if (theme) {
    lines.push(`Mapped to theme \`${theme.name}\`.`);
    lines.push('');
    lines.push('**Legend:** ✅ exact match · 🎨 poetic license → forced token · ⚠️ close · ❌ new');
    lines.push('');
  }

  lines.push('## Colors — Text');
  lines.push(tokens.colors.text.map(fmtColor).join('\n'));
  lines.push('\n## Colors — Background');
  lines.push(tokens.colors.background.map(fmtColor).join('\n'));
  lines.push('\n## Colors — Borders');
  lines.push(tokens.colors.border.map(fmtColor).join('\n') || '- _(no borders)_');

  lines.push('\n## Typography');
  lines.push(`**Family:** ${tokens.typography.families.map(([v]) => `\`${v}\``).join(', ') || '—'}`);
  lines.push('\n**Sizes:**');
  lines.push(tokens.typography.sizes.map(([v, c]) => `- \`${v}\` · ${c}×`).join('\n'));
  lines.push('\n**Weights:**');
  lines.push(tokens.typography.weights.map(([v, c]) => `- \`${v}\` · ${c}×`).join('\n'));

  lines.push('\n## Spacing');
  lines.push('**Padding:**');
  lines.push(tokens.spacing.padding.map(([v, c]) => `- \`${v}\` · ${c}×`).join('\n'));
  lines.push('\n**Gap:**');
  lines.push(tokens.spacing.gap.map(([v, c]) => `- \`${v}\` · ${c}×`).join('\n') || '- _(no gap)_');

  lines.push('\n## Effects');
  lines.push('**Radius:**');
  lines.push(tokens.effects.radii.map(([v, c]) => `- \`${v}\` · ${c}×`).join('\n'));
  lines.push('\n**Shadow:**');
  lines.push(tokens.effects.shadows.map(([v, c]) => `- \`${v}\` · ${c}×`).join('\n') || '- _(no shadows)_');

  // ----- Iconography section -----
  lines.push('\n## Iconography');
  const icono = tokens.iconography || { libraries: [], icons: [] };
  if (!icono.icons || icono.icons.length === 0) {
    lines.push('- _(no SVG icons detected)_');
  } else {
    lines.push(`**Libraries detected:** ${icono.libraries.map((l) => `\`${l}\``).join(', ') || '—'}`);
    lines.push('');
    const byLib = new Map();
    for (const ic of icono.icons) {
      if (!byLib.has(ic.library)) byLib.set(ic.library, new Map());
      const inner = byLib.get(ic.library);
      inner.set(ic.name, (inner.get(ic.name) || 0) + 1);
    }
    for (const [lib, inner] of byLib.entries()) {
      lines.push(`**${lib}** (${[...inner.values()].reduce((a, b) => a + b, 0)} total)`);
      const sorted = [...inner.entries()].sort((a, b) => b[1] - a[1]);
      for (const [name, count] of sorted) {
        lines.push(`- \`${name}\` · ${count}×`);
      }
      lines.push('');
    }
  }

  return lines.join('\n') + '\n';
}

// ============================================================================
// Main
// ============================================================================

async function captureState(page, state, index) {
  const stateName = `${String(index + 1).padStart(2, '0')}-${slug(state.name)}`;
  const dir = path.join(OUT, stateName);
  await fs.mkdir(dir, { recursive: true });
  console.log(`→ [${index + 1}] ${state.name}`);

  // Execute steps to reach this state
  await runSteps(page, state.steps);
  await page.waitForTimeout(state.settleMs || 800);

  // Strip platform chrome (Lovable footer, cookie banners, PWA prompts).
  // State-level selectors override config-level.
  const purgeSelectors = state.chromePurge ?? config.chromePurge ?? [];
  await applyChromePurge(page, purgeSelectors);

  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(200);

  // Full page screenshot
  await page.screenshot({ path: path.join(dir, 'fullpage.png'), fullPage: true });

  // Section crops + per-crop structural spec
  const sections = await page.evaluate(collectSectionsInBrowser);
  const cropIndex = [];
  let specCount = 0;
  for (let i = 0; i < sections.length; i++) {
    const c = sections[i];
    const fname = `${String(i + 1).padStart(2, '0')}-${slug(c.text)}.png`;
    const specName = fname.replace(/\.png$/, '_spec.json');
    try {
      await page.screenshot({
        path: path.join(dir, fname),
        clip: { x: c.x, y: c.y, width: c.w, height: c.h },
      });

      let spec = null;
      try {
        spec = await page.evaluate(extractStructureInBrowser, {
          x: c.x, y: c.y, w: c.w, h: c.h,
        });
      } catch (specErr) {
        console.warn(`  spec failed for ${fname}: ${specErr.message}`);
      }

      const entry = { file: fname, ...c };
      if (spec) {
        const envelope = {
          $version: '1.0',
          source: {
            url: config.url || null,
            state: state.name,
            extractor: 'extract.mjs',
          },
          crop: {
            file: fname,
            text: c.text,
            bounds: { x: c.x, y: c.y, w: c.w, h: c.h },
          },
          root: spec,
        };
        await fs.writeFile(
          path.join(dir, specName),
          JSON.stringify(envelope, null, 2),
        );
        entry.spec = specName;
        specCount++;
      }
      cropIndex.push(entry);
    } catch (e) {
      console.warn(`  skipped ${fname}: ${e.message}`);
    }
  }
  await fs.writeFile(path.join(dir, '_index.json'), JSON.stringify(cropIndex, null, 2));

  // Design tokens
  const tokens = await page.evaluate(extractTokensInBrowser);
  await fs.writeFile(path.join(dir, 'tokens.json'), JSON.stringify(tokens, null, 2));
  await fs.writeFile(path.join(dir, '_DESIGN.md'), buildDesignMd(state.name, tokens, theme));

  // Reference origin marker — consumed by `print_widget compare` to decide
  // whether to use compare_threshold (Flutter-to-Flutter) or
  // cross_engine_threshold (browser-to-Flutter). Copies over to .reference/
  // along with the rest of the state dir in the handoff step.
  const origin = {
    origin: 'browser',
    extracted_at: new Date().toISOString(),
    url: config.url || null,
    state: state.name,
    viewport: VIEWPORT,
    deviceScaleFactor: DPR,
  };
  await fs.writeFile(
    path.join(dir, '_origin.json'),
    JSON.stringify(origin, null, 2),
  );

  console.log(
    `  ${stateName}: ${cropIndex.length} section(s), ${specCount} spec(s)`,
  );
  return { stateName, cropCount: cropIndex.length, specCount };
}

(async () => {
  await fs.mkdir(OUT, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: DPR });
  const page = await ctx.newPage();

  if (config.url) {
    console.log(`→ Base URL: ${config.url}`);
    // Use 'load' instead of 'networkidle' — SPAs like Lovable keep websockets
    // open for hot-reload, so the network never goes idle. Give the page a
    // fixed settle time after load to let React hydrate and paint.
    await page.goto(config.url, { waitUntil: 'load', timeout: 60_000 });
    await page.waitForTimeout(2500);

    // Force-load any web fonts declared in CSS font-family but never actually
    // imported by the page. Lovable and similar tools commonly declare
    // `font-family: Inter, sans-serif` while only @import-ing Roboto, which
    // means the browser silently falls back to the system sans-serif (macOS:
    // Helvetica Neue; Linux: DejaVu). That makes the extracted crops render
    // with the wrong font and any downstream Flutter comparison drifts.
    //
    // Configure via `states.json`:
    //   "forceFonts": ["Inter:wght@300;400;500;600;700"]
    const forceFonts = config.forceFonts ?? [];
    if (forceFonts.length > 0) {
      const href =
          'https://fonts.googleapis.com/css2?' +
          forceFonts.map((f) => 'family=' + encodeURIComponent(f)).join('&') +
          '&display=block';
      await page.addStyleTag({ url: href });
      // Wait for all declared fonts to actually load.
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(500);
    }
  }

  const results = [];
  for (let i = 0; i < config.states.length; i++) {
    results.push(await captureState(page, config.states[i], i));
  }

  // Global summary
  await fs.writeFile(
    path.join(OUT, '_SUMMARY.json'),
    JSON.stringify({ url: config.url, viewport: VIEWPORT, states: results }, null, 2)
  );

  console.log(`\n✅ Done. Output: ${OUT}`);
  await browser.close();
})().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
