# Widget Conventions

## Core principle: Composition over nesting

Flat widget trees are easier to read, test, and maintain. Deep nesting hides intent.

## Rules

- **3-level rule**: Subtree deeper than 3 levels → extract to `_WidgetName extends StatelessWidget`
- **4+ children rule**: Column/Row/ListView with 4+ children → extract each child
- **Card decomposition**: Header + body + footer → 3 separate private widgets
- **No `_buildXxx()` methods**: Always extract to private `StatelessWidget` classes
- **Const constructors**: All `StatelessWidget` subclasses with no required mutable params → `const`
- **Component-first**: Check the project’s component library before building from scratch
- **Promote when reused**: Private widget used by 2+ features → move to shared location

## Working with existing widgets

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don't start from scratch.
- **Mock as little as possible**: Use real data and theme. Only mock external dependencies (network, platform channels).
