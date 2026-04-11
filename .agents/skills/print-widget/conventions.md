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
- **FittedBox(scaleDown) for cross-context reuse**: Atoms/molecules that will be rendered standalone AND composed into an organism at a narrower width must wrap variable-width text values in `Flexible > FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft) > Text(...)`. This keeps the standalone capture at natural size while shrinking smoothly in the tighter organism slot — no clipping, no truncation, no fontSize downgrades. Apply proactively when the component will be composed; retrofitting after the organism fails is 3x the work.

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don’t start from scratch.
- **Mock as little as possible**: Use real data and theme. Only mock external dependencies (network, platform channels).
- **GoRouter ancestor**: Widgets using navigation (`context.go()`, `GoRouterState.of()`) need `MaterialApp.router` with `GoRouter` in the `appWrapper` — not plain `MaterialApp`

## Design system component discovery (MANDATORY before creating a new widget)

Before creating ANY new widget — button, card, chip, pill, toggle, tab, badge, filter — search the project for existing equivalents. Creating a parallel component set is the #1 source of wasted iterations.

Run these greps at the start of every implementation:

```bash
# All widget declarations in the project
Grep: "class \w+ extends (Stateless|Stateful)Widget" in lib/ and packages/

# Common component locations
Glob: lib/core/components/*.dart
Glob: lib/design_system/**/*.dart
Glob: packages/*/lib/src/widgets/*.dart
Glob: packages/*_design_system/lib/**/*.dart
```

Build a one-line catalog of each found widget: `ComponentName — what it does`.

For each visual element in the reference:
1. Classify it: is it a button, pill, segmented button, tab, chip, card, toggle, badge?
2. Search the catalog for a matching type.
3. If found: use it. Do NOT create a new one.
4. If not found: flag it to the user before creating. The user may want to add it to the DS instead of inlining it in a feature.

Red flags that you're about to reinvent a DS component:
- You’re about to name something `_FilterChipsWidget`, `_CustomToggle`, `_EmbeddedSegmentedButton`, etc. — these almost always exist
- You’re about to handwrite a `Container(decoration: BoxDecoration(borderRadius: ..., color: ...))` for something the DS calls a Card
- You’re about to use `Colors.*` or `TextStyle(fontSize: ...)` directly — those are tokens, not literals

Rule: **never** create a widget of a well-known pattern (filter, toggle, card, button, chip) without first verifying the DS doesn’t have it.
