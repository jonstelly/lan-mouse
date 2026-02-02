# Named Pipe IPC

## ADDED Requirements

### Requirement: Pipe Creation

The service MUST create a named pipe for inter-process communication on Windows.

#### Scenario: Named Pipe Initialization

**GIVEN** the service is starting in service mode  
**WHEN** initializing the IPC listener  
**THEN** the system MUST create a named pipe at `\\.\pipe\lan-mouse`  
**AND** the pipe MUST be configured as a byte-mode pipe (PIPE_TYPE_BYTE | PIPE_READMODE_BYTE)  
**AND** the pipe MUST use blocking mode (PIPE_WAIT)  
**AND** the pipe MUST allow multiple clients (PIPE_ACCESS_DUPLEX)

#### Scenario: Pipe Security

**GIVEN** a named pipe is being created  
**WHEN** setting security attributes  
**THEN** the system MUST construct a DACL restricting access to:

- NT AUTHORITY\SYSTEM (Full Control)
- BUILTIN\Administrators (Full Control)  
  **AND** the DACL MUST be applied via SECURITY_ATTRIBUTES during CreateNamedPipe  
  **AND** non-administrator users MUST be denied access

### Requirement: Client Connection

Frontend applications MUST connect to the service via named pipe.

#### Scenario: GTK Frontend Connection

**GIVEN** the service is running with named pipe IPC  
**WHEN** the GTK frontend starts  
**THEN** the frontend MUST attempt to connect to `\\.\pipe\lan-mouse`  
**AND** if the connection succeeds, the frontend MUST use the pipe for all IPC  
**AND** the frontend MUST serialize FrontendRequest and deserialize FrontendEvent using the existing protocol

#### Scenario: CLI Frontend Connection

**GIVEN** the service is running  
**WHEN** lan-mouse-cli executes a command  
**THEN** the CLI MUST connect to the named pipe  
**AND** the CLI MUST send the request over the pipe  
**AND** the CLI MUST receive the response over the pipe

### Requirement: Backward Compatibility

The system MUST support both named pipe and TCP IPC during the transition period.

#### Scenario: Pipe Connection Failure Fallback

**GIVEN** the frontend attempts to connect to a named pipe  
**WHEN** the pipe does not exist (service not installed or old version)  
**THEN** the frontend MUST fall back to TCP connection at 127.0.0.1:5252  
**AND** all IPC functionality MUST work identically over TCP

#### Scenario: Legacy Service Compatibility

**GIVEN** an older version of the daemon is running (TCP only)  
**WHEN** a new frontend attempts to connect  
**THEN** the frontend MUST detect the absence of the named pipe  
**AND** the frontend MUST successfully connect via TCP  
**AND** no errors MUST be displayed to the user

### Requirement: Protocol Compatibility

The IPC protocol MUST remain unchanged regardless of transport.

#### Scenario: Protocol Serialization

**GIVEN** a FrontendRequest or FrontendEvent  
**WHEN** transmitted over named pipe  
**THEN** the serialization format MUST be identical to TCP IPC  
**AND** message framing MUST be preserved  
**AND** no protocol changes MUST be required

#### Scenario: Asynchronous Operation

**GIVEN** the named pipe IPC is in use  
**WHEN** multiple frontend requests are pending  
**THEN** the system MUST handle requests asynchronously using Tokio  
**AND** the system MUST maintain the same concurrency guarantees as TCP IPC

### Requirement: Error Handling

The system MUST handle pipe failures gracefully.

#### Scenario: Pipe Disconnection

**GIVEN** a frontend is connected via named pipe  
**WHEN** the service stops or crashes  
**THEN** the frontend MUST detect the pipe disconnection  
**AND** the frontend MUST display an appropriate error message  
**AND** the frontend MUST NOT crash

#### Scenario: Access Denied

**GIVEN** a non-administrator user attempts to connect to the pipe  
**WHEN** the connection is attempted  
**THEN** the system MUST return an access denied error  
**AND** the error message MUST explain that the service requires Administrator privileges to connect

### Requirement: Performance

Named pipe IPC MUST have lower latency than TCP loopback.

#### Scenario: IPC Latency

**GIVEN** the service and frontend are communicating via named pipe  
**WHEN** measuring round-trip latency for a simple request/response  
**THEN** the latency MUST be less than 1 millisecond  
**AND** the latency MUST be lower than TCP loopback (typically 0.1ms vs 0.5ms)
