# Proposal: Windows Service Support for Elevated Input

**Change ID:** `windows-service-support`  
**Status:** Draft (Revised)  
**Created:** 2026-02-02  
**Revised:** 2026-02-03

## Why

Remote input on Windows fails at the login screen, UAC prompts, and other secure desktops because user-mode processes cannot inject input into these protected contexts. This prevents users from typing passwords or interacting with elevated applications remotely, severely limiting the utility of lan-mouse on Windows.

Running as Administrator is insufficient due to Windows Session 0 isolation and User Interface Privilege Isolation (UIPI). A Windows service running as SYSTEM in Session 0 **cannot directly inject input into user sessions**—`SendInput` calls succeed but the input goes to Session 0's input queue, not the user's session.

The solution, proven by deskflow, is a **watchdog architecture**: a Windows service acts as a session manager that spawns lan-mouse daemon processes inside each user session, using the appropriate token for the security context (user token for normal desktop, winlogon token for secure desktops).

This change unblocks the primary Windows use case: remote login and UAC interaction.

## Problem Statement

Lan-mouse on Windows cannot inject input into secure desktop contexts (login screen, UAC prompts, elevated windows) because:

1. **Session 0 Isolation**: Services run in an isolated session and cannot inject input to user sessions
2. **UIPI**: User-mode processes cannot send input to higher-integrity processes
3. **Secure Desktop**: The UAC prompt runs on a separate desktop that blocks input from normal processes

Users report that remote keyboard/mouse control fails at the Windows login screen, making the software unusable for critical workflows like remote server management.

Related: [lan-mouse#127](https://github.com/feschber/lan-mouse/issues/127)

## Solution Overview

Implement a **session watchdog architecture** where:

1. **Service (Watchdog)**: A Windows service running as SYSTEM in Session 0 that:
   - Monitors the active console session via `WTSGetActiveConsoleSessionId`
   - Spawns lan-mouse daemon processes in user sessions via `CreateProcessAsUser`
   - Manages process lifecycle (restart on crash, respawn on session change)
   - Handles Ctrl+Alt+Del via `SendSAS` (only callable from Session 0)

2. **Session Daemon**: A lan-mouse daemon process spawned by the watchdog that:
   - Runs in the user's session with appropriate token
   - Performs actual input capture and emulation
   - Uses desktop switching to access secure desktops (UAC prompts)
   - Communicates with the watchdog via IPC for lifecycle management

This approach:

- Maintains cross-platform daemon architecture (session daemon is the normal daemon)
- Enables input injection at login screen (using winlogon token)
- Enables input injection at UAC prompts (using desktop switching from user session)
- Provides graceful degradation (service is optional; normal mode unchanged)
- Follows proven patterns (same architecture as deskflow)

## Scope

This change introduces five new capabilities:

1. **Watchdog Service** — Session monitoring, process spawning with appropriate tokens, lifecycle management
2. **Session Daemon Mode** — Daemon that runs in user session, spawned by watchdog (reuses existing daemon)
3. **Desktop Switching** — `OpenInputDesktop` / `SetThreadDesktop` for secure desktop injection (from session daemon)
4. **SendSAS Support** — Ctrl+Alt+Del forwarding via `SendSAS` API (from watchdog only)
5. **Service Management CLI** — Commands to install/uninstall/configure service

## Configuration Strategy

**Problem:** Service runs as SYSTEM, cannot access `%LOCALAPPDATA%\<user>\AppData\Local\lan-mouse\`.

**Solution:** Windows follows standard service config patterns:

| Mode                 | Config Location                         | Reasoning                          |
| -------------------- | --------------------------------------- | ---------------------------------- |
| **Service/Watchdog** | `C:\ProgramData\lan-mouse\config.toml`  | Machine-wide, accessible to SYSTEM |
| **Session Daemon**   | Inherits from watchdog (passed via arg) | Consistency with watchdog          |
| **Normal (user)**    | `%LOCALAPPDATA%\lan-mouse\config.toml`  | Per-user, backward compatible      |

Session daemons spawned by the watchdog inherit the ProgramData config path via command-line argument.

## Fallback Behavior

When the service is not installed, lan-mouse operates in its current mode:

- GTK spawns daemon as child process
- Input works on normal user desktop
- Login screen and UAC prompts are inaccessible (current limitation)

This provides graceful degradation—users who don't need elevated access don't need to install the service.

## Non-Goals

- RDP session targeting (console session only for v1)
- Multi-user simultaneous session support (single active session for v1)
- Code signing infrastructure (documented separately)
- UAC self-elevation (unlike deskflow, we require the service for elevated contexts)

## Implementation Phases

See [tasks.md](tasks.md) for detailed breakdown.

1. Watchdog service infrastructure (SCM, session monitoring)
2. Process spawning with token management (user token, winlogon token, UIAccess)
3. Desktop switching in emulation backend (for UAC from session daemon)
4. Watchdog-daemon IPC for SendSAS and lifecycle
5. SendSAS Ctrl+Alt+Del support (from watchdog)
6. CLI commands for service install/uninstall
7. Config path logic and migration

## Success Criteria

- [ ] User can install service via `lan-mouse install-service`
- [ ] Service auto-starts on boot, spawns session daemon automatically
- [ ] GTK connects to session daemon (same IPC as before)
- [ ] Ctrl+Alt+Del works remotely via SendSAS
- [ ] Fallback mode works when service not installed

## References

- [Design Document](design.md)
- [Tasks](tasks.md)
- [ ] Remote typing works on Windows login screen
- [ ] UAC prompts can be interacted with remotely
- [ ] Ctrl+Alt+Del can be triggered remotely
- [ ] Session daemon respawns if it crashes
- [ ] Session daemon respawns on session change (user switch, lock/unlock)
- [ ] Uninstalling service restores previous behavior (GTK spawns daemon)
- [ ] Config migrates correctly between normal and service modes

## Security Considerations

- Watchdog runs as SYSTEM but only spawns processes; no direct input injection
- Session daemon runs with user token (or winlogon token for login screen)
- `TokenUIAccess` is set on spawned process tokens for secure desktop access
- Named pipe IPC restricts to Administrators and SYSTEM only
- SendSAS only callable from Session 0 (watchdog), not user-mode processes

## Breaking Changes

None. Service installation is opt-in; existing workflows unchanged.

## References

- [deskflow MSWindowsWatchdog](https://github.com/deskflow/deskflow/blob/main/src/lib/platform/MSWindowsWatchdog.cpp)
- [docs/windows-elevated-plan.md](../../../docs/windows-elevated-plan.md)
- [lan-mouse#127](https://github.com/feschber/lan-mouse/issues/127)
- [windows-service crate](https://crates.io/crates/windows-service)
