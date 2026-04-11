# Parallel agent teams

## Purpose

When a single task produces 5 or more independent sibling components (a Figma screen with 8 cards, a Stitch-generated dashboard with multiple tiles, a Lovable page row with N KPI widgets), build them in parallel using an **agent team**, not sequentially. This applies to ANY provider — figma, stitch, lovable, or a hand-written spec — as long as the siblings do not depend on each other.

## When to use it

Use a parallel team when ALL of the following hold:

- The task produces 5+ components that share a container (row, grid, flex-wrap)
- Each component has its own data and renders independently (no cross-component state)
- Each component could theoretically be built by a different person with the same brief
- You have a reference per component (Figma node, Stitch snippet, Lovable DOM node, screenshot crop)

Do NOT use a parallel team when:

- There are only 2-4 siblings — overhead beats the gain
- Components share state or one configures another
- You have only one global reference (a single screenshot of the whole page with no per-component crops) — resolve crops first
- The design system component that all siblings use does not exist yet — build the shared atom first, serially, then parallel the siblings

## Why parallel beats sequential

- **Independent units**: Each component is a self-contained leaf — its own icon, its own reference crop, its own mock data, its own Flutter snippet. There is no data flow between siblings.
- **Zero drift**: Serial builds accumulate drift — the 7th component gets built with different conventions than the 1st because you "learned something new" halfway through. Parallel agents all start from the same brief, so conventions stay uniform.
- **Clean main session**: No 7 rounds of edits to `print_widget/config.dart` — the main session aggregates everything once.
- **Faster convergence**: 7 agents running at once finish in roughly the time of one, so the feedback loop to `print_widget compare` stays tight.

## Hard contract — what each agent produces

Every agent in the team MUST emit exactly these artifacts to its own isolated workspace dir (no shared files). Nothing else. The exact file set depends on the provider:

### Provider-agnostic (always required)

| Artifact | Purpose |
|---|---|
| `<slot>.ref.png` | Reference image of the component (cropped Figma export, Stitch screenshot, Lovable DOM crop) |
| `data.json` | Mock data — every label, value, delta, percentage, state matching the reference exactly |
| `snippet.dart.txt` | Ready-to-drop Dart widget code using the project design system tokens — NOT written into `lib/` directly |

### Provider-specific (when applicable)

| Artifact | When | Purpose |
|---|---|---|
| `icon.svg` | Custom icons (Lucide, Heroicons, hand-drawn) that are not in the project icon set | Captured SVG outerHTML from the source DOM, or exported from Figma |
| `icon_const.dart.txt` | Same | `const String <slot>Svg = r"""<svg>...</svg>""";` declaration |
| `tokens.md` | Source uses novel colors or spacings that do not exist in the project theme | One row per new token with its proposed project-theme name |

**Forbidden for every agent**: editing `print_widget/config.dart`, editing any shared file under `lib/`, running `print_widget generate`, running tests, or touching another agent's workspace. These are all main-session responsibilities.

## Workspace isolation

Give each agent a unique workspace dir — this is what makes parallel safe without git worktrees:

```
/tmp/agent-team-<feature>/
  <slot-1>/   <- agent 1 writes only here
  <slot-2>/   <- agent 2 writes only here
  <slot-3>/   <- agent 3 writes only here
  ...
```

Agent workspaces are artifact buckets — nothing is committed from them. The main session reads the artifacts and aggregates into the repo.

## Mandatory Flutter rules every agent must obey

These rules apply to every agent regardless of provider. Bake them into the brief:

- **Material ancestor**: Every widget that renders text must resolve a `Material` ancestor. Wrap the widget root in `Material(color: Colors.transparent, type: MaterialType.transparency, child: ...)`. Yellow double-underlines in the generated PNG = missing Material. The agent's `snippet.dart.txt` output must already include this wrapper or a clearly marked TODO for the main session to add one.
- **FittedBox for cross-context reuse**: If the component will be rendered standalone AND composed into a narrower organism slot, variable-width text values must be wrapped in `Flexible > FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft) > Text(...)`. Apply proactively; retrofitting later is 3x the work.
- **Design system tokens only**: No raw `Color(0x...)`, no raw `EdgeInsets.all(16)`. Every value must reference a token from the project theme. If the source uses a color that has no token, record it in `tokens.md` for the main session — do not inline raw hex.
- **Const constructors**: Private `StatelessWidget` subclasses → `const`. No `_buildXxx()` methods — always extract sub-widgets.
- **No test runs**: Agents must not run `print_widget generate`, `flutter test`, or any build command. The snippet is text, not a compiled artifact. The main session is the only place builds happen.

