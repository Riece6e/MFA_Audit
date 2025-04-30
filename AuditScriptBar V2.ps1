# Connect to Microsoft Graph with the required scopes
Connect-MgGraph -NoWelcome
#Connect-ExchangeOnline

# Retrieve all users with their Id, DisplayName, and Mail
#$users = Get-MgUser -Consistencylevel eventual -Search '"DisplayName:r"' | Where-Object {$_.Mail -like '*inland*' }  | Select-Object Id, DisplayName, Mail
$users = Get-MgUser -Top 700 | Where-Object {$_.Mail -like '*inland*' } | Select-Object Id, DisplayName, Mail

# Initialize an array to store the results
$result = @()

$ProgressPreference = 'Continue'

# Start the stopwatch
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Initialize progress variables
$totalUsers = $users.Count
$processed = 0

# Loop through each user
foreach ($user in $users) {
    # Get the authentication methods for the current user
    $methods = Get-MgUserAuthenticationMethod -UserId $user.Id
    
    if (Get-MailboxStatistics -Identity $user.Mail -ErrorAction SilentlyContinue) {
        $mailboxType = Get-MailboxStatistics -Identity $user.Mail | Select-Object -ExpandProperty MailboxTypeDetail
        #$user.DisplayName

        # Check if the user does not have SoftwareOathAuthenticationMethod
        if ((-not ($methods | Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod' -or $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' })) -and $mailboxType.Value -eq "UserMailbox") {
            $lastLogon = Get-MailboxStatistics -Identity $user.Mail | Select-Object -ExpandProperty LastLogonTime
            $result += [PSCustomObject]@{
                DisplayName = $user.DisplayName
                Mail        = $user.Mail
                MailboxType = $mailboxType
                LastMailboxLogonTime = $lastLogon
            }
            #Write-Host $user
        }
    }

    # Update progress
    $processed++
    $percentComplete = [Math]::Round((($processed / $totalUsers) * 100), 1)
    $elapsedTime = $stopwatch.Elapsed.TotalSeconds

    #Calculate the estimated time remaining
    if ($processed -gt 0) {
        $timePerUser = $elapsedTime / $processed
        $remainingUsers = $totalUsers - $processed
        $remainingSeconds = $timePerUser * $remainingUsers
        if ($remainingSeconds -gt 60) {
            $remainingMinutes = [Math]::Floor($remainingSeconds / 60)
            $remainingSeconds = [Math]::Round($remainingSeconds % 60)
            $timeRemaining = "$remainingMinutes min(s) $remainingSeconds sec(s)"
        } else {
            $timeRemaining = "$remainingSeconds sec(s)"
        }
        $status = "Processed $processed of $totalUsers ($percentComplete%) - Elapsed: $([Math]::Round($elapsedTime.ToString('F2'))) sec(s) - Remaining: $timeRemaining"
    } else {
        $status = "Starting..."
    }

    Write-Progress -Activity "Processing Users" -Status $status -PercentComplete $percentComplete 
    #-SecondsRemaining $remainingSeconds
}

# Stop the stopwatch
$stopwatch.Stop()

# Complete progress
Write-Progress -Activity "Processing Users" -Completed

# Output the results to the console
$result | Format-Table
Write-Host "Total Users Processed: $($result.Count)"
Write-Host "Elapsed Time: $($stopwatch.Elapsed.TotalSeconds.ToString('F2')) seconds"

# Export the results to a CSV file
$result | Export-Csv -Path "users_without_software_mfa.csv" -NoTypeInformation