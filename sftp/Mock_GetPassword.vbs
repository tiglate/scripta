' --- Script Information ---
' Name:        Mock_GetPassword.vbs
' Description: TEST SCRIPT - Simulates retrieving a password.
'              Accepts Server, Username, and Output File Path as arguments.
'              Writes a hardcoded password ("TestPassword123") to the Output File.
' Author:      HAL 9000
' Date:        2025-04-10
' Version:     1.0 (for testing only)
' Usage:       cscript //nologo Mock_GetPassword.vbs [PasswordManagerServer] [FTPUserName] [PasswordFile]
' Example:     cscript //nologo Mock_GetPassword.vbs pwdmgr.test.local testuser C:\temp\pwd.txt
' ---

Option Explicit ' Enforce variable declaration

Dim objArgs, pwdMgrServer, ftpUser, pwdFilePath
Dim fso, ts, testPassword
Const ForWriting = 2
Const CreateIfNeeded = True

' --- Argument Handling ---
Set objArgs = WScript.Arguments

If objArgs.Count <> 3 Then
    WScript.Echo "ERROR: Incorrect number of arguments."
    WScript.Echo "Usage: cscript //nologo " & WScript.ScriptName & " [PasswordManagerServer] [FTPUserName] [PasswordFile]"
    WScript.Quit(1) ' Exit with error code
End If

pwdMgrServer = objArgs(0)
ftpUser = objArgs(1)
pwdFilePath = objArgs(2)

' --- Display Received Parameters ---
WScript.Echo "--- Mock Password Retrieval Script Started ---"
WScript.Echo "Received Parameters:"
WScript.Echo "  Password Manager Server: " & pwdMgrServer
WScript.Echo "  FTP User Name:           " & ftpUser
WScript.Echo "  Password File Path:      " & pwdFilePath
WScript.Echo "-------------------------------------------"

' --- Define Test Password ---
testPassword = "password" ' Hardcoded password for testing
WScript.Echo "INFO: Using hardcoded test password: " & testPassword

' --- Write Password to File ---
WScript.Echo "INFO: Attempting to write password to file: " & pwdFilePath

On Error Resume Next ' Enable error handling

Set fso = CreateObject("Scripting.FileSystemObject")
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not create FileSystemObject. VBScripting runtime issue?"
    WScript.Echo "Error [" & Err.Number & "]: " & Err.Description
    WScript.Quit(2) ' Exit with specific error code
End If

Set ts = fso.OpenTextFile(pwdFilePath, ForWriting, CreateIfNeeded)
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not open or create password file: " & pwdFilePath
    WScript.Echo "Check path validity and permissions."
    WScript.Echo "Error [" & Err.Number & "]: " & Err.Description
    Set fso = Nothing ' Clean up object
    WScript.Quit(3) ' Exit with specific error code
End If

ts.WriteLine testPassword
If Err.Number <> 0 Then
    WScript.Echo "ERROR: Could not write password to file: " & pwdFilePath
    WScript.Echo "Check disk space and permissions."
    WScript.Echo "Error [" & Err.Number & "]: " & Err.Description
    ts.Close ' Attempt to close file even on error
    Set ts = Nothing
    Set fso = Nothing
    WScript.Quit(4) ' Exit with specific error code
End If

ts.Close
If Err.Number <> 0 Then
    ' Non-critical error, but worth noting
    WScript.Echo "WARNING: Error occurred while closing the password file."
    WScript.Echo "Error [" & Err.Number & "]: " & Err.Description
End If

On Error GoTo 0 ' Disable error handling

Set ts = Nothing
Set fso = Nothing

WScript.Echo "INFO: Successfully wrote test password to: " & pwdFilePath
WScript.Echo "--- Mock Password Retrieval Script Finished ---"

WScript.Quit(0) ' Exit successfully