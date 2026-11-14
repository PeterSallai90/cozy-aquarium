# ADR 0008: World input routing and modal blocking

- Status: Accepted (accepted when the #25 pull request merges; gated by `needs:owner`)
- Date: 2026-11-11
- Decision log reference: none (no row in the decisions table changes); refines the "Camera" row
  of Core systems in docs/architecture.md
- Issue: #25 (B14 orbit camera); used by #26 (zoom, pan, Home), #44/#45 (photo mode), #81
  (remappable bindings) and the placement system

## Context

#25 adds the first system that reads mouse and keyboard input in the 3D world: the build camera
(right-drag orbits, Q/E and R/F step and repeat while held). Placement (left mouse), zoom and pan
(#26) and photo mode (#44) follow. They all share the screen with GUI panels (tank chooser, tank
details #117), modal dialogs (change-tank confirmation) and, later, text fields (rename).

The acceptance criteria of #25 need:

- a drag that starts on a panel never moves the world; a drag that starts in the world keeps
  working when the pointer passes over a panel and ends when the button is released anywhere,
  also outside the window, or when the window loses focus;
- a focused text field keeps Q/E/R/F; keys with Ctrl, Alt, Shift or Meta never trigger world
  actions (Ctrl+Z stays free for undo);
- an open modal dialog blocks all world input. The current dialog stops the mouse with a
  full-screen dimmer, but its focused buttons do not accept letter keys, so a Q press would still
  reach `_unhandled_input`.

Facts checked in Godot 4.7.2: `_input` runs before the GUI, `_unhandled_input` after it; a Control
with `MOUSE_FILTER_STOP` consumes mouse events over it; a `LineEdit` accepts printable key events;
a `Button` does not accept letter keys; `InputEvent.is_action_pressed(action, allow_echo,
exact_match)` with `exact_match = true` rejects an event whose modifiers differ from the binding.
`Viewport.push_input` (used by some tests) does not update the `Input` singleton, while
`Input.parse_input_event` (the GdUnit4 scene runner) does.

## Decision

1. **Presses start in `_unhandled_input`.** A world system starts a gesture (drag, key press,
   held key) only from `_unhandled_input`, so every GUI Control that consumes the event wins:
   panels with `MOUSE_FILTER_STOP`, focused text fields, buttons that accept `ui_accept`.
2. **Running gestures continue and end in `_input`.** Once started, a drag reads its motion and its
   release, and a held key reads its release, in `_input`, before the GUI. The event is not marked
   as handled, so hover and other UI still see it. A drag therefore keeps working over a panel and
   ends on a release anywhere. Gesture state is never derived by polling the `Input` singleton,
   so it behaves the same with `push_input` and `parse_input_event`.
3. **Focus loss ends every gesture.** `NOTIFICATION_APPLICATION_FOCUS_OUT` and
   `NOTIFICATION_WM_WINDOW_FOCUS_OUT` end drags and release held keys.
4. **Modal UI blocks world input through a group, not a signal.** A modal Control joins the group
   `world_input_blockers` (constant `WorldInput.BLOCKER_GROUP`). While any member is visible in the
   tree, `WorldInput.is_blocked(tree)` is true: world systems ignore new presses and end running
   gestures. The helper is a pure static function in `game/systems/input/world_input.gd`. Panels
   that are not modal (tank details, tank chooser) do not join the group.
5. **Action names and matching.** Input actions live in the `project.godot` input map with a
   `<system>_` prefix (`camera_` for #25 and #26), so #81 can remap them by name. Key actions are
   matched with `exact_match = true` and echo events are ignored; repeats come from the system's
   own frame-time timer. Mouse button actions use default matching. Keys are bound by physical
   key code (US-QWERTY positions); #81 decides on remapping.
6. **Systems expose a step function.** A system with timed input behaviour (damping, key repeat,
   fades) runs it in a public `step(delta_s)` that `_process` calls, so tests drive it with fixed
   frame times.

## Alternatives considered

- **EventBus `modal_opened` / `modal_closed` with a counter.** Stateful: a dialog freed while open
  leaves the counter wrong and the camera blocked. The group query is stateless.
- **Block keys whenever a Control has keyboard focus.** A clicked button keeps the focus, so Q/E
  would stop working after any button click until the player clicks elsewhere.
- **Modal dialogs as exclusive `Window` popups.** Godot then keeps input away from the main
  viewport, but every existing dialog, its theme and its tests would have to be rebuilt.
- **Whole gestures in `_unhandled_input`.** A drag would stop as soon as the pointer crosses a
  panel, and a release over a panel or the dimmer would be lost (stuck drag).
- **Polling `Input.is_mouse_button_pressed` to end drags.** Works in the game, but fails in tests
  that use `push_input` and hides the routing rule.

## Consequences

- `TankChangeDialog` (and every later modal, for example the settings screen once it is shown in
  the game) joins `world_input_blockers`; a test scan can check that every modal scene does.
- The camera (#25), zoom and pan (#26), placement and photo mode (#44) follow rules 1 to 6; #81
  remaps actions by name without touching the systems.
- Q/E/R/F keep working while a non-modal panel is open; a focused text field keeps its letters.
