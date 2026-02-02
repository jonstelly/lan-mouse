# Security review — lan-mouse

Date: 2026-02-02

Summary

- Short audit of repository for malicious or security-suspect code. No obvious backdoors or exfiltration found. Found several security-relevant issues and hardening opportunities (see Findings).

Findings (concise)

- Insecure DTLS client verification: outgoing client connections set `insecure_skip_verify = true` (see [src/connect.rs](src/connect.rs#L60)). This disables certificate validation and enables MITM on the LAN. Recommend enabling verification and/or performing explicit certificate fingerprint checks for outgoing connections.
- Shell execution of user-controlled hooks: the service executes `enter_hook` via `sh -c` (see [src/service.rs](src/service.rs#L520)). Because `enter_hook` is configurable via config/IPCs, this is a command-injection risk. Recommend executing commands without a shell, using `Command::new` with explicit args, whitelisting, or otherwise restricting/or documenting this feature.
- Unsafe / FFI usage in capture backends: multiple `unsafe` blocks exist inside `input-capture` (macOS, Windows, libei). These appear to be OS FFI and low-level pointer usage (expected for capture code) but should be reviewed and tightly audited; minimize unsafe scope and validate all data coming across FFI boundaries. Example files: [input-capture/src/macos.rs](input-capture/src/macos.rs), [input-capture/src/windows/event_thread.rs](input-capture/src/windows/event_thread.rs).
- Panic/unwrap/expect usage: many places use `unwrap()`/`expect()` and `panic!` for operational errors (examples: [src/crypto.rs](src/crypto.rs), [src/dns.rs](src/dns.rs), [src/service.rs](src/service.rs)). These can be triggered by malformed input or resource failures and lead to process termination / DoS. Prefer returning errors and graceful degradation for runtime-facing code.
- Self-signed certificate handling + permissions: keys/certs are generated self-signed for device identity (see [src/crypto.rs](src/crypto.rs)). On Unix the code sets file mode to `0o400` which is good; Windows path notes `FIXME windows permissions` — Windows private key file permissions should be addressed (current code does not set them).
- IPC / local sockets: the CLI/IPC uses localhost / unix sockets and connects to `127.0.0.1:5252` for certain client paths (see [lan-mouse-ipc/src/connect.rs](lan-mouse-ipc/src/connect.rs)). Ensure local IPC endpoints are not exposed to untrusted local users (file socket permissions on Unix) and validate/authorize requests coming from local clients.
- No evidence of hardcoded credentials, telemetry exfiltration, or obfuscated code. No network callbacks to unexpected external hosts identified in this scan.
- Good cryptographic choices visible: `webrtc-dtls` usage, `ExtendedMasterSecretType::Require`, `sha2` for fingerprints. Still, the `insecure_skip_verify` mismatch (listener verifies by fingerprint; outgoing client disables verification) is the main crypto-policy inconsistency.

Risk summary (priority)

- High: Insecure DTLS client verification (MITM potential) — fix required for strong transport security.
- High: Shell execution of configurable hooks — command injection risk if untrusted input reaches `enter_hook`.
- Medium: Unsafe FFI blocks — audit required (likely necessary but sensitive surface).
- Medium: Panics/unwraps causing DoS — improve error handling for robustness.
- Low: Missing Windows file-permissions for generated private key — improve for parity with Unix.

Recommended immediate actions

1. Stop using `insecure_skip_verify = true` for outgoing connections. Either set it to `false` and rely on a proper certificate chain, or perform explicit certificate fingerprint verification immediately after connection and reject connections that don't match an authorized fingerprint. (See [src/connect.rs](src/connect.rs#L60).)
2. Replace `sh -c <string>` execution with a safer execution path: accept a command + args array, or provide a documented, whitelisted script path only. At minimum, mark `enter_hook` as dangerous and restrict which users can set it (see [src/service.rs](src/service.rs#L520)).
3. Audit all `unsafe` FFI blocks in `input-capture` and document invariants. Constrain `unsafe` scope to minimal functions and add input checks around FFI boundaries.
4. Replace critical `expect`/`unwrap` calls in runtime-facing code with proper error propagation and logging. Treat malformed network data as recoverable errors where possible.
5. Add Windows handling for private key file permissions (or document secure storage expectations for Windows installs).
6. Add tests / CI checks: lint for `insecure_skip_verify`, disallow `sh -c` usage of config-controlled strings, and run fuzzing on ProtoEvent parsing to reduce crash surface.

Notes & context

- The codebase uses DTLS via webrtc-dtls and appears to rely on certificate fingerprints for authorization on the listener side (good). However, the asymmetry where the outgoing client session disables verification is the central crypto-policy defect.
- `unsafe` usage in platform capture code is expected for low-level OS bindings; those are not inherently malicious but are high-risk by nature and must be carefully audited.

If you want, I can:

- Create a minimal patch that disables `insecure_skip_verify` and adds a client-side fingerprint check.
- Replace the `sh -c` invocation with a safer `Command`-with-args pattern and a short migration note.

Report generated by an automated code scan plus manual review of key files.
