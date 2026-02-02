# SendSAS Support

## ADDED Requirements

### Requirement: Secure Attention Sequence Emulation

The system MUST support remote triggering of Ctrl+Alt+Delete (Secure Attention Sequence).

#### Scenario: SendSAS API Binding

**GIVEN** the service is running in Session 0 as SYSTEM  
**WHEN** initializing the emulation module  
**THEN** the system MUST dynamically load sas.dll using LoadLibraryW  
**AND** the system MUST resolve the SendSAS function address using GetProcAddress  
**AND** if sas.dll or SendSAS is unavailable, the system MUST log a warning and disable SAS support

#### Scenario: Ctrl+Alt+Del Detection

**GIVEN** the input capture module is active  
**WHEN** the user presses Ctrl+Alt+Delete on a remote machine  
**THEN** the capture MUST detect the simultaneous Ctrl, Alt, and Delete key states  
**AND** the capture MUST generate a CaptureEvent::SecureAttentionSequence event  
**AND** the capture MUST suppress forwarding of individual Ctrl/Alt/Del key events

#### Scenario: SAS Emulation

**GIVEN** a CaptureEvent::SecureAttentionSequence is received from a remote client  
**WHEN** the emulation module processes the event  
**THEN** the system MUST call the SendSAS function from sas.dll  
**AND** the SendSAS function MUST be called with the FALSE parameter (simulate real SAS, not user invoked)  
**AND** the Windows Secure Desktop menu MUST appear

#### Scenario: Session 0 Privilege Requirement

**GIVEN** the SendSAS function is invoked  
**WHEN** called from a user-mode process (not SYSTEM in Session 0)  
**THEN** the function MUST fail or have no effect (per Windows security policy)  
**WHEN** called from a SYSTEM service in Session 0  
**THEN** the function MUST succeed and trigger the SAS screen

### Requirement: Security Considerations

The system MUST log SAS invocations for audit purposes.

#### Scenario: SAS Audit Logging

**GIVEN** a Secure Attention Sequence is triggered remotely  
**WHEN** SendSAS is called successfully  
**THEN** the system MUST log a warning-level event to Event Viewer  
**AND** the log entry MUST include the source client hostname/IP  
**AND** the log entry MUST include a timestamp

#### Scenario: SAS Rate Limiting

**GIVEN** the service is receiving SAS events  
**WHEN** multiple SAS events are received in quick succession  
**THEN** the system MUST NOT rate-limit or throttle SAS events  
**AND** each SAS event MUST be honored (Windows kernel handles abuse prevention)

### Requirement: Error Handling

The system MUST handle SAS failures gracefully.

#### Scenario: SendSAS Unavailable

**GIVEN** sas.dll cannot be loaded  
**WHEN** the service initializes  
**THEN** the system MUST log a warning indicating SAS support is disabled  
**AND** the system MUST continue operating normally  
**AND** SAS events from remote clients MUST be silently ignored

#### Scenario: SendSAS Call Failure

**GIVEN** SendSAS is available  
**WHEN** the function call fails (returns error)  
**THEN** the system MUST log an error with details  
**AND** the system MUST continue processing other input events  
**AND** the system MUST NOT crash

### Requirement: User Experience

The user MUST be able to trigger Ctrl+Alt+Delete remotely.

#### Scenario: Remote Lock Workstation

**GIVEN** the Windows desktop is unlocked  
**WHEN** the user presses Ctrl+Alt+Delete remotely  
**THEN** the SAS menu MUST appear with options: Lock, Switch User, Sign Out, Task Manager  
**AND** the user MUST be able to select "Lock" using remote mouse/keyboard

#### Scenario: Remote Unlock After Lock

**GIVEN** the workstation is locked  
**WHEN** the user presses Ctrl+Alt+Delete remotely  
**THEN** the password entry screen MUST appear  
**AND** the user MUST be able to type their password remotely and unlock

#### Scenario: Remote Task Manager Access

**GIVEN** the user needs to access Task Manager  
**WHEN** the user presses Ctrl+Alt+Delete remotely  
**THEN** the SAS menu MUST appear  
**AND** the user MUST be able to select "Task Manager" remotely
