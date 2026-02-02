# Desktop Switching

## ADDED Requirements

### Requirement: Input Desktop Targeting

The system MUST switch to the appropriate Windows desktop before emulating input events.

#### Scenario: Automatic Desktop Detection

**GIVEN** the service is running in Session 0  
**WHEN** an input emulation event is received  
**THEN** the system MUST call OpenInputDesktop to determine the current input desktop  
**AND** the system MUST switch the emulation thread to that desktop using SetThreadDesktop  
**AND** after emulation completes, the system MUST restore the previous desktop  
**AND** the system MUST close desktop handles to prevent resource leaks

#### Scenario: Login Screen Input

**GIVEN** the system is at the Windows login screen (Winlogon desktop)  
**WHEN** remote keyboard input is received  
**THEN** the system MUST successfully switch to the Winlogon desktop  
**AND** the emulated input MUST appear on the login screen  
**AND** the user MUST be able to type their password remotely

#### Scenario: UAC Prompt Input

**GIVEN** a UAC prompt is displayed (Secure desktop)  
**WHEN** remote mouse or keyboard input is received  
**THEN** the system MUST successfully switch to the Secure desktop  
**AND** the emulated input MUST interact with the UAC prompt  
**AND** the user MUST be able to click "Yes" or "No" remotely

#### Scenario: Normal Desktop Input

**GIVEN** the user is logged in to the Default desktop  
**WHEN** remote input is received  
**THEN** the system MUST switch to the Default desktop  
**AND** input emulation MUST work identically to the current implementation

### Requirement: Session Targeting

The service MUST target the console session for input emulation.

#### Scenario: Console Session Detection

**GIVEN** the service is running  
**WHEN** determining which session to send input to  
**THEN** the system MUST call WTSGetActiveConsoleSessionId  
**AND** the system MUST target the returned session ID for desktop operations

#### Scenario: Multi-User Environment

**GIVEN** multiple users are logged in (fast user switching)  
**WHEN** remote input is received  
**THEN** the system MUST send input to the console session only  
**AND** input MUST NOT affect disconnected RDP or background sessions

### Requirement: Error Handling

The system MUST handle desktop switching failures gracefully.

#### Scenario: Desktop Switch Failure

**GIVEN** OpenInputDesktop fails (desktop no longer exists)  
**WHEN** an input emulation event is received  
**THEN** the system MUST log a warning to Event Viewer  
**AND** the system MUST skip that input event  
**AND** the system MUST continue processing subsequent events  
**AND** the system MUST NOT crash or enter an error loop

#### Scenario: Desktop Handle Cleanup

**GIVEN** desktop switching succeeds  
**WHEN** emulation completes  
**THEN** all desktop handles MUST be closed with CloseDesktop  
**AND** no desktop handle leaks MUST occur over extended operation

### Requirement: Performance

Desktop switching MUST NOT introduce significant latency.

#### Scenario: Input Latency

**GIVEN** the service is emulating input  
**WHEN** desktop switching overhead is measured  
**THEN** the added latency MUST be less than 5 milliseconds per event  
**AND** the total latency MUST remain acceptable for real-time use (< 50ms end-to-end)
