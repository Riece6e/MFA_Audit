# Prompt for credentials if needed
if (-not $MyCredential) {
    $MyCredential = Get-Credential -Message "Enter credentials for AD02"
}

Write-Host "Connecting to AD02..." -ForegroundColor Cyan

# Get enabled users from AD02 and store in $EnableUser
$EnableUser = Invoke-Command -ComputerName "AD02" -Credential $MyCredential -ScriptBlock {
    Write-Host "Connected to AD02" -ForegroundColor Green
    
    # Import Active Directory module
    Import-Module ActiveDirectory
    
    # Get all enabled users from AD with email addresses
    Get-ADUser -Filter 'Enabled -eq $true' -Properties mail | 
    Where-Object { -not [string]::IsNullOrEmpty($_.mail) } |
    Select-Object -Property Name, UserPrincipalName, mail |
    Sort-Object Name
}

# Now $EnableUser holds the list of enabled users with email addresses
# Optional: Display the results
 $EnableUser | Format-Table -AutoSize

Write-Host "Print enabled users" -ForegroundColor Green

# Import-Module Microsoft.Graph.Authentication
# Import-Module ExchangeOnlineManagement

# Connect to Microsoft Graph with the required scopes
 #Connect-MgGraph -NoWelcome
 #Connect-ExchangeOnline

# Start the stopwatch
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Retrieve all users with their Id, DisplayName, and Mail
$users = Get-MgUser -Consistencylevel eventual -Search '"DisplayName:r"' | Where-Object {$_.Mail -like '*inland*' }  | Select-Object Id, DisplayName, Mail
# $users = Get-MgUser -All | Where-Object { $_.Mail -like '*inland*' } | Select-Object Id, DisplayName, Mail
#-and (Get-MailboxStatistics -Identity $_.Mail -ErrorAction SilentlyContinue)

$getUserTime = $stopwatch.Elapsed.TotalSeconds
if ($getUserTime -gt 60) {
    $minutesToGetUsers = [Math]::Floor($getUserTime / 60)
    $secondsToGetUsers = [Math]::Round($getUserTime % 60)
    $timeToGetUsers = "$minutesToGetUsers min(s) and $secondsToGetUsers sec(s)"
} else {
    $timeToGetUsers = "$([Math]::Round($getUserTime)) sec(s)"
}
Write-Host "It took $timeToGetUsers to get the users"

# Initialize an array to store the results
$result = @()

$ProgressPreference = 'Continue'

# Initialize progress variables
$totalUsers = $users.Count
$processed = 0

# Start the stopwatch for user time estimating
$userStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Loop through each user
foreach ($user in $users) {
    try{
    # Get the authentication methods for the current user
    $methods = Get-MgUserAuthenticationMethod -UserId $user.Id
    
    if (Get-MailboxStatistics -Identity $user.Mail -ErrorAction SilentlyContinue) {
        # Get the mailbox type for the current user
        $mailboxType = Get-MailboxStatistics -Identity $user.Mail | Select-Object -ExpandProperty MailboxTypeDetail
        #$user.DisplayName

        # Check if the user does not have SoftwareOathAuthenticationMethod
        if ( -not ($methods | Where-Object { 
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod' -or 
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' }) -and 
            $user.DisplayName -contains $EnableUser.Name) {
            $lastLogon = Get-MailboxStatistics -Identity $user.Mail | Select-Object -ExpandProperty LastLogonTime
            $result += [PSCustomObject]@{
                DisplayName = $user.DisplayName
                Mail        = $user.Mail
                MailboxType = $mailboxType
                LastLogonTime = $lastLogon
            }
            #Write-Host $user
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

    #Calculate the estimated time remaining
    if ($processed -gt 0) {
        $timePerUser = $userTime / $processed
        $remainingUsers = $totalUsers - $processed
        $remainingSeconds = $timePerUser * $remainingUsers
        if ($processed -lt 10) {
            $timeRemaining = "Calculating Time Remaining..."
        }
        elseif ($remainingSeconds -gt 60) {
            $remainingMinutes = [Math]::Floor($remainingSeconds / 60)
            $remainingSeconds = [Math]::Round($remainingSeconds % 60)
            $timeRemaining = "Remaining: $remainingMinutes min(s) $remainingSeconds sec(s)"
        } else {
            $timeRemaining = "Remaining: $([Math]::Round($remainingSeconds)) sec(s)"
        }
        $status = "Processed $processed of $totalUsers ($percentComplete%) - Elapsed: $([Math]::Round($elapsedTime.ToString('F2'))) sec(s) - $timeRemaining"
    } else {
        $status = "Starting..."
    }

    Write-Progress -Activity "Processing Users" -Status $status -PercentComplete $percentComplete 
    #-SecondsRemaining $remainingSeconds
}

# Stop the stopwatch
$stopwatch.Stop()
$userStopwatch.Stop()

# Complete progress
Write-Progress -Activity "Processing Users" -Completed

# Output the results to the console
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

# Export the results to a CSV file
$result | Export-Csv -Path "users_without_software_mfa.csv" -NoTypeInformation