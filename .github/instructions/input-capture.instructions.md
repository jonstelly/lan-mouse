---
applyTo: "input-capture/**"
---

## Purpose & responsibilities

- `input-capture` centralizes the OS-specific logic that reads local keyboard and mouse events and exposes them as a unified `Stream` of `CaptureEvent` plus position metadata.
- Capture events are forwarded to the IPC layer (`lan-mouse-ipc`) so the remote peers can emulate them. Keep this crate lean—avoid parsing CLI arguments or configuration here.

## Backend pattern

- The `Backend` enum enumerates available OS/layer-shell/X11/libei implementations plus the dummy fallback (see [`input-capture/src/lib.rs`](input-capture/src/lib.rs)).
- Each backend lives in its own module and is gated with the same cfgs you see now (`cfg(all(unix, feature = "layer_shell", not(target_os = "macos")))`, etc.). When adding a backend keep the gate tight so compilation fails fast on unsupported hosts.
- `InputCapture::new()` tries backends in priority order; prefer best UX first (libei → layer-shell → X11) and push slower fallbacks later. Always log the winning backend for easier debugging.

## Event handling conventions

- `InputCapture` implements `Stream` and manually pumps pending events for every client. Respect this existing buffering logic when modifying event flows—don’t short-circuit the `position_map` logic unless you also handle multiple clients at one physical position.
- Track `pressed_keys` like today to avoid holding modifiers. Any backend emitting a key event must update `pressed_keys` the same way otherwise keys can get stuck.

## Configuration & features

- Backend availability is controlled through features defined in [`Cargo.toml`](Cargo.toml#L28-L62); enabling `layer_shell_capture` or `libei_capture` activates new modules. Name new features clearly and gate downstream dependencies accordingly.
- The crate reuses types from `input-event`, so prefer the shared scancode enums rather than rolling new representations. Consult [`input-event/src/scancode.rs`](input-event/src/scancode.rs) when translating low-level codes.

## Testing & debugging tips

- Capture backends are best tested using the real GTK frontend or CLI daemon on the target OS. Run the daemon with `RUST_LOG=lan_mouse=debug` to trace backend selection.
- To emulate missing dependencies use the dummy backend (feature flag `dummy` is implicit) and confirm the rest of the pipeline still runs in integration tests.
- When making changes that might affect clients sharing a side, verify the `position_map` queueing still delivers events to each handle without starvation.

