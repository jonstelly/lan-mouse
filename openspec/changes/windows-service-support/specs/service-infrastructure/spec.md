# Service Infrastructure

## ADDED Requirements

### Requirement: Windows Service Registration

The system MUST support registration as a Windows service through the Service Control Manager.

#### Scenario: Service Creation

**GIVEN** a user with Administrator privileges  
**WHEN** the service installation command is executed  
**THEN** the system MUST register itself with the Windows Service Control Manager  
**AND** the service MUST be configured to start automatically on system boot  
**AND** the service MUST run under the NT AUTHORITY\SYSTEM account

#### Scenario: Service State Reporting

**GIVEN** the service is registered with SCM  
**WHEN** the service is started by SCM  
**THEN** the service MUST report SERVICE_START_PENDING within 30 seconds  
**AND** the service MUST report SERVICE_RUNNING after successful initialization  
**AND** the service MUST report SERVICE_STOP_PENDING when receiving a stop signal  
**AND** the service MUST report SERVICE_STOPPED after graceful shutdown completes

#### Scenario: Single Binary Detection

**GIVEN** the lan-mouse.exe binary is executed  
**WHEN** the process starts  
**THEN** the system MUST attempt to register as a service dispatcher first  
**AND** if service dispatcher registration fails, the system MUST fall back to normal execution mode  
**AND** normal execution mode MUST spawn the daemon and GTK frontend as currently implemented

### Requirement: Event Logging

The service MUST log operational events to the Windows Event Viewer.

#### Scenario: Service Lifecycle Logging

**GIVEN** the service is running  
**WHEN** the service starts successfully  
**THEN** an informational event MUST be logged to Event Viewer  
**WHEN** the service encounters an error during initialization  
**THEN** an error event MUST be logged with diagnostic details  
**WHEN** the service stops  
**THEN** an informational event MUST be logged

#### Scenario: Runtime Error Logging

**GIVEN** the service is running  
**WHEN** a desktop switch operation fails  
**THEN** a warning event MUST be logged with the error details  
**WHEN** input emulation fails  
**THEN** a warning event MUST be logged  
**AND** the service MUST continue operating with graceful degradation

### Requirement: Service Control Handlers

The service MUST respond to control signals from SCM.

#### Scenario: Stop Signal Handling

**GIVEN** the service is running  
**WHEN** SCM sends a SERVICE_CONTROL_STOP signal  
**THEN** the service MUST report SERVICE_STOP_PENDING within 3 seconds  
**AND** the service MUST perform graceful shutdown (close connections, release resources)  
**AND** the service MUST report SERVICE_STOPPED within 30 seconds

#### Scenario: Shutdown Signal Handling

**GIVEN** the service is running  
**WHEN** the system is shutting down  
**THEN** the service MUST respond to SERVICE_CONTROL_SHUTDOWN  
**AND** the service MUST complete shutdown within the system shutdown timeout

### Requirement: Backward Compatibility

The system MUST maintain existing functionality when not running as a service.

#### Scenario: Normal Mode Operation

**GIVEN** the service is not installed  
**WHEN** lan-mouse.exe is executed normally  
**THEN** the system MUST spawn the daemon process as a child  
**AND** the GTK frontend MUST launch  
**AND** all existing capture/emulation functionality MUST work as before

#### Scenario: Graceful Degradation

**GIVEN** the service installation fails  
**WHEN** the user attempts to run lan-mouse  
**THEN** the system MUST fall back to normal mode  
**AND** a clear error message MUST be displayed explaining the limitation  
**AND** the message MUST suggest running `lan-mouse install-service` as Administrator
