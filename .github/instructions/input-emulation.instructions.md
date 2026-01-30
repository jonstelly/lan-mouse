---
applyTo: "input-emulation/**"
---

## Purpose

- `input-emulation` receives encoded events from `lan-mouse-ipc` and replays them on the local host. It is the counterpart to `input-capture` and shares the same feature-driven OS coverage (wlroots, libei, X11, Windows, macOS, etc.).
- Keep it focused on event delivery and error reporting; translation, authentication, and client bookkeeping belong to `lan-mouse-ipc` or the main binary.

## Backend expectations

- The `Backend` enum mirrors capture: each backend struct implements the `Emulation` trait and is gated with the same cfgs (see [`input-emulation/src/lib.rs`](input-emulation/src/lib.rs)).
- The crate prevents stuck keys via `pressed_keys`, so any backend that emits low-level key up/down pairs must respect that bookkeeping.
- Keep the four `async fn` methods on the `Emulation` trait (`consume`, `create`, `destroy`, `terminate`) implemented consistently so the higher-level code can rely on predictable lifecycle hooks.
- The `consume` method deduplicates keyboard events before forwarding to the OS backend; preserve that dedup logic if you tweak `pressed_keys`.

## Feature & build guidance

- Add new optional backends via feature flags declared in `Cargo.toml` under `features` (e.g., `wlroots_emulation`, `libei_emulation`).
- The existing features share dependencies with `input-capture` (`input-event` scancodes, `async_trait`, etc.), so prefer reusing those dependencies rather than adding new ones unless absolutely necessary.
- Build the crate inside the workspace with `cargo build -p input-emulation` after toggling features to ensure the correct cfgs compile.

## Testing & observability

- Use the CLI or GTK frontend to send events to a target; the emulation crate runs inside the same binary as those frontends. Run `lan-mouse daemon` with `RUST_LOG=lan_mouse=trace` to confirm the chosen backend logs look sane.
- When changing event handling, test scenarios where a client disconnects unexpectedly so that `terminate()` still releases pressed keys and `release_keys()` completes without panicking (see `InputEmulation::terminate`).

