---
applyTo: "**/*.rs"
---

## Rust landscape for Lan Mouse

- The repository is a single Cargo workspace where `lan-mouse`, `lan-mouse-gtk`, `lan-mouse-cli`, `input-*`, `lan-mouse-ipc`, and `lan-mouse-proto` share versions and features.
- Every crate targets multiple OSes and relies on conditional compilation, so read [`Cargo.toml`](Cargo.toml) before toggling features or enabling new crates.
- Keep README/Component docs in sync when you change OS support or network protocols because human-facing docs are the entry point for new contributors.

## Feature and cfg discipline

- Feature flags live at the root; do not duplicate them elsewhere. Refer to the `features` table in [`Cargo.toml`](Cargo.toml) when adding new backends or optional frontends.
- Gate OS-specific files via the same cfg blocks you see in [`input-capture/src/lib.rs`](input-capture/src/lib.rs) and [`input-emulation/src/lib.rs`](input-emulation/src/lib.rs). The project tolerates a rich matrix of `unix`, `windows`, `macos`, and feature combinations, so keep new modules granular and introducible only when the matching cfg is set.
- Avoid `#[cfg(feature = "foo")]` on individual functions unless that feature actually alters the public signature—prefer module-level gating so you never ship empty stubs for an unsupported backend.

## Async capture + emulation patterns

- Most logic lives in async loops driven by `tokio`, `futures`, and `async_trait`. Model new flows as streams or `async` methods (see how `InputCapture` implements `Stream` and polls upstream backends manually in [`input-capture/src/lib.rs`](input-capture/src/lib.rs)).
- Keep `async_trait` traits tightly scoped (the `Capture` and `Emulation` traits are only used within their respective crates). Pass handles across async boundaries rather than cloning heavy context.
- Use `tokio::sync::Mutex`/`Semaphore` sparingly; prefer the existing single-threaded stream handling unless a new backend truly needs shared state.

## Logging and errors

- Errors are built on `thiserror`, and runtime diagnostics use `log`. Match the `InputCaptureError`/`InputEmulationError` hierarchy when introducing new failure modes so the CLI and GTK frontends can `.interpret()` them correctly.
- Keep log messages actionable and guard guard macros as in the capture/emulation crates—`log::info!` is for backend selection and `log::warn!` for feature fallbacks.

## Cross-crate expectations

- The `lan-mouse` binary routes capture events → IPC → emulation, so any API change in `input-event`, `input-capture`, `lan-mouse-ipc`, or `input-emulation` should consider its effect on the pipeline. Validate via integration smoke tests rather than unit tests alone because the crate boundary behavior is what matters in the workspace.
- Shared protocol definitions live in `lan-mouse-proto`. If you tweak serialization, update the version numbers in each dependent crate.

## Formatting, testing, and tooling

- Always run `cargo fmt` and `cargo clippy --workspace` after touching more than a few lines; the repo aims for stable formatting and zero clippy warnings.
- Use `cargo test --workspace` plus `cargo test -p <crate>` when experimenting on a single crate. End-to-end verification often involves the GTK frontend and the CLI or service mode.
- Shadow metadata is generated via `shadow-rs` in `build.rs`; avoid renaming binaries without updating the metadata block.

