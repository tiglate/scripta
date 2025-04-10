@echo off
setlocal enabledelayedexpansion

rem --- Script Information ---
rem Name:        SFTP_Download_Delete.bat
rem Description: Connects to an SFTP server using PSFTP, downloads a specified file,
rem              saves it locally, and deletes the file from the SFTP server.
rem              Retrieves SFTP password using a VBS script. Logs actions.
rem Author:      HAL 9000
rem Date:        2025-04-10 (Revised: 2025-04-10 for date prefix in log filename)
rem Version:     1.5
rem Requirements: psftp.exe (from PuTTY) must be in the system PATH or script directory.
rem               cscript.exe (standard Windows component).
rem Usage:       SFTP_Download_Delete.bat [SourceServer] [SourcePath] [FTPUserName] [FTPBatchScript] [FileName] [TargetPath] [PasswordManagerServer] [PasswordRetrievalScriptPath] [PasswordFile] [LogName]
rem Example:     SFTP_Download_Delete.bat sftpsrv.example.com /remote/data user1 sftp_commands.txt data.zip C:\Downloads\Incoming pwdmgr.example.com C:\Scripts\GetPassword.vbs temp_pwd.txt sftp_download.log
rem ---

rem --- Parameter Validation (Initial check for up to 9) ---
rem We need at least 9 parameters before we can SHIFT to check for the 10th
if "%~9"=="" (
    echo "ERROR: Missing parameters. 10 parameters are required. (Detected missing parameters up to 9th)"
    echo "Usage: %~nx0 [SourceServer] [SourcePath] [FTPUserName] [FTPBatchScript] [FileName] [TargetPath] [PasswordManagerServer] [PasswordRetrievalScriptPath] [PasswordFile] [LogName]"
    exit /b 1
)

rem --- Assign Parameters to Variables (Parameters 1 through 9) ---
set "SourceServer=%~1"
set "SourcePathParam=%~2"
set "FTPUserName=%~3"
set "FTPBatchScriptParam=%~4"
set "FileNameParam=%~5"
set "TargetPathParam=%~6"
set "PasswordManagerServer=%~7"
set "PasswordRetrievalScriptPath=%~8"
set "PasswordFileParam=%~9"

rem --- Shift parameters to access the 10th parameter ---
SHIFT

rem --- Parameter Validation (Check for 10th parameter after SHIFT) ---
rem The original 10th parameter is now accessible as %9
if "%~9"=="" (
    echo "ERROR: Missing 10th parameter (LogName). 10 parameters are required. (Detected missing 10th parameter after SHIFT)"
    echo "Usage: %~nx0 [SourceServer] [SourcePath] [FTPUserName] [FTPBatchScript] [FileName] [TargetPath] [PasswordManagerServer] [PasswordRetrievalScriptPath] [PasswordFile] [LogName]"
    exit /b 1
)

rem --- Assign 10th Parameter ---
set "LogNameParam=%~9"

rem --- Define Script and File Paths ---
set "ScriptDir=%~dp0"
set "FullPasswordFilePath=%ScriptDir%%PasswordFileParam%"
set "FullFTPBatchScriptPath=%ScriptDir%%FTPBatchScriptParam%"

rem --- Define Log File Path ---
rem Go up one level from TargetPath and into LOGS directory
for %%F in ("%TargetPathParam%\..") do set "LogDir=%%~fF\LOGS"

rem --- Get Current Date for Log Filename (YYYY-MM-DD format) ---
set "CurrentDate="
set LogDateWarning=
for /f "tokens=2 delims==" %%A in ('wmic os get LocalDateTime /value 2^>nul') do set DateTime=%%A
if defined DateTime (
    set "CurrentDate=%DateTime:~0,4%-%DateTime:~4,2%-%DateTime:~6,2%"
    echo INFO: Using date prefix for log file: %CurrentDate%
) else (
    echo WARNING: Could not get current date via WMI for log file naming. Using original name only.
    set LogDateWarning=true REM Set flag to log this warning later
    set "CurrentDate=" REM Ensure it's empty if WMI failed
)

rem --- Construct Final Log Filename ---
if defined CurrentDate (
    set "FinalLogName=%CurrentDate%-%LogNameParam%"
) else (
    set "FinalLogName=%LogNameParam%"
)
set "LogFile=%LogDir%\%FinalLogName%"
echo INFO: Full log file path: %LogFile%

rem --- Ensure Log Directory Exists ---
if not exist "%LogDir%" (
    echo "INFO: Creating log directory: %LogDir%"
    mkdir "%LogDir%"
    if errorlevel 1 (
        echo "ERROR: Failed to create log directory: %LogDir%. Check permissions."
        call :LogMsg "ERROR: Failed to create log directory: %LogDir%" NOEXIT
        exit /b 3
    )
)

