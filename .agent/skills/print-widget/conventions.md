# Widget Conventions

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain. Deep nesting hides intent.

## Structure rules

- **3-level rule**: Subtree deeper than 3 levels → extract to `_WidgetName extends StatelessWidget`
- **4+ children rule**: Column/Row/ListView with 4+ children → extract each child
- **Card decomposition**: Header + body + footer → 3 separate private widgets
- **No `_buildXxx()` methods**: Always extract to private `StatelessWidget` classes
- **Const constructors**: All `StatelessWidget` subclasses with no required mutable params → `const`
- **Component-first**: Check the project’s component library before building from scratch
- **Promote when reused**: Private widget used by 2+ features → move to shared location

## Behavioral rules (from real-world feedback)

- **IntrinsicHeight for equal-height cards**: Cards in the same Row need `IntrinsicHeight` + `CrossAxisAlignment.stretch` to match heights
- **Never add wrappers not in Figma**: Before adding Container, Card, or any wrapper widget, verify it exists as a node in the Figma design. Unnecessary wrappers add backgrounds, padding, or borders that break the match.
- **Never blanket-apply style changes**: Scope each fix to the specific component. After fixing one widget, verify that sibling widgets are unaffected.
- **Never guess, always verify**: ALWAYS check the Figma design context for actual values (colors, spacing, sizes). Never assume or approximate.
- **Copy-paste node names**: Don’t retype Figma node names — copy them exactly. Typos cause silent mismatches.
- **Never remove functionality as a workaround**: If a widget causes issues (e.g. AnimatedDefaultTextStyle), find an alternative implementation (e.g. TweenAnimationBuilder) instead of removing the feature.
- **Ask before uncertain color changes**: When the design context is ambiguous about a color, show the user what you plan to change and ask BEFORE modifying code.
- **Generate after EACH visual change**: Do not batch multiple visual changes. Make one change, generate, verify, then proceed. This isolates regressions.
- **Save novel solutions to CLAUDE.md**: When you discover a new pattern or workaround, persist it to the project’s CLAUDE.md so it’s available in future sessions.
- **Material ancestor is MANDATORY for any widget that renders text**: If a generated PNG shows yellow double-underlines under text, that is Flutter’s "no DefaultTextStyle / no Material ancestor" marker — the widget has no `Material` in its ancestor tree. Every atom, molecule, and organism print entry must resolve a `Material` ancestor, either by wrapping its own root in `Material(color: Colors.transparent, type: MaterialType.transparency, child: ...)` or via the session `appWrapper`. Assume nothing about the consumer context; a reusable widget that relies on "someone upstream will provide Material" will ship broken the first time it’s captured standalone. ALWAYS visually audit the generated PNG for yellow lines before trusting any compare score — pixelmatch can still return a high score while every glyph is underlined.
- **Mirror the reference’s overflow behavior — do NOT default to FittedBox**: When text won’t fit a slot, STOP and inspect how the reference handles the overflow. Does it truncate with ellipsis (`text-overflow: ellipsis`)? Wrap to a second line (`white-space: normal`)? Let the container grow? Accept the overflow? Mirror that exact behavior in Flutter (`Text(overflow: TextOverflow.ellipsis, maxLines: N)`, `softWrap: true`, or a layout adjustment). **FittedBox(scaleDown) is a last resort**: CSS almost never auto-scales text — if the reference truncates but Flutter auto-scales, pixelmatch sees every glyph at the wrong size and flags the whole component. Before reaching for FittedBox, verify via Playwright / DevTools that the reference really does auto-scale at the narrower width (rare — usually only true for SVG `viewBox` content or explicit JS-driven resize). When in doubt, truncate with ellipsis and ask the user — do not silently introduce a scale delta.

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don’t start from scratch.
- **Mock as little as possible**: Use real data and theme. Only mock external dependencies (network, platform channels).
- **GoRouter ancestor**: Widgets using navigation (`context.go()`, `GoRouterState.of()`) need `MaterialApp.router` with `GoRouter` in the `appWrapper` — not plain `MaterialApp`

## Design system component discovery (MANDATORY — run FIRST, before any implementation)

