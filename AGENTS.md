<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Lan Mouse Agent Instructions

## Repository purpose

- Lan Mouse is an open-source Software KVM that shares mouse/keyboard input across local networks and mirrors the structure described in [README.md](README.md).
- The repository combines a GTK frontend, a CLI/daemon mode, and multi-OS capture/emulation cores so contributors understand both high-level usage and low-level OS bindings.
- Most organization work centers on expanding backends, keeping protocols in sync, and making the workspace easier to build on Linux, Windows, and macOS simultaneously.

## Core principles for any change

- **Scope discipline.** Only implement what was requested—let the user decide whether related work is urgent instead of sneaking unasked-for features into the change.
- **Maintainability & observability.** Each backend should log startup/failure paths, surface clear errors, and document assumptions in the code or associated docs.
- **Options & trade-offs.** When multiple approaches are feasible, describe 2‑3 options, highlight the trade-offs, and deliver the simplest correct solution.
- **Clarify OS behavior.** Ask questions when requirements touch OS-specific capture/emulation guarantees (Linux vs. Windows vs. macOS can differ significantly).
- **Docs stay current.** Update [README.md](README.md) or [DOC.md](DOC.md) whenever you touch a public API, packaging instructions, or supported platform list.
- **Testing is proportional.** Add tests that cover the new logic; follow Rust testing best practices (`#[test]`, `#[cfg(test)]`, integration tests under `tests/`) and run the relevant `cargo test` invocations. Document when an OS-specific feature cannot be exercised locally.
- **Rust best practices & commenting.** Generated code must follow ownership/error-handling idioms (`Result`, `Option`, `thiserror`), emit descriptive logs, and include concise comments only where the intent or invariants are otherwise obscured.

## Technology stack snapshot

- Rust workspace with `lan-mouse`, GUI crate (`lan-mouse-gtk`), CLI (`lan-mouse-cli`), IPC protocol crate, and low-level crates (`input-capture`, `input-event`, `input-emulation`, `lan-mouse-ipc`, `lan-mouse-proto`).
- Tokio-based async runtime, `futures` streams, `async_trait`, and `thiserror` for unified error handling.
- Optional GTK frontend via the `gtk` feature; OS-specific capture/emulation features (layer-shell, libei, wlroots, x11, remote desktop portal, etc.) are declared in [Cargo.toml](Cargo.toml).
- `shadow-rs` builds metadata via `build.rs`, so metadata changes should update that script as well.

## Architecture pointers

### Process Model & IPC

Lan-mouse uses a **daemon + frontend** architecture:

- **Daemon** (`lan-mouse daemon` or `Service` in `src/service.rs`): handles capture, emulation, network, crypto, client management
- **Frontend** (GTK or CLI): stateless UI that connects via IPC, sends `FrontendRequest`, receives `FrontendEvent`

IPC transport:

- **Linux**: Unix socket at `$XDG_RUNTIME_DIR/lan-mouse-socket.sock`
- **macOS**: Unix socket at `~/Library/Caches/lan-mouse-socket.sock`
- **Windows**: TCP `127.0.0.1:5252` (planned: named pipe)

On normal GTK launch, `main.rs` spawns daemon as child process, then runs GTK which connects via IPC. When `lan-mouse daemon` runs explicitly, multiple frontends can connect (headless/systemd use).

### Crate Responsibilities

| Crate             | Purpose                                                                 |
| ----------------- | ----------------------------------------------------------------------- |
| `lan-mouse`       | Main binary, daemon service, network protocol                           |
| `lan-mouse-gtk`   | GTK4/libadwaita frontend                                                |
| `lan-mouse-cli`   | Command-line frontend for scripting                                     |
| `lan-mouse-ipc`   | IPC protocol types (`FrontendRequest`/`FrontendEvent`), socket handling |
| `lan-mouse-proto` | Network protocol types (peer-to-peer)                                   |
| `input-capture`   | OS-specific input capture backends                                      |
| `input-emulation` | OS-specific input injection backends                                    |
| `input-event`     | Shared event types, scancode mappings                                   |

### Windows-Specific Considerations

The current Windows backend uses `SendInput` which fails for login screen, UAC, and elevated windows. See [docs/windows-elevated-plan.md](docs/windows-elevated-plan.md) for the planned solution: run the daemon as a Windows service (same binary, detected at startup via `windows-service` crate).

### Additional Architecture Notes

