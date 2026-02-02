# Tasks: Windows Service Support (Watchdog Architecture)

## Phase 1: Watchdog Service Infrastructure

### 1.1 Watchdog Entry Point

- [ ] Add `--watchdog` CLI flag to indicate watchdog mode
- [ ] Modify service dispatcher to run watchdog loop instead of daemon
- [ ] Set up watchdog logging to `C:\ProgramData\lan-mouse\watchdog.log`
- [ ] Implement graceful shutdown on SCM stop signal

### 1.2 Session Monitoring

- [ ] Implement `WTSGetActiveConsoleSessionId()` wrapper
- [ ] Add session change detection loop (poll every 500ms)
- [ ] Log session transitions

### 1.3 Basic Process Spawning

- [ ] Implement `spawn_session_daemon()` with `CreateProcessAsUser`
- [ ] Pass `--spawned-by-watchdog` flag to spawned daemon
- [ ] Create environment block for spawned process
- [ ] Track spawned process handle for monitoring

## Phase 2: Token Management

### 2.1 User Token Acquisition

- [ ] Implement `WTSQueryUserToken()` wrapper for logged-in user
- [ ] Handle case where no user is logged in (wait/retry)
- [ ] Test spawning process with user token

### 2.2 Winlogon Token (Login Screen)

- [ ] Implement `find_process_in_session("winlogon.exe", session_id)`
- [ ] Enumerate processes with `CreateToolhelp32Snapshot`
- [ ] Match process to session via `ProcessIdToSessionId`
- [ ] Duplicate winlogon token with `DuplicateTokenEx`
- [ ] Test spawning process with winlogon token

### 2.3 UIAccess Token (Secure Desktop)

- [ ] Implement `SetTokenInformation(TokenUIAccess, 1)`
- [ ] Test if UIAccess allows secure desktop access
- [ ] Document any signing requirements for UIAccess

### 2.4 Context Detection

- [ ] Detect login screen: `logonui.exe` present, no `explorer.exe`
- [ ] Choose appropriate token based on context
- [ ] Handle transition between contexts (re-spawn with new token)

## Phase 3: Session Daemon Modifications

### 3.1 Spawned Mode Detection

- [ ] Add `--spawned-by-watchdog` flag parsing
- [ ] Skip IPC socket creation if spawned (watchdog manages lifecycle)
- [ ] Use config path from `--config` argument when spawned

### 3.2 Desktop Switching (Already Partially Implemented)

- [ ] Verify `OpenInputDesktop` works from user session
- [ ] Verify `SetThreadDesktop` + `SendInput` works for UAC
- [ ] Clean up existing desktop switching code (remove Session 0 workarounds)

### 3.3 Daemon Lifecycle

- [ ] Exit cleanly when watchdog pipe disconnects
- [ ] Implement heartbeat to watchdog (optional, for monitoring)

## Phase 4: Watchdog-Daemon IPC

### 4.1 Named Pipe Setup

- [ ] Create `\\.\pipe\lan-mouse-watchdog` in watchdog
- [ ] Connect from session daemon on startup
- [ ] Set appropriate DACL (SYSTEM + Administrators)

### 4.2 IPC Protocol

- [ ] Define message types: `RequestSAS`, `Heartbeat`, `Shutdown`, `ConfigReload`
- [ ] Implement serialization (simple binary or JSON)
- [ ] Handle pipe disconnection gracefully

### 4.3 Daemon Health Monitoring

- [ ] Track last heartbeat time
- [ ] Kill and respawn unresponsive daemons
- [ ] Implement exponential backoff for repeated failures

## Phase 5: SendSAS (Ctrl+Alt+Del)

### 5.1 SAS Infrastructure

- [ ] Load `sas.dll` dynamically in watchdog
- [ ] Get `SendSAS` function pointer
- [ ] Create `Global\LanMouseSendSAS` event

### 5.2 SAS Request Flow

- [ ] Session daemon: detect Ctrl+Alt+Del key combo
- [ ] Session daemon: signal event (or send IPC message)
- [ ] Watchdog: call `SendSAS(FALSE)` when signaled

### 5.3 Registry Configuration

- [ ] Document `SoftwareSASGeneration` registry requirement
- [ ] Optionally: set registry during `install-service` (with user consent)

## Phase 6: CLI Commands (Partially Done)