rem --- Start Logging ---
call :LogMsg "-------------------------------------------------"
call :LogMsg "INFO: Script execution started."
if defined LogDateWarning call :LogMsg "WARN: Could not get current date via WMI for log file naming. Using original name only."

rem --- Log Parameters (excluding password file name for security, though path is known) ---
call :LogMsg "PARAM: SourceServer = %SourceServer%"
call :LogMsg "PARAM: SourcePath = %SourcePathParam%"
call :LogMsg "PARAM: FTPUserName = %FTPUserName%"
call :LogMsg "PARAM: FTPBatchScript = %FTPBatchScriptParam%"
call :LogMsg "PARAM: FileName = %FileNameParam%"
call :LogMsg "PARAM: TargetPath = %TargetPathParam%"
call :LogMsg "PARAM: PasswordManagerServer = %PasswordManagerServer%"
call :LogMsg "PARAM: PasswordRetrievalScriptPath = %PasswordRetrievalScriptPath%"
call :LogMsg "PARAM: PasswordFile = (Filename: %PasswordFileParam% in script directory)"
call :LogMsg "PARAM: LogName = %LogNameParam% (Base Name)"
call :LogMsg "INFO: Log file path: %LogFile% (Full Path)"

rem --- Password Retrieval ---
echo INFO: Attempting to retrieve password for user '%FTPUserName%' from '%PasswordManagerServer%'...
call :LogMsg "INFO: Attempting to retrieve password using VBS script: %PasswordRetrievalScriptPath%"
call :LogMsg "INFO: Password file target: %FullPasswordFilePath%"

rem Ensure password file does not exist before running script
if exist "%FullPasswordFilePath%" (
    call :LogMsg "WARN: Pre-existing password file found. Deleting: %FullPasswordFilePath%"
    del /F /Q "%FullPasswordFilePath%"
)

cscript //nologo "%PasswordRetrievalScriptPath%" "%PasswordManagerServer%" "%FTPUserName%" "%FullPasswordFilePath%"
if errorlevel 1 (
    echo "ERROR: Password retrieval script failed. Check VBS script execution and parameters."
    call :LogMsg "ERROR: Password retrieval script '%PasswordRetrievalScriptPath%' failed with errorlevel %ERRORLEVEL%."
    goto ErrorExit
)

rem Check if password file was created
if not exist "%FullPasswordFilePath%" (
    echo ERROR: Password file '%FullPasswordFilePath%' was not created by the VBS script.
    call :LogMsg "ERROR: Password file '%FullPasswordFilePath%' was not created by VBS script."
    goto ErrorExit
)

rem Read password from file (reads the first line)
set /p FTPPassword=<"%FullPasswordFilePath%"
if "!FTPPassword!"=="" (
    echo ERROR: Password file '%FullPasswordFilePath%' is empty.
    call :LogMsg "ERROR: Password file '%FullPasswordFilePath%' is empty."
    goto CleanupPasswordFileAndError
)
call :LogMsg "INFO: Password retrieved successfully."
echo INFO: Password retrieved successfully.

rem --- Generate PSFTP Batch Script ---
echo "INFO: Generating PSFTP command script: %FullFTPBatchScriptPath%"
call :LogMsg "INFO: Generating PSFTP command script: %FullFTPBatchScriptPath%"

(
    echo lcd "%TargetPathParam%"
    echo cd "%SourcePathParam%"
    echo mget "%FileNameParam%"
    echo rm "%FileNameParam%"
    echo quit
) > "%FullFTPBatchScriptPath%"

if errorlevel 1 (
    echo "ERROR: Failed to create PSFTP command script: %FullFTPBatchScriptPath%. Check permissions or disk space."
    call :LogMsg "ERROR: Failed to write PSFTP command script '%FullFTPBatchScriptPath%'. Errorlevel %ERRORLEVEL%."
    goto CleanupPasswordFileAndError
)
call :LogMsg "INFO: PSFTP command script generated successfully."
echo INFO: PSFTP command script generated.

rem --- Execute PSFTP ---
echo INFO: Connecting to SFTP server '%SourceServer%' as user '%FTPUserName%'...
call :LogMsg "INFO: Executing PSFTP command."
psftp.exe %FTPUserName%@%SourceServer% -pw "!FTPPassword!" -b "%FullFTPBatchScriptPath%" -batch

set SFTPExitCode=%ERRORLEVEL%

