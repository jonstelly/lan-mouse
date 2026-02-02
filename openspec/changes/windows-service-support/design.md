# Design: Windows Service Support (Watchdog Architecture)

## Architecture Overview

### Why Watchdog?

Windows Session 0 isolation prevents a service from directly injecting input into user sessions. Even with `OpenInputDesktop` and `SetThreadDesktop`, `SendInput` calls from Session 0 succeed but the input goes to Session 0's input queue—not the user's session.

The proven solution (used by deskflow, Synergy, and other KVM software) is a **watchdog architecture**:

1. **Watchdog Service** runs in Session 0 as SYSTEM
2. **Session Daemon** is spawned by the watchdog in the user's session
3. Session daemon does actual input injection (works because it's in the user's session)

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Session 0 (Isolated Service Session)                               │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  lan-mouse.exe --watchdog (Watchdog Service)                  │  │
│  │                                                               │  │
│  │  Responsibilities:                                            │  │
│  │  • SCM integration (start/stop/status)                        │  │
│  │  • Monitor active console session (WTSGetActiveConsoleSessionId) │
│  │  • Spawn session daemons with appropriate tokens              │  │
│  │  • Handle SendSAS for Ctrl+Alt+Del                            │  │
│  │  • Restart crashed session daemons                            │  │
│  │  • Log to C:\ProgramData\lan-mouse\watchdog.log               │  │
│  └────────────────────────┬──────────────────────────────────────┘  │
└───────────────────────────┼─────────────────────────────────────────┘
                            │
                            │ CreateProcessAsUser()
                            │ (token depends on context)
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  User Session (Session 1, 2, ...)                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  lan-mouse.exe daemon --spawned-by-watchdog                   │  │
│  │                                                               │  │
│  │  Responsibilities:                                            │  │
│  │  • Normal daemon operation (capture, emulate, network)        │  │
│  │  • Desktop switching for UAC (OpenInputDesktop)               │  │
│  │  • IPC server for GTK frontend                                │  │
│  │  • Signal watchdog for Ctrl+Alt+Del requests                  │  │
│  │  • Read config from ProgramData (passed by watchdog)          │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  lan-mouse-gtk (Frontend) — No changes from current           │  │
│  │  • Connects to session daemon via IPC                         │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Token Strategy

The watchdog spawns session daemons with different tokens depending on the security context:

| Context                | Token Source                   | How to Detect                               | Capabilities               |
| ---------------------- | ------------------------------ | ------------------------------------------- | -------------------------- |
| **User logged in**     | `WTSQueryUserToken(sessionId)` | `explorer.exe` in session                   | Normal user desktop access |
| **Login screen**       | Duplicate from `winlogon.exe`  | `logonui.exe` in session, no `explorer.exe` | Winlogon desktop access    |
| **UAC/Secure desktop** | User token + `TokenUIAccess=1` | Handled by session daemon                   | Secure Desktop access      |

**Token acquisition flow:**

```rust
fn get_user_token(session_id: u32, elevated: bool) -> Result<HANDLE> {
    if elevated {
        // Get winlogon.exe's token for secure desktop access
        let winlogon = find_process_in_session("winlogon.exe", session_id)?;
        let source_token = OpenProcessToken(winlogon, TOKEN_ALL_ACCESS)?;
        let token = DuplicateTokenEx(source_token, ..., TokenPrimary)?;

        // Enable UIAccess for secure desktop
        let ui_access: DWORD = 1;
        SetTokenInformation(token, TokenUIAccess, &ui_access, ...)?;

        Ok(token)
    } else {
        // Normal user token
        WTSQueryUserToken(session_id, &mut token)?;
        Ok(token)
    }
}
```

### Process Spawning

The watchdog spawns session daemons using `CreateProcessAsUser`:

```rust
fn spawn_session_daemon(token: HANDLE) -> Result<PROCESS_INFORMATION> {
    let exe_path = std::env::current_exe()?;
    let command = format!(
        r#""{}" daemon --spawned-by-watchdog --config "C:\ProgramData\lan-mouse\config.toml""#,
        exe_path.display()
    );

    let mut startup_info = STARTUPINFOW::default();
    startup_info.cb = std::mem::size_of::<STARTUPINFOW>() as u32;
    startup_info.lpDesktop = w!("winsta0\\Default").as_ptr(); // Target user's desktop

    let mut env_block = ptr::null_mut();
    CreateEnvironmentBlock(&mut env_block, token, FALSE)?;

    let mut proc_info = PROCESS_INFORMATION::default();
    CreateProcessAsUserW(
        token,
        None,
        PWSTR(command.as_mut_ptr()),
        None, // Process security
        None, // Thread security
        FALSE, // Don't inherit handles
        CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
        env_block,
        None, // Current directory
        &startup_info,
        &mut proc_info,
    )?;

    DestroyEnvironmentBlock(env_block);
    Ok(proc_info)
}
```