Before writing any new widget, search the project for existing equivalents. Creating a parallel component set is the #1 source of wasted iterations, dead code, and token drift. **This is the first step of the pipeline, not a nice-to-have.**

The search covers two tiers:

### Tier A — primitive components

Buttons, cards, chips, pills, toggles, tabs, badges, filters, dropdowns, avatars, icon buttons, form fields.

### Tier B — composite components (the ones agents miss most)

Tables, data grids, paginated lists, filter rows, search fields, kanban columns, timelines, master-detail panes, card-list hybrids, pagination strips. **Whenever the reference shows a row of header cells sitting above repeated body rows, STOP and search for an existing table — do not hand-roll `_Table` / `_Header` / `_Row` / `_Cell` private classes.**

### Search

Run these at the start of every implementation:

```bash
# All widget declarations in the project
Grep: "class \w+ extends (Stateless|Stateful)Widget" in lib/ and packages/

# Common component locations
Glob: lib/core/components/*.dart
Glob: lib/ui/core/ui/**/*.dart
Glob: lib/ui/features/*/widgets/**/*.dart
Glob: lib/design_system/**/*.dart
Glob: packages/*/lib/src/widgets/*.dart
Glob: packages/*_design_system/lib/**/*.dart

# Targeted searches for common composite primitives
Grep: "AdaptiveTable|DataTable|SimpleTable|DataGrid|PaginatedList|KanbanList|TimelineList"
Grep: "class \w*Table\b|class \w*Grid\b|class \w*List\b"
```

For each section of the reference, search twice: once for the visual primitive name (button, pill, card) and once for the *domain* name (orders list, pedidos table, clients grid). The second search is what finds `CardOrdersTable`, `KanbanListView`, `ClientCardList` — feature-specific components that have become the app's pattern without being in the DS package.

Build a one-line catalog: `ComponentName — where it lives — what it does`.

### Decision — use `AskUserQuestion` when in doubt

For each matched component, you have four options:

1. **Use as-is** — the existing component fits the reference with no visual change needed.
2. **Improve in place** — the existing component is close, but the reference needs a feature it doesn't have. Propose the change and get permission to edit the shared component.
3. **Create a V2** — the reference diverges enough that a parallel variant is justified (mirrors the `SideBarV2` / `CustomAppBarDesktopV2` / `CustomColorsV2` pattern). V2s are explicit, named, and document why they exist.
4. **Create from scratch** — no existing component matches, and no existing one is close enough to base a V2 on.

**When the match is ambiguous — partial fit, different visual style, unclear if a V2 is warranted — invoke `AskUserQuestion` before writing any code.** List the candidates you found, state the reference's constraints (size, row height, filter rows, pagination, etc.), and let the user pick option 1/2/3/4. Do NOT silently pick option 4 just because it's faster.

Example question frame:

> I found `CardOrdersTable` (lib/ui/features/client/widgets/client_360_detail/tables/...) which renders an orders table with filter pills + pagination — the exact pattern the reference shows. It uses `YHDataGrid` (Syncfusion). The reference is 638×448 with 32px rows; `CardOrdersTable` uses 42px default rows. Should I (1) use `CardOrdersTable` as-is and accept the row-height delta, (2) parameterize `CardOrdersTable` to accept a rowHeight prop, (3) create `CardOrdersTableV2` with Lovable-aligned spacing, or (4) hand-roll a new table for this card only?

### Red flags that you're about to reinvent a component

- You're about to name something `_FilterChipsWidget`, `_CustomToggle`, `_EmbeddedSegmentedButton`, `_SimpleTable`, `_OrdersList`, `_DataGrid` — these almost always exist.
- You're about to handwrite a `Container(decoration: BoxDecoration(borderRadius: ..., color: ...))` for something the DS calls a Card.
- You're about to write 3+ private `_HeaderRow` / `_BodyRow` / `_HeaderCell` / `_BodyCell` classes in one file — that's a table, and the project has at least three existing ones.
- You're about to use `Colors.*` or `TextStyle(fontSize: ...)` directly — those are tokens, not literals.

**Rule**: never create a widget matching a well-known pattern (filter, toggle, card, button, chip, **table, grid, list, pagination**) without first verifying the project doesn't have it. When in doubt, ask.