- Input capture is an event stream: `InputCapture` translates OS-level events into `CaptureEvent`s and shares them via `lan-mouse-ipc`. See [`input-capture/src/lib.rs`](input-capture/src/lib.rs) for the backend selection ordering and the `position_map` queuing logic.
- Input emulation applies inbound events to the local system while guarding against stuck keys; the `Emulation` trait lives in [`input-emulation/src/lib.rs`](input-emulation/src/lib.rs) and keeps a `pressed_keys` map per handle.
- Protocol glue lives in `lan-mouse-ipc`/`lan-mouse-proto`, and the GTK frontend/CLI glue everything together.
- Systemd service definitions, firewall rules, and desktop entries reside in `service/`, `firewall/`, and the repository root to facilitate packaging across distros.
- Central pipeline abstraction: capture → IPC → emulation. Treat `input-capture` outputs as the source stream, `lan-mouse-ipc` as the relay/authorization tier, and `input-emulation` as the sink. Any change to the stream shape requires updates in each tier and careful versioning in `lan-mouse-proto`.
- Asynchronous design: upstream crates rely on `tokio`, `futures`, and `async_trait`. Respect the existing `Stream` implementations and prefer explicit `async fn`s for new behavior. Avoid blocking the runtime; if you need to block, isolate it behind `spawn_blocking` or a dedicated thread.
- Feature & cfg discipline: `Cargo.toml` controls optional backends (gtk, layer shell, wlroots, libei, RDP, etc.). Every platform-specific module mirrors its cfg tag so build failures surface early. When introducing new cfg combinations, update documentation explaining when those features are available.
- Input-event consistency: share scancode conversions and event enums from `input-event`. Do not duplicate keycode translations; extend `input-event` when you need new scancodes.

## Implementation expectations

- Write minimal code that satisfies the request; if you see follow-up work, describe it instead of implementing it concurrently.
- Keep cross-platform logic clean: split OS-specific layers into separate modules (as seen under `input-capture/src` and `input-emulation/src`) and gate them via cfg attributes.
- Follow Rust best practices documented in [.github/instructions/rust.instructions.md](.github/instructions/rust.instructions.md): handle ownership carefully, propagate errors with `Result`, use `thiserror` for domain-specific cases, and keep the borrow checker happy.
- Tests must match the scope of the change. Small utility functions get unit tests; new protocol behavior gets integration tests (via `tests/` or workspace `cargo test`). When certain backends are hard to exercise locally, mock the behavior or document the manual verification steps taken.
- Keep code comments concise and intent-focused. Avoid over-commenting trivial assignments; reserve comments for explaining _why_ a mutex is needed, why a cfg gate exists, or why certain backends are skipped.

## Command execution patterns

- Build/debug the whole workspace with `cargo build --workspace` or a single crate via `cargo build -p <crate>`.
- Toggle features explicitly: `cargo run --features "layer_shell_capture,wlroots_emulation" -- --help` compiles with only those backends, matching the manual installation guidance in [README.md](README.md).
- GTK/macOS packaging uses the existing shell scripts: `scripts/makeicns.sh` and `scripts/copy-macos-dylib.sh` after running `cargo bundle` (see [README.md](README.md) for the recipe).
- `nix develop`/`nix-shell` set up the environment described in [nix/README.md](nix/README.md); prefer these commands when debugging dependencies on nix-based systems rather than manual installs.
- No `cd` commands in scripts—use explicit paths and run everything from the repository root. This keeps terminal sessions in the root directory so future commands can assume `pwd` is the repository root and work without additional navigation.

## Scripts and tooling

- `scripts/makeicns.sh` builds macOS icons, and `scripts/copy-macos-dylib.sh` copies shared libraries into bundles—run them only when targeting the GTK bundle on macOS.
- The systemd unit lives at `service/lan-mouse.service`; installing it helps with daemon mode testing described under the daemon usage section of [README.md](README.md).
- The firewall rules under `firewall/lan-mouse.xml` accompany Linux packaging; if a change affects network ports/protocols, document it in the README and service files.

## Documentation & configuration

- The main configuration file is `config.toml` (mirrored by `$XDG_CONFIG_HOME/lan-mouse/config.toml` in user installations). Keep comments in sync when adding new knobs.
- High-level guidance lives in [DOC.md](DOC.md) and [README.md](README.md); highlight OS known issues (X11 limitations, Windows cursor behavior, Wayfire plugin needs) whenever they change.
- Packaging references (desktop file, icon, firewall, nix flakes) are best fed by existing directories—avoid duplicating instructions elsewhere.

## Testing strategy

- Core verification is `cargo test --workspace`; use `cargo test -p <crate>` when working in a single crate.
- Integration-level coverage happens via CLI/GTK manual testing across OSes; reproduce capture/emulation flows on the relevant host when touching OS-specific code.
- Use `RUST_LOG=lan_mouse=debug` or `trace` when diagnosing backend selection or event loss.

## Specialized agent instructions

- Rust-specific guidelines: [.github/instructions/rust.instructions.md](.github/instructions/rust.instructions.md)
- Input capture specifics: [.github/instructions/input-capture.instructions.md](.github/instructions/input-capture.instructions.md)
- Input emulation specifics: [.github/instructions/input-emulation.instructions.md](.github/instructions/input-emulation.instructions.md)

Consult those files when you land inside the corresponding code—only the relevant file set is loaded, which keeps the instructions focused and manageable.

## Preferred workflow

- Clarify the user intent if anything in the request or existing code is ambiguous, especially when OS-specific delivery differs across Linux/Windows/macOS.
- Implement just the requested change, keeping it minimal and aligned with the Rust patterns described earlier; flag follow-up work instead of absorbing it casually.
- Add or update tests that cover the new behavior (unit, integration, or both depending on scope) and `cargo test` the affected crates before claiming completion. If an OS-specific backend cannot be exercised locally, note the manual steps that need verification.
- Run formatting/linting (`cargo fmt`, `cargo clippy --workspace`) when touching multiple files, then document any non-obvious decisions or remaining questions for reviewers.
