# Service Management CLI

## ADDED Requirements

### Requirement: Service Installation

The system MUST provide a command to install the Windows service.

#### Scenario: Service Install Command

**GIVEN** a user with Administrator privileges  
**WHEN** running `lan-mouse install-service`  
**THEN** the system MUST register the service with SCM  
**AND** the service MUST be configured to auto-start on boot  
**AND** the service MUST be configured to run as NT AUTHORITY\SYSTEM  
**AND** the service MUST start immediately after installation  
**AND** a success message MUST be displayed

#### Scenario: Config Migration on Install

**GIVEN** a user has an existing config at `%LOCALAPPDATA%\lan-mouse\config.toml`  
**WHEN** running `lan-mouse install-service`  
**THEN** the system MUST copy the user config to `C:\ProgramData\lan-mouse\config.toml`  
**AND** if a ProgramData config already exists, the system MUST preserve it (no overwrite)  
**AND** the user MUST be informed of the config location in the success message

#### Scenario: No Existing Config

**GIVEN** no user config exists  
**WHEN** running `lan-mouse install-service`  
**THEN** the service MUST install successfully  
**AND** the service MUST create a default config at `C:\ProgramData\lan-mouse\config.toml`  
**AND** the default config MUST match the application defaults

#### Scenario: Service Already Installed

**GIVEN** the service is already installed  
**WHEN** running `lan-mouse install-service`  
**THEN** the system MUST detect the existing service  
**AND** the system MUST display an error message indicating the service is already installed  
**AND** the system MUST NOT duplicate the service registration

#### Scenario: Insufficient Privileges

**GIVEN** a user without Administrator privileges  
**WHEN** running `lan-mouse install-service`  
**THEN** the system MUST detect insufficient privileges  
**AND** the system MUST display an error message requesting Administrator elevation  
**AND** the system MUST exit with a non-zero status code

### Requirement: Service Uninstallation

The system MUST provide a command to uninstall the Windows service.

#### Scenario: Service Uninstall Command

**GIVEN** the service is installed and running  
**WHEN** running `lan-mouse uninstall-service`  
**THEN** the system MUST stop the service gracefully  
**AND** the system MUST wait for the service to reach STOPPED state  
**AND** the system MUST delete the service registration from SCM  
**AND** a success message MUST be displayed

#### Scenario: Config Preservation on Uninstall

**GIVEN** the service is installed with config at `C:\ProgramData\lan-mouse\config.toml`  
**WHEN** running `lan-mouse uninstall-service`  
**THEN** the system MUST preserve the config by default  
**AND** the user MUST be informed that the config was preserved  
**AND** the config location MUST be displayed in the success message

#### Scenario: Config Deletion on Uninstall

**GIVEN** the service is installed  
**WHEN** running `lan-mouse uninstall-service --purge`  
**THEN** the system MUST delete the service registration  
**AND** the system MUST delete `C:\ProgramData\lan-mouse\` directory and all contents  
**AND** a success message MUST indicate the config was removed

#### Scenario: Service Not Installed

**GIVEN** the service is not installed  
**WHEN** running `lan-mouse uninstall-service`  
**THEN** the system MUST detect the service is not registered  
**AND** the system MUST display an informational message  
**AND** the system MUST exit with status code 0 (not an error)

#### Scenario: Service Stop Timeout

**GIVEN** the service is running but unresponsive  
**WHEN** running `lan-mouse uninstall-service`  
**THEN** the system MUST wait up to 30 seconds for graceful shutdown  
**AND** if the service does not stop, the system MUST forcefully terminate it  
**AND** the system MUST proceed with service deletion  
**AND** a warning MUST be logged indicating forced termination

### Requirement: Service Status Query

The system MUST provide a command to query service status.

#### Scenario: Service Status Command - Running

**GIVEN** the service is installed and running  
**WHEN** running `lan-mouse service-status`  
**THEN** the system MUST display "Service Status: Running"  
**AND** the system MUST display the service PID  
**AND** the system MUST display the startup type (e.g., "Automatic")  
**AND** the system MUST display the config location: `C:\ProgramData\lan-mouse\config.toml`

#### Scenario: Service Status Command - Stopped

**GIVEN** the service is installed but not running  
**WHEN** running `lan-mouse service-status`  
**THEN** the system MUST display "Service Status: Stopped"  
**AND** the system MUST indicate the service is not currently active  
**AND** the system MUST suggest running `sc start lan-mouse` or `net start lan-mouse`

#### Scenario: Service Status Command - Not Installed

**GIVEN** the service is not installed  
**WHEN** running `lan-mouse service-status`  
**THEN** the system MUST display "Service Status: Not Installed"  
**AND** the system MUST suggest running `lan-mouse install-service` as Administrator

#### Scenario: Service Status Command - Error State

**GIVEN** the service is in an error state (e.g., failed to start)  
**WHEN** running `lan-mouse service-status`  
**THEN** the system MUST display "Service Status: Error"  
**AND** the system MUST retrieve and display the last error message  
**AND** the system MUST suggest checking Event Viewer for details

### Requirement: Help and Documentation

The system MUST provide help text for service management commands.

#### Scenario: Help Text

**GIVEN** a user runs `lan-mouse --help`  
**WHEN** displaying available commands  
**THEN** the help text MUST include:

- `install-service`: Install and start the Windows service
- `uninstall-service [--purge]`: Stop and uninstall the Windows service
- `service-status`: Display service status and configuration

#### Scenario: Command-Specific Help

**GIVEN** a user runs `lan-mouse install-service --help`  
**WHEN** displaying command help  
**THEN** the system MUST explain the command's purpose  
**AND** the system MUST note that Administrator privileges are required  
**AND** the system MUST explain config migration behavior

### Requirement: Exit Codes

Service management commands MUST use appropriate exit codes.

#### Scenario: Successful Operation

**GIVEN** a service management command completes successfully  
**WHEN** the command exits  
**THEN** the exit code MUST be 0

#### Scenario: Privilege Error

**GIVEN** a command requires Administrator privileges but is run as normal user  
**WHEN** the command exits  
**THEN** the exit code MUST be 1  
**AND** the error message MUST explain privilege requirements

#### Scenario: Service Not Found

**GIVEN** an operation targets a non-existent service  
**WHEN** the command exits  
**THEN** the exit code MUST be 2  
**AND** the error message MUST explain the service is not installed

#### Scenario: Service Operation Failure

**GIVEN** a service operation fails (e.g., cannot stop service)  
**WHEN** the command exits  
**THEN** the exit code MUST be 3  
**AND** the error message MUST include diagnostic details
