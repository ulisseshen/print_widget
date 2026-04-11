# Screen Patterns

## Callbacks over hardcoded logic

Screens are presentation-only. Data in, callbacks out. No business logic, navigation, or API calls.

| Type | Use case |
|------|----------|
| `VoidCallback?` | Button press, tap, form submit |
| `ValueChanged<T>?` | Text field, toggle, selection |
| `ValueSetter<int>?` | Index-based (tabs, pages) |

Pass `null` to disable an action.

## Screen-provider separation

- **Screen**: Pure `StatelessWidget` receiving data + callbacks. Testable, previewable with print_widget.
- **Page**: Connects state management to the screen.

## Mock data for print_widget

In `print_widget/config.dart`, populate all states with representative data:
- Use representative values ("Sarah Johnson", not "User 1")
- Lists: 3–5 items to show scrolling
- All visual states: empty, loading, filled, error, disabled

## Working with existing screens

- **Extract, don't rewrite**: Refactor by extracting sub-widgets. Don't start over.
- **Mock as little as possible**: Pass real data models. Only mock external systems.
- **Preserve the Page**: Only modify the Screen (presentation). Keep the wiring intact.

## Mock patterns for full page rendering

### Progressive mock — start with noSuchMethod

When a page depends on providers, start with a catch-all mock and add overrides as errors appear:

```dart
class _AppMock implements MyProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

If a method returns `Future<void>`, `noSuchMethod` returning null will crash. Use an async-safe base:

```dart
class _AsyncSafeMock implements MyProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final returnType = invocation.memberName;
    // For Future-returning methods, return completed future
    return Future<void>.value();
  }
}
```

Then add overrides as type errors appear:
```dart
@override
int get menuOpened => -1;

@override
String get currentUserId => 'mock-user-id';

@override
List<Order> get orders => [];
```

### Full page shell — GoRouter + Providers + Scaffold

For capturing a complete page with AppBar, Sidebar, and navigation:

```dart
appWrapper: (child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MyProvider>.value(value: _AppMock()),
      // Add all required providers
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: '/my-page',
        routes: [
          GoRoute(
            path: '/my-page',
            builder: (context, state) => child,
          ),
        ],
      ),
    ),
  );
},
```

If the page needs a Scaffold shell (AppBar + Sidebar):
```dart
builder: (context, state) => Scaffold(
  body: Row(children: [
    const SideBar(),
    Expanded(child: Column(children: [
      const CustomAppBar(),
      Expanded(child: child),
    ])),
  ]),
),
```

### GoRouter as required ancestor

Widgets using `context.go()`, `GoRouterState.of(context)`, or any navigation REQUIRE `MaterialApp.router` with `GoRouter` in the tree. Without it, the widget crashes with "GoRouter not found". Always use `MaterialApp.router` (not `MaterialApp`) when the widget uses navigation.

## Tracing widget dependencies

Before building a mock or appWrapper, trace what the widget actually needs:

```bash
# Find provider reads in the widget file
grep -n "context.read\|context.watch\|ref.read\|ref.watch\|Provider.of" lib/path/to/widget.dart

# Find inherited widgets
grep -n "Theme.of\|MediaQuery.of\|Navigator.of\|Scaffold.of" lib/path/to/widget.dart
```

Start with the minimum set. Add providers only as errors appear during generation.

## Design system component customization

When a DS component almost matches but needs tweaking, choose one of these approaches (in order of preference):

1. **Add parameter to DS component** (recommended): If the DS component is yours, add an optional parameter for the customization. This keeps the design system as the single source of truth.
2. **Wrap in Container/Padding**: For spacing-only adjustments, wrap the DS component. Never modify its internal padding.
3. **Fork the component**: Last resort. Copy the DS component and modify. Document why in a comment.

Avoid option 3 unless the customization is fundamentally incompatible with the DS component’s API.

## Toggle state pattern

Capture expanded/collapsed or on/off states using `pages()` with `state()` and the `setup` callback:

```dart
pages('settings_panel', states: [
  state('collapsed', const SettingsPanel()),
  state(
    'expanded',
    const SettingsPanel(),
    setup: (tester) async {
      // Tap the expand button to toggle state
      await tester.tap(find.byKey(const Key('expand_toggle')));
      await tester.pumpAndSettle();
    },
  ),
]),
```

The `setup` callback runs after `pumpAndSettle()`, so the widget is fully built before interaction. Use it for:
- Tapping toggles, accordions, expandable sections
- Scrolling to specific positions
- Entering text in form fields
- Selecting tabs or navigation items