### 6.1 Install Service

- [x] Register service with SCM
- [x] Set service to auto-start
- [ ] Migrate config from `%LOCALAPPDATA%` to `ProgramData`
- [ ] Set recovery policy (restart on failure)

### 6.2 Uninstall Service

- [x] Stop service if running
- [x] Remove service registration
- [ ] Add `--purge` flag to remove ProgramData config

### 6.3 Service Status

- [x] Query SCM for service state
- [ ] Show watchdog PID and session daemon PID
- [ ] Show current session being controlled

## Phase 7: Testing & Polish

### 7.1 Manual Testing Checklist

- [ ] Normal operation: service starts, daemon spawns, input works
- [ ] Login screen: lock workstation, type password remotely
- [ ] UAC: trigger UAC prompt, click button remotely
- [ ] Ctrl+Alt+Del: press remotely, secure desktop appears
- [ ] Session switch: fast user switching, daemon respawns
- [ ] Service stop: `sc stop lan-mouse`, daemon terminates
- [ ] Service crash recovery: kill daemon, watchdog respawns
- [ ] Fallback mode: service not installed, GTK works normally on user desktop
- [ ] Fallback mode: verify clear error when login screen/UAC attempted without service

### 7.2 Code Cleanup

- [ ] Remove obsolete Session 0 direct injection code
- [ ] Update documentation in `DOC.md`
- [ ] Update `README.md` with service usage instructions
- [ ] Add Windows service section to `docs/windows-elevated.md`

### 7.3 Error Handling

- [ ] Graceful degradation when token acquisition fails
- [ ] Clear error messages for common issues
- [ ] Log rotation for watchdog log file

## Phase 8: Known Issues Investigation

### 8.1 First-Time Focus Switch (Cross-Platform, Pre-existing)

- [ ] Reproduce issue: connect two devices, observe first border crossing fails
- [ ] Add debug logging to capture zone creation and Enter event handling
- [ ] Trace timing: connection establishment vs capture zone registration
- [ ] Check if `ProtoEvent::Enter` is received but not processed on first attempt
- [ ] Investigate race condition between `CaptureType::EnterOnly` registration and incoming events
- [ ] Fix timing/ordering issue or add retry logic

### 8.2 Meta+L (Windows Lock) Not Working

- [ ] Verify scancode mapping: Linux KeyLeftMeta (125) → Windows 0xE05B
- [ ] Add debug logging to `key_event()` to confirm Meta key press/release sent
- [ ] Test if Meta key alone works (tap Win key to open Start menu)
- [ ] Test if other Meta combinations work (Meta+E, Meta+R)
- [ ] Research if Windows intercepts Win+L at lower level than SendInput
- [ ] If intercepted: may need SendSAS-like approach or different API
- [ ] Check modifier state tracking in emulation (is Meta held when 'L' sent?)

### 8.3 Certificate Path Mismatch on Capture Side

- [ ] Add logging to show cert_path on daemon startup
- [ ] Verify `is_service()` returns correct value in capture context
- [ ] Check if capture uses different config loading path than emulation
- [ ] Compare fingerprint sent during capture vs fingerprint in remote's authorized list
- [ ] Ensure ProgramData cert is copied/shared correctly during service install
- [ ] Test: manually verify cert files match between capture and emulation configs

## Dependencies

- `windows-service` crate (v0.7) - already added
- `windows` crate for Win32 APIs - already in use
- No new crate dependencies expected

## Risks & Mitigations

| Risk                              | Mitigation                                                    |
| --------------------------------- | ------------------------------------------------------------- |
| UIAccess requires signed binary   | Test early; may need to ship signed or use different approach |
| Winlogon token acquisition denied | Run watchdog as SYSTEM with SE_DEBUG_PRIVILEGE                |
| Named pipe security issues        | Use restrictive DACL, document security model                 |
| Session change race conditions    | Use proper synchronization, test thoroughly                   |

## Success Criteria

- [ ] `lan-mouse install-service` creates working watchdog service
- [ ] Input works on normal desktop without GTK running
- [ ] Input works on Windows login screen
- [ ] Input works during UAC prompts
- [ ] Ctrl+Alt+Del can be sent remotely
- [ ] Service survives session changes and daemon crashes
- [ ] Fallback mode works (service not installed, normal operation continues)

## References