## Agent brief template

Copy this into every agent's prompt, filling in `<slot>` and provider-specific fields:

```
You are building a single component (<slot>) as part of a parallel agent team.

Reference source: <figma-url | stitch-snippet | lovable-url>
Reference node/selector: <node-id | CSS selector | crop coordinates>
Viewport (if web): <WxH>

Workspace: /tmp/agent-team-<feature>/<slot>/   (write ONLY here)

Produce these artifacts:
  - <slot>.ref.png        (reference crop at the target resolution)
  - data.json             (mock data matching the reference exactly — labels,
                           numbers, states)
  - snippet.dart.txt      (ready-to-drop Dart widget using project DS tokens)
  - icon.svg              (ONLY if the component uses a custom icon not in the
                           project icon set)
  - icon_const.dart.txt   (ONLY if icon.svg exists — const String declaration)
  - tokens.md             (ONLY if the source introduces new colors/spacings
                           that do not exist in the project theme)

DO NOT:
  - edit print_widget/config.dart
  - edit anything under lib/
  - run print_widget generate or any build/test command
  - touch any other agent's workspace

Flutter rules:
  - Wrap the widget root in Material(type: MaterialType.transparency) to avoid
    yellow underlines under text.
  - If the component will be composed into a narrower organism slot, wrap
    variable-width text values in Flexible > FittedBox(scaleDown, centerLeft).
  - Use only project design system tokens. No raw Color() or EdgeInsets literals.
  - Private StatelessWidget subclasses must be const.
  - No _buildXxx() methods — always extract sub-widgets.

Report back when all required artifacts are written.
```

## Main session aggregation

After all agents finish, the main session takes over:

1. **Audit each workspace** — verify every required artifact is present. Missing artifacts = rerun that specific agent.
2. **Copy reference crops**: each `<slot>.ref.png` to `print_widget/output/<feature>/<slot>/<slot>.ref.png`
3. **Drop widget snippets**: each `snippet.dart.txt` into `lib/ui/features/<feature>/widgets/<slot>.dart`
4. **Aggregate icons**: each `icon_const.dart.txt` into a shared `<feature>_icons.dart`, or inline per widget if one-offs
5. **Reconcile tokens**: merge all `tokens.md` rows — duplicates resolve to the same new token. Add new tokens to the project theme BEFORE adding entries to `print_widget/config.dart`.
6. **One config edit**: add all slots to `print_widget/config.dart` in a single pass.
7. **Batch generate**: `print_widget generate --name=<slot>` for each, or the full batch if supported.
8. **Visual audit every PNG before trusting scores**: look for yellow underlines (Material ancestor), text truncation, missing icons, wrong colors. Pixelmatch can score high while glyphs are underlined.
9. **Compare**: `print_widget compare` and iterate per the iterate.md loop on the worst-scoring slots. Re-dispatch a single agent per slot if a specific one needs a rewrite.
10. **One commit for the whole team** — clean history over one-commit-per-slot.

## Team anti-patterns

- **Shared config edits**: the moment two agents both want to edit `print_widget/config.dart`, you have a race. Keep all config edits in the main session.
- **Inter-agent chat**: agents must not read each other's workspaces or coordinate. Independence is the contract.
- **Re-generating the reference from scratch in every agent**: if the reference comes from a central source (smart-extract, Figma MCP), capture it once in the main session and copy into each agent workspace before dispatch.
- **Partial briefs**: copy-pasting the brief template with `<slot>` un-filled is the #1 cause of agent failures. Fill every placeholder before dispatch.
- **Skipping the visual audit**: trusting pixelmatch scores blind is how yellow-underlined components ship. Always eyeball the PNG grid before shipping.
