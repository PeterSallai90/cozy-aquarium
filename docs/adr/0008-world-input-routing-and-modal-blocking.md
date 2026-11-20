# ADR 0008: World input routing and modal blocking

- Status: Accepted (pull request for #25; gated by `needs:owner`)
- Date: 2026-11-11; Amendment 1 (#31): 2026-11-20; Amendment 2 (#32): 2026-11-20
- Decision log reference: none (no row in the decisions table changes); refines the "Camera" row
  of Core systems in docs/architecture.md
- Issue: #25 (B14 orbit camera); used by #26 (zoom, pan, Home), #44/#45 (photo mode), #81
  (remappable bindings), the placement system (#31, Amendment 1) and delete and undo/redo
  shortcuts (#32, Amendment 2)

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
  actions (Ctrl+Z stays free for undo); exception since Amendment 1: Shift with the two placement
  rotate actions selects the fine step;
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

## Amendment 1 (#31, placement)

- Status: Accepted (pull request for #31; gated by `needs:owner`). No row of the decisions table
  changes; rules 1 to 6 above stay in force except where this amendment says so.
- Date: 2026-11-20

### Context

#31 adds the placement system: left mouse places, selects and drags items, Comma and Period
rotate them. The owner decided that Shift with Comma or Period turns by 1 degree instead of the
15 degree step (issue comment 7043191623). Rule 1 and the reserved-keys text say that keys with
Ctrl, Alt, Shift or Meta never trigger world actions, and rule 5 matches key actions exactly. The
Esc order of #31 is: modal dialog, running drag, running rotate hold, open Items panel, then the
pick or the selection. Photo mode (#44) must stop placement without losing the pick or the
selection.

### Decision

7. **Shift is the fine modifier of the two placement rotate actions.** `place_rotate_left`
   (physical Comma) and `place_rotate_right` (physical Period) have one event each, with no
   modifier, so #81 remaps one binding per action. They are the only world actions matched with
   `exact_match = false`; the event is then accepted only when Ctrl, Alt and Meta are all up
   (`WorldInput.allows_fine_modifier(event)`), and Shift held selects the fine step. Every other
   world action keeps rules 1 and 5. Shift alone stays reserved for photo mode, where placement is
   blocked (rule 10), so the two uses never meet. A held rotate key reads Shift again at each
   repeat from Shift key events seen in `_input` (rule 2), never from the `Input` singleton.
8. **Esc of a running gesture is read in `_input`.** A running gesture that Esc cancels (a drag, a
   rotate hold) reads `ui_cancel` in `_input`, cancels itself and marks the event handled, so it
   wins over open panels and a focused text field. A modal dialog ends every gesture first (rule
   4), so a dialog and a gesture never meet.
9. **Idle world Esc steps come after the HUD.** Esc steps of an idle world system (clear the pick,
   clear the selection) are read in `_unhandled_input`. The HUD (dialogs, panels) handles its Esc
   in `_unhandled_input` too and marks it handled. Because `SceneTree` calls `_unhandled_input`
   from the last node in tree order to the first, world systems stay in the 3D part of `main.tscn`
   (under `RoomCorner`), before the `Hud` CanvasLayer; a main-scene test pins the order.
10. **Photo mode blocks through the blocker group; feedback hides.** Photo mode puts its visible UI
    root into `world_input_blockers` (rule 4); no EventBus state signal is added. While the world is
    blocked (modal dialog or photo mode), placement hides the ghost, the drag preview, the selection
    mark and the hint line, ignores new presses and ends running gestures with no command; the pick
    and the selection survive and their feedback returns when the block ends.
11. **A world press releases text focus.** A left press that reaches `_unhandled_input` while a
    `LineEdit` or `TextEdit` has the focus releases it (`Viewport.gui_release_focus()`) and is then
    handled as a normal world press. A focused `Button` blocks nothing (it does not accept Comma or
    Period), as rule 1 already implies.

### Consequences

- The Reserved keys text of docs/architecture.md lists Comma and Period (placement rotate, alone or
  with Shift); Shift alone stays a photo mode key.
- #44 adds its photo-mode root to `world_input_blockers` and its own test; #31 tests rule 10 with
  a fake blocker.
- #81 remaps the two rotate actions by name; Shift as the fine modifier is not remappable there
  unless #81 decides otherwise with a new amendment.

## Amendment 2 (#32, delete and undo/redo shortcuts)

- Status: Accepted (pull request for #32; gated by `needs:owner`). No row of the decisions table
  changes; rules 1 to 11 stay in force except where this amendment says so.
- Date: 2026-11-20

### Context

#32 adds three shortcuts: Delete removes the selected item (a world action), Ctrl+Z undoes and
Ctrl+Y or Ctrl+Shift+Z redoes (global actions). All three are blocked during a drag, a rotate
hold, a modal dialog, photo mode and while a text field has the focus; Delete is also blocked by a
pick. A text field keeps its own Ctrl+Z. Only placement knows whether a drag or a rotate hold is
running, and the history buttons live in the HUD, which may not reference placement. Rule 5 binds
keys by physical code; on the Hungarian QWERTZ layout the physical Z position is labelled Y, so a
physical Ctrl+Z would be "Ctrl+Y" for a Hungarian player and the two shortcuts would swap.

### Decision

12. **Delete is a world action of placement.** `item_delete` (physical Delete, no modifier) is read
    by `PlacementSystem` in `_unhandled_input` with `exact_match = true` and no echo (rules 1 and
    5), so Shift+Delete and Ctrl+Delete do nothing and a focused text field keeps its Delete key. It
    acts only on the selection, with no pick, no running gesture, no blocker, no text focus and a
    history that is not busy. A focused `Button` does not block it (rule 11). The HUD Delete button
    and the colour dots do not run commands: they emit `EventBus.item_delete_requested` and
    `EventBus.item_colour_requested(has_colour, colour)`, and placement answers both with the same
    checks as the key (ADR 0012 Amendment 1), so every item edit has one owner.
13. **Undo and redo are global HUD actions.** `history_undo` (Ctrl+Z) and `history_redo` (Ctrl+Y
    and Ctrl+Shift+Z) are read by `HistoryControls` (a child of the `Hud` CanvasLayer) in
    `_unhandled_input` with `exact_match = true` and no echo; one press is one step. Because the
    GUI runs first (rule 1), a focused `LineEdit` or `TextEdit` consumes its own Ctrl+Z and Ctrl+Y
    (`ui_undo`, `ui_redo`); the handler also checks `WorldInput.is_text_focused` as a second guard.
    The handler and the two buttons do nothing while `WorldInput.is_blocked`, while
    `WorldInput.is_gesture_running` or while `CommandHistory.is_busy()`; a pick does not block
    them. "Global" means not tied to the selection or the tank; it never means "through a blocker".
14. **Letter shortcuts bind the logical key.** Exception to rule 5: the events of `history_undo`
    and `history_redo` use `keycode` (the key label of the active layout) with `ctrl_pressed`, not
    `physical_keycode`, so Ctrl+Z is the key labelled Z on QWERTY and QWERTZ alike. Positional keys
    (camera, rotate, Delete) stay physical. Tooltips and hints read the label of an action's first
    key event from the live input map (`InputLabels`, logical or physical as bound).
15. **An action may have more than one event.** Rule 7's "one event each" applies to the two
    rotate actions only (it is how the Shift fine step works). `history_redo` has two events; the
    first (Ctrl+Y) is the one shown in tooltips. #81 remaps per event and refuses a conflict with
    any other action's event; the existing "no two actions share a binding" test covers all events.
16. **Running gestures are queried through a group.** A world system with gestures joins the group
    `world_gesture_sources` (`WorldInput.GESTURE_GROUP`) in `_ready` and implements
    `has_running_gesture() -> bool`. `WorldInput.is_gesture_running(tree)` is true when any member
    in the tree reports a running gesture. Placement reports a press on an item, a drag, any
    rotate hold, and the tail of a rotate hold cancelled by a modifier (#31 AC 41 (d), unchanged).
    The tail ends when Ctrl, Alt and Meta are all up, or when the first non-modifier key pressed
    after the cancel (or carried by the cancelling event) is released. Placement cancels in
    `_input`, before the HUD reads the key, so without the tail the Ctrl+Z whose Ctrl cancelled the
    hold would undo a step; with it, that press does nothing (#32 AC 20) and the next Ctrl+Z press
    undoes as usual. The still-held rotate key does not restart the hold (echoes are ignored). Like
    rule 4 it is a stateless query: no EventBus state signal, no counter, and a freed system leaves
    the group by itself.
17. **Tree order.** `HistoryControls` and `ItemActions` (the Delete button and the colour row) are
    children of `Hud`, after `TankControls` and `PlacementHint`. They handle no Esc and no world
    key, so rule 9 is unchanged: placement stays under `RoomCorner`, before `Hud`, and its idle Esc
    and Delete run after the HUD; a main-scene test pins the order.

### Consequences

- The Reserved keys text of docs/architecture.md lists Delete (world, no modifier) and Ctrl+Z,
  Ctrl+Y and Ctrl+Shift+Z (global undo and redo).
- #44 photo mode blocks the shortcuts through its blocker (rule 10); #69 text entry keeps its own
  Ctrl+Z through rule 1; #81 remaps `item_delete`, `history_undo` and `history_redo` by name and
  per event, keeping the logical binding of the letter shortcuts. Meta+Z (macOS) is not bound;
  #81 may add it as a further event.
- Later gesture owners (photo mode, feeding) join `world_gesture_sources` when undo must wait for
  them.