### Session Monitoring

The watchdog monitors session changes to respawn daemons when needed:

```rust
async fn watchdog_main_loop() {
    let mut current_session = WTSGetActiveConsoleSessionId();
    let mut daemon_process: Option<PROCESS_INFORMATION> = None;

    loop {
        // Check if session changed
        let new_session = WTSGetActiveConsoleSessionId();
        if new_session != current_session {
            log::info!("Session changed: {} -> {}", current_session, new_session);
            if let Some(proc) = daemon_process.take() {
                terminate_process(proc);
            }
            current_session = new_session;
        }

        // Check if daemon is running
        if daemon_process.is_none() || !is_process_running(&daemon_process) {
            let elevated = is_secure_desktop_active(current_session);
            let token = get_user_token(current_session, elevated)?;
            daemon_process = Some(spawn_session_daemon(token)?);
            log::info!("Spawned session daemon in session {}", current_session);
        }

        // Check for Ctrl+Alt+Del requests from daemon (via named event)
        if check_sas_event() {
            send_sas();
        }

        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}
```

### Desktop Switching (Session Daemon)

The session daemon uses desktop switching to handle UAC prompts. Since it runs in the user's session, this actually works:

```rust
fn send_input_safe(input: INPUT) {
    unsafe {
        // Open the current input desktop (may be Secure Desktop during UAC)
        let input_desktop = match OpenInputDesktop(
            DF_ALLOWOTHERACCOUNTHOOK,
            TRUE,
            DESKTOP_CREATEWINDOW | DESKTOP_HOOKCONTROL | GENERIC_WRITE,
        ) {
            Ok(desktop) => desktop,
            Err(e) => {
                log::warn!("Failed to open input desktop: {}", e);
                // Fallback: try direct SendInput (works for normal desktop)
                SendInput(&[input], std::mem::size_of::<INPUT>() as i32);
                return;
            }
        };

        let old_desktop = GetThreadDesktop(GetCurrentThreadId());
        SetThreadDesktop(input_desktop);

        SendInput(&[input], std::mem::size_of::<INPUT>() as i32);

        // Restore original desktop
        if let Ok(old) = old_desktop {
            SetThreadDesktop(old);
        }
        CloseDesktop(input_desktop);
    }
}
```

### SendSAS (Ctrl+Alt+Del)

Only the watchdog (running as SYSTEM in Session 0) can call `SendSAS`. The session daemon signals the watchdog via a named event:

**Session Daemon (requests SAS):**

```rust
fn request_ctrl_alt_del() -> Result<()> {
    let event = OpenEventW(EVENT_MODIFY_STATE, FALSE, w!("Global\\LanMouseSendSAS"))?;
    SetEvent(event)?;
    CloseHandle(event);
    Ok(())
}
```

**Watchdog (handles SAS):**

```rust
fn init_sas() -> Result<SendSasFn> {
    let sas_dll = LoadLibraryW(w!("sas.dll"))?;
    let send_sas = GetProcAddress(sas_dll, s!("SendSAS"))?;
    Ok(std::mem::transmute(send_sas))
}

fn sas_loop(send_sas: SendSasFn) {
    // Create event that session daemon can signal
    let event = CreateEventW(None, FALSE, FALSE, w!("Global\\LanMouseSendSAS"))?;

    loop {
        if WaitForSingleObject(event, 1000) == WAIT_OBJECT_0 {
            log::info!("SendSAS requested by session daemon");
            send_sas(FALSE); // FALSE = simulate real SAS
        }
    }
}
```

**Note:** `SendSAS` requires the `SoftwareSASGeneration` registry key to be set:

```
HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System
SoftwareSASGeneration = 1 (DWORD)
```

### IPC Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Watchdog ←──── Named Pipe ────→ Session Daemon                   │
│            (\\.\pipe\lan-mouse-watchdog)                         │
│                                                                  │
│ Messages:                                                        │
│ • Daemon → Watchdog: RequestSAS, Heartbeat, Shutdown            │
│ • Watchdog → Daemon: ConfigReload, Terminate                    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ GTK Frontend ←── Named Pipe ──→ Session Daemon                   │
│              (\\.\pipe\lan-mouse) — existing IPC, no changes     │
└──────────────────────────────────────────────────────────────────┘
```

### Configuration Management

**Locations:**

- Watchdog config: `C:\ProgramData\lan-mouse\config.toml`
- Session daemon: Reads from ProgramData (path passed by watchdog)
- Normal mode (no service): `%LOCALAPPDATA%\lan-mouse\config.toml`

**Migration during install:**

```rust
fn install_service() -> Result<()> {
    let user_config = PathBuf::from(env::var("LOCALAPPDATA")?)
        .join("lan-mouse").join("config.toml");
    let service_config = PathBuf::from(r"C:\ProgramData\lan-mouse\config.toml");

    if user_config.exists() && !service_config.exists() {
        fs::create_dir_all(service_config.parent().unwrap())?;
        fs::copy(&user_config, &service_config)?;
        log::info!("Migrated config to ProgramData");
    }

    // ... register service
}
```

### CLI Commands

```bash
# Install and start service
lan-mouse install-service

