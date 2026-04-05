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
