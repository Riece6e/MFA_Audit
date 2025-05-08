# Prompt for credentials if needed
if (-not $MyCredential) {
    $MyCredential = Get-Credential -Message "Enter credentials for AD02"
}

Write-Host "Connecting to AD02..." -ForegroundColor Cyan

# Get enabled users from AD02 and store in $EnableUser
$EnableUser = Invoke-Command -ComputerName "AD02" -Credential $MyCredential -ScriptBlock {
    Write-Host "Connected to AD02" -ForegroundColor Green
    Import-Module ActiveDirectory
    Get-ADUser -Filter 'Enabled -eq $true' -Properties mail | 
    Where-Object { -not [string]::IsNullOrEmpty($_.mail) } |
    Select-Object -Property Name, UserPrincipalName, mail |
    Sort-Object Name
}

Write-Host "Print enabled users" -ForegroundColor Green
$EnableUser | Format-Table -AutoSize

# Import required modules and connect
Import-Module Microsoft.Graph.Authentication
Import-Module ExchangeOnlineManagement
Connect-MgGraph -Scopes "User.Read.All", "UserAuthenticationMethod.Read.All" -NoWelcome
Connect-ExchangeOnline

# Start the stopwatch
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Retrieve users from Microsoft Graph
$users = Get-MgUser -All | Where-Object { $_.Mail -like '*inland*' } | Select-Object Id, DisplayName, Mail

$getUserTime = $stopwatch.Elapsed.TotalSeconds
if ($getUserTime -gt 60) {
    $minutesToGetUsers = [Math]::Floor($getUserTime / 60)
    $secondsToGetUsers = [Math]::Round($getUserTime % 60)
    $timeToGetUsers = "$minutesToGetUsers min(s) and $secondsToGetUsers sec(s)"
} else {
    $timeToGetUsers = "$([Math]::Round($getUserTime)) sec(s)"
}
Write-Host "It took $timeToGetUsers to get the users"

# Initialize variables
$result = @()
$ProgressPreference = 'Continue'
$totalUsers = $users.Count
$processed = 0
$userStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Process each user
foreach ($user in $users) {
    try {
        # Get authentication methods
        $methods = Get-MgUserAuthenticationMethod -UserId $user.Id
        
        # Check mailbox and get details
        $mailboxStats = Get-MailboxStatistics -Identity $user.Mail -ErrorAction Stop
        if ($mailboxStats) {
            $mailboxType = $mailboxStats.MailboxTypeDetail
            # Check authentication methods and AD match
            if (-not ($methods | Where-Object { 
                $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod' -or 
                $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' 
            }) -and $EnableUser.Name -contains $user.DisplayName) {
                $lastLogon = $mailboxStats.LastLogonTime
                $result += [PSCustomObject]@{
                    DisplayName   = $user.DisplayName
                    Mail          = $user.Mail
                    MailboxType   = $mailboxType
                    LastLogonTime = $lastLogon
                }
            }
        }
    } catch {
        Write-Warning "Error processing $($user.Mail): $_"
    }

    # Update progress
    $processed++
    $percentComplete = [Math]::Round((($processed / $totalUsers) * 100), 1)
    $elapsedTime = $stopwatch.Elapsed.TotalSeconds
    $userTime = $userStopwatch.Elapsed.TotalSeconds

    if ($processed -gt 0) {
        $timePerUser = $userTime / $processed
        $remainingUsers = $totalUsers - $processed
        $remainingSeconds = $timePerUser * $remainingUsers
        if ($remainingSeconds -gt 60) {
            $remainingMinutes = [Math]::Floor($remainingSeconds / 60)
            $remainingSeconds = [Math]::Round($remainingSeconds % 60)
            $timeRemaining = "Remaining: $remainingMinutes min(s) $remainingSeconds sec(s)"
        } else {
            $timeRemaining = "Remaining: $([Math]::Round($remainingSeconds)) sec(s)"
        }
        $status = "Processed $processed of $totalUsers ($percentComplete%) - Elapsed: $([Math]::Round($elapsedTime, 1)) sec(s) - $timeRemaining"
    } else {
        $status = "Starting..."
    }
    Write-Progress -Activity "Processing Users" -Status $status -PercentComplete $percentComplete
}

# Stop stopwatches and complete progress
$stopwatch.Stop()
$userStopwatch.Stop()
Write-Progress -Activity "Processing Users" -Completed

# Output results
$result | Format-Table
Write-Host "Total Users Processed: $($result.Count)"
$totalStopwatch = $stopwatch.Elapsed.TotalSeconds
if ($totalStopwatch -gt 60) {
    $minutes = [Math]::Floor($totalStopwatch / 60)
    $seconds = [Math]::Round($totalStopwatch % 60)
    $totalTime = "$minutes min(s) and $seconds sec(s)"
} else {
    $totalTime = "$([Math]::Round($totalStopwatch)) sec(s)"
}
Write-Host "Total Elapsed Time: $totalTime"

# Export to CSV
$result | Export-Csv -Path "users_without_software_mfa.csv" -NoTypeInformation