# Uninstall service (keeps config)
lan-mouse uninstall-service

# Uninstall and remove config
lan-mouse uninstall-service --purge

# Check service status
lan-mouse service-status
```

### Error Handling

**Watchdog errors:**

- Session daemon won't start → log error, retry after delay, report unhealthy after N failures
- Token acquisition fails → log error, retry with different strategy (elevated vs non-elevated)
- SCM communication fails → log to file, exit (SCM will restart based on recovery policy)

**Session daemon errors:**

- Desktop switch fails → log warning, fallback to direct SendInput (may not work on secure desktop)
- Watchdog pipe disconnected → exit (watchdog will respawn)
- Input emulation fails → log error, continue (don't crash entire daemon)

### Testing Strategy

**Manual testing required for:**

- Login screen input (lock workstation, type password remotely)
- UAC prompt interaction (trigger UAC, click Yes remotely)
- Ctrl+Alt+Del (press remotely, verify secure desktop appears)
- Session switch (fast user switching, verify daemon respawns)
- Service recovery (kill daemon, verify watchdog respawns it)

**Automated tests:**

- Token acquisition logic (mock Windows APIs)
- IPC protocol (unit tests with mock pipes)
- Config path detection (test service vs normal mode)
- Desktop switching logic (requires running in user session)

### Security Considerations

- **Least Privilege**: Watchdog runs as SYSTEM but never injects input directly; all input injection happens in session daemons running with appropriate user-level tokens
- **Token Isolation**: Session daemon runs with user/winlogon token (appropriate privilege level for context)
- **User Impersonation**: For certain actions, the watchdog may impersonate the user via token duplication to perform actions in the user's context (following deskflow patterns)
- **IPC Security**: Named pipes use DACL restricting to SYSTEM + Administrators to prevent privilege escalation or unauthorized access
- **Kernel Enforcement**: `SendSAS` only callable from Session 0 (kernel enforced)
- **No Remote Code Execution**: Watchdog only spawns known exe path (`std::env::current_exe()`), no arbitrary command execution

### Migration from Current Implementation

The current code has partial service support that tried to inject input directly from Session 0. This needs to be refactored:

1. **Keep:** SCM integration, service install/uninstall CLI, config path logic
2. **Remove:** Direct input injection from service mode
3. **Add:** Watchdog main loop, process spawning, token management
4. **Modify:** Session daemon detection (`--spawned-by-watchdog` flag), watchdog IPC

### Known Issues / Future Work

1. **First-time focus switch requires double border crossing (cross-platform):** When a remote device first connects, the initial Enter event may not trigger focus switch. Moving the cursor away and back to the border resolves this. This is a pre-existing issue observed on both Linux and Windows—likely a timing issue with connection establishment vs capture zone creation. **Not specific to Windows service support.**

2. **Meta+L (Windows lock) sends 'l' instead:** The Meta (Windows) key modifier may not be handled correctly for system shortcuts. Need to investigate whether the modifier press/release is being sent properly or if Windows intercepts these combinations differently.

3. **Certificate not recognized for outbound capture:** When this computer sends input to a remote, the remote may prompt for authorization even if certificates are configured. The capture side may be using a different certificate path than expected. Need to verify cert_path resolution matches between capture and emulation modes.

### Fallback Behavior

When the service is not installed or cannot be reached:

1. **GTK/CLI launches normally** - Spawns daemon as child process (existing behavior)
2. **Daemon runs as user** - Works for normal desktop, fails for login screen/UAC
3. **No UAC self-elevation** - Unlike deskflow, we don't attempt self-elevation; service is required for elevated contexts

This provides graceful degradation: users without the service get current functionality; users who need login screen/UAC support install the service.

### Open Questions

1. **Heartbeat interval:** How often should session daemon ping watchdog? (Recommendation: 1 second)
2. **Respawn delay:** How long to wait before respawning crashed daemon? (Recommendation: 500ms initial, exponential backoff to 10s max)
3. **Multi-session:** Should we support spawning daemons in multiple sessions simultaneously? (Recommendation: No for v1, console session only)

### References

- [Microsoft Docs: Windows Services](https://docs.microsoft.com/en-us/windows/win32/services/)
- [Microsoft Docs: User Account Control](https://docs.microsoft.com/en-us/windows/security/identity-protection/user-account-control/)
- [Microsoft Docs: Winlogon](https://docs.microsoft.com/en-us/windows/win32/winlogon/winlogon)
- [Microsoft Docs: Session 0 Isolation](https://docs.microsoft.com/en-us/windows/win32/services/service-changes-for-windows-vista)