rem --- Check PSFTP Execution Result ---
if %SFTPExitCode% equ 0 (
    echo INFO: PSFTP execution completed successfully. File '%FileNameParam%' downloaded and deleted from server.
    call :LogMsg "INFO: PSFTP execution successful (Exit Code 0). File '%FileNameParam%' downloaded to '%TargetPathParam%' and deleted from '%SourcePathParam%' on '%SourceServer%'."
    set FinalExitCode=0
) else (
    echo ERROR: PSFTP execution failed with Exit Code %SFTPExitCode%. Check PSFTP logs or output if available.
    call :LogMsg "ERROR: PSFTP execution failed with Exit Code %SFTPExitCode%. File download/delete may have failed."
    set FinalExitCode=%SFTPExitCode%
    rem Even on failure, attempt cleanup.
)

rem --- Cleanup ---
:Cleanup
call :LogMsg "INFO: Starting cleanup..."
echo INFO: Cleaning up temporary files...

if exist "%FullPasswordFilePath%" (
    del /F /Q "%FullPasswordFilePath%"
    if errorlevel 1 (
        echo "WARN: Failed to delete temporary password file: %FullPasswordFilePath%"
        call :LogMsg "WARN: Failed to delete temporary password file: %FullPasswordFilePath%" NOEXIT
    ) else (
        call :LogMsg "INFO: Deleted temporary password file: %FullPasswordFilePath%"
        echo INFO: Deleted temporary password file.
    )
) else (
    call :LogMsg "INFO: Temporary password file not found for cleanup (already deleted or never created): %FullPasswordFilePath%"
)

if exist "%FullFTPBatchScriptPath%" (
    del /F /Q "%FullFTPBatchScriptPath%"
    if errorlevel 1 (
        echo "WARN: Failed to delete temporary FTP batch script: %FullFTPBatchScriptPath%"
        call :LogMsg "WARN: Failed to delete temporary FTP batch script: %FullFTPBatchScriptPath%" NOEXIT
    ) else (
        call :LogMsg "INFO: Deleted temporary FTP batch script: %FullFTPBatchScriptPath%"
        echo INFO: Deleted temporary FTP batch script.
    )
) else (
    call :LogMsg "INFO: Temporary FTP batch script not found for cleanup (already deleted or never created): %FullFTPBatchScriptPath%"
)

call :LogMsg "INFO: Cleanup finished."
call :LogMsg "INFO: Script execution finished with Exit Code %FinalExitCode%."
echo INFO: Script execution finished.

endlocal
exit /b %FinalExitCode%

rem --- Error Handling Subroutines ---
:CleanupPasswordFileAndError
call :LogMsg "INFO: An error occurred, attempting to clean up password file before exiting." NOEXIT
if exist "%FullPasswordFilePath%" (
    del /F /Q "%FullPasswordFilePath%"
    if not errorlevel 1 call :LogMsg "INFO: Deleted temporary password file: %FullPasswordFilePath%" NOEXIT
)
goto ErrorExit

:ErrorExit
call :LogMsg "INFO: Script exiting due to error." NOEXIT
echo "ERROR: Script terminated due to an error. Check log file: %LogFile%"
endlocal
exit /b 1

rem --- Logging Subroutine ---
:LogMsg
rem Usage: call :LogMsg "Log message" [NOEXIT]
rem If NOEXIT is provided as the second argument, it won't attempt to exit if logging fails.
set "LogMessage=%~1"
set "NoExitOnError=%~2"
set LogWriteError=0 REM Initialize error check variable

rem Get timestamp using WMI (more robust than %DATE% %TIME%)
rem Note: WMI format is independent of locale. Fallback %DATE% %TIME% IS locale dependent.
for /f "tokens=2 delims==" %%A in ('wmic os get LocalDateTime /value 2^>nul') do set DateTime=%%A
if not defined DateTime (
    rem Fallback to less reliable date/time if WMI fails
    set "Timestamp=%DATE% %TIME:~0,8%"
    rem Attempt to write warning to log without exiting on failure
    echo [%Timestamp%] WARN: Could not get timestamp via WMI. Falling back to DATE/TIME. >> "%LogFile%" 2>nul
) else (
    set "Timestamp=%DateTime:~0,4%-%DateTime:~4,2%-%DateTime:~6,2% %DateTime:~8,2%:%DateTime:~10,2%:%DateTime:~12,2%"
)

rem Write message to log file and CAPTURE its specific errorlevel
echo [%Timestamp%] %LogMessage% >> "%LogFile%" 2>nul
set LogWriteError=%ERRORLEVEL%

rem Check the CAPTURED errorlevel from the echo command
if %LogWriteError% neq 0 (
    echo "ERROR: Failed to write to log file: %LogFile%"
    if /I not "%NoExitOnError%"=="NOEXIT" (
        echo Script will terminate.
        exit /b 2
    )
)
goto :eof