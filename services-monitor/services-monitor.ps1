<#
.SYNOPSIS
    Monitors specified Windows NT Services and sends an HTML email report.

.DESCRIPTION
    This script loads a list of Windows NT services from a CSV file ("services.csv") located in the same folder,
    checks whether each service is running, builds an HTML report (with inline CSS optimized for Outlook/IE11),
    and sends the report via email using settings from a "settings.ini" file.
    
    Sample settings.ini (place in the same folder as the script):
    ------------------------------------------------------------
    [Email]
    SMTPServer=smtp.example.com
    SMTPPort=587
    EmailFrom=sender@example.com
    EmailTo=recipient@example.com
    EmailSubject=Windows NT Services Status Report
    SMTPUsername=yourUsername
    SMTPPassword=yourPassword
    UseSSL=True
    ------------------------------------------------------------

.NOTES
    Ensure the CSV file ("services.csv") contains two columns:
      - Service Name (technical name used by Get-Service)
      - Display Name (friendly name for the email report)
    This script uses only built-in cmdlets so it can run in restricted environments.
#>

# Logs messages with a timestamp
function Write-Log {
    param([string]$Message)
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

# Parses an INI file into a nested hashtable (supports sections)
function Parse-IniFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "INI file not found: $Path"
    }
    $ini = @{}
    $section = ""
    foreach ($line in Get-Content $Path) {
        $line = $line.Trim()
        if ($line -match '^\s*;') { continue }  # Skip comment lines
        if ($line -match '^\[(.+)\]$') {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        elseif ($line -match '^(.*?)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($section -eq "") {
                $ini[$key] = $value
            }
            else {
                $ini[$section][$key] = $value
            }
        }
    }
    return $ini
}

# Reads email configuration from settings.ini
function Read-Settings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    Write-Log "Reading settings from $FilePath"
    return Parse-IniFile -Path $FilePath
}

# Loads the list of services from CSV and checks their current status
function Get-ServicesStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath
    )
    if (-not (Test-Path $CsvPath)) {
        throw "CSV file not found: $CsvPath"
    }
    Write-Log "Loading service list from $CsvPath"
    $servicesList = Import-Csv -Path $CsvPath
    $servicesStatus = @()
    foreach ($service in $servicesList) {
        try {
            $svc = Get-Service -Name $service.'Service Name' -ErrorAction Stop
            $status = if ($svc.Status -eq 'Running') { 'Started' } else { 'Stopped' }
        }
        catch {
            $status = "Not Found"
        }
        $servicesStatus += [PSCustomObject]@{
            DisplayName = $service.'Display Name'
            Status      = $status
        }
    }
    return $servicesStatus
}

# Builds the HTML email body with inline CSS optimized for Outlook/IE11
function Build-EmailBody {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Services,
        [Parameter(Mandatory = $true)]
        [datetime]$ReportTime
    )
    $html = @"
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>Windows NT Services Status Report</title>
  </head>
  <body style="font-family: Arial, sans-serif; margin: 0; padding: 20px;">
    <h2 style="text-align: center; color: #333;">Windows NT Services Status Report</h2>
    <p style="text-align: center; color: #555;">Report generated on: $($ReportTime.ToString("yyyy-MM-dd HH:mm:ss"))</p>
    <table style="width: 100%; border-collapse: collapse;">
      <thead>
        <tr style="background-color: #001aff; color: white;">
          <th style="border: 1px solid #ddd; padding: 8px;">Service</th>
          <th style="border: 1px solid #ddd; padding: 8px;">Status</th>
        </tr>
      </thead>
      <tbody>
"@
    foreach ($svc in $Services) {
        $html += "        <tr style='background-color: #f9f9f9;'>" + "`n"
        $html += "          <td style='border: 1px solid #ddd; padding: 8px;'>$($svc.DisplayName)</td>" + "`n"
        $html += "          <td style='border: 1px solid #ddd; padding: 8px;'>$($svc.Status)</td>" + "`n"
        $html += "        </tr>" + "`n"
    }
    $html += @"
      </tbody>
    </table>
  </body>
</html>
"@
    return $html
}

# Sends an HTML email using configuration from the settings file
function Send-Email {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Body,
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )
    # Retrieve email settings from the [Email] section of settings.ini
    $emailSettings = $Settings["Email"]
    if (-not $emailSettings) {
        throw "Email settings not found in settings.ini under [Email] section."
    }
    
    $smtpServer = $emailSettings.SMTPServer
    $smtpPort   = [int]$emailSettings.SMTPPort
    $emailFrom  = $emailSettings.EmailFrom
    $emailTo    = $emailSettings.EmailTo
    $subject    = $emailSettings.EmailSubject
    $useSSL     = ($emailSettings.UseSSL -eq "True")
    
    Write-Log "Preparing to send email to $emailTo using SMTP server $smtpServer on port $smtpPort"
    
    # Build parameters for Send-MailMessage
    $mailParams = @{
        SmtpServer = $smtpServer
        Port       = $smtpPort
        From       = $emailFrom
        To         = $emailTo
        Subject    = $subject
        Body       = $Body
        BodyAsHtml = $true
        UseSsl     = $useSSL
    }
    
    # Optional: Add authentication if SMTPUsername and SMTPPassword are provided
    if ($emailSettings.SMTPUsername -and $emailSettings.SMTPPassword) {
        $securePassword = ConvertTo-SecureString $emailSettings.SMTPPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($emailSettings.SMTPUsername, $securePassword)
        $mailParams.Credential = $credential
    }
    
    try {
        Send-MailMessage @mailParams
        Write-Log "Email sent successfully."
    }
    catch {
        Write-Log "Failed to send email: $_"
    }
}

# Main function orchestrating the workflow
function Main {
    try {
        Write-Log "Script execution started."
        
        # Load email configuration
        $settingsPath = Join-Path -Path $PSScriptRoot -ChildPath "settings.ini"
        $settings = Read-Settings -FilePath $settingsPath
        
        # Load and check service statuses from CSV
        $csvPath = Join-Path -Path $PSScriptRoot -ChildPath "services.csv"
        $servicesStatus = Get-ServicesStatus -CsvPath $csvPath
        
        # Build the HTML email body
        $reportTime = Get-Date
        $emailBody = Build-EmailBody -Services $servicesStatus -ReportTime $reportTime
        
        # Output the service status to the console for manual execution
        Write-Log "Service Status Report:"
        foreach ($svc in $servicesStatus) {
            Write-Host "$($svc.DisplayName): $($svc.Status)"
        }
        
        # Send the email report
        Send-Email -Body $emailBody -Settings $settings
        
        Write-Log "Script execution completed successfully."
    }
    catch {
        Write-Log "An error occurred: $_"
    }
}

# Execute the main function
Main
