# Script to identify users who are enabled in AD but don't have MFA configured
# Initialize stopwatch for performance measurement
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Set progress preference
$ProgressPreference = 'Continue'

Write-Host "Starting script to identify AD users without MFA..." -ForegroundColor Cyan

# Step 1: Prompt for credentials if needed
if (-not $MyCredential) {
    $MyCredential = Get-Credential -Message "Enter credentials for AD02"
}

# Step 2: Connect to AD02 and get enabled users
Write-Host "Connecting to AD02..." -ForegroundColor Cyan

# Use a scriptblock with Invoke-Command instead of Enter-PSSession
$EnabledUsers = @()
$EnabledUsers = Invoke-Command -ComputerName "AD02" -Credential $MyCredential -ScriptBlock {
    # Import Active Directory module
    Import-Module ActiveDirectory
    
    Write-Host "Getting enabled users from Active Directory..." -ForegroundColor Cyan
    
    # Get all enabled users from AD with email addresses
    Get-ADUser -Filter 'Enabled -eq $true' -Properties mail | 
    Where-Object { -not [string]::IsNullOrEmpty($_.mail) } |
    Select-Object -Property Name, UserPrincipalName, mail |
    Sort-Object Name
}

# No need to exit session or save temporary file since we're using Invoke-Command
Write-Host "Retrieved users from AD02" -ForegroundColor Green

# Use the users returned directly from Invoke-Command
$adUsersCount = $EnabledUsers.Count
Write-Host "Found $adUsersCount enabled users with email addresses in Active Directory." -ForegroundColor Green

# Step 4: Connect to Microsoft Graph and Exchange Online
Write-Host "Connecting to Microsoft 365 services..." -ForegroundColor Cyan
try {
    Connect-MgGraph -NoWelcome -ErrorAction Stop
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Host "Successfully connected to Microsoft 365 services." -ForegroundColor Green
} catch {
    Write-Host "Error connecting to Microsoft 365 services: $_" -ForegroundColor Red
    exit 1
}

# Step 5: Process users to check MFA status
Write-Host "Checking MFA status for each user..." -ForegroundColor Cyan

# Initialize result collection
$result = @()

# Initialize progress variables
$processed = 0

foreach ($adUser in $EnabledUsers) {
    # Update progress
    $processed++
    $percentComplete = [Math]::Round((($processed / $adUsersCount) * 100), 1)
    
    # Calculate time estimates
    if ($processed -gt 10) {
        $elapsedTime = $stopwatch.Elapsed.TotalSeconds
        $timePerUser = $elapsedTime / $processed
        $remainingUsers = $adUsersCount - $processed
        $remainingSeconds = $timePerUser * $remainingUsers
        
        if ($remainingSeconds -gt 60) {
            $remainingMinutes = [Math]::Floor($remainingSeconds / 60)
            $remainingSeconds = [Math]::Round($remainingSeconds % 60)
            $timeRemaining = "Remaining: $remainingMinutes min(s) $remainingSeconds sec(s)"
        } else {
            $timeRemaining = "Remaining: $([Math]::Round($remainingSeconds)) sec(s)"
        }
    } else {
        $timeRemaining = "Calculating..."
    }
    
    $status = "Processing $processed of $adUsersCount ($percentComplete%) - $timeRemaining"
    Write-Progress -Activity "Checking MFA Status" -Status $status -PercentComplete $percentComplete
    
    try {
        # Try to get Microsoft Graph user by email
        $mgUser = Get-MgUser -Filter "mail eq '$($adUser.mail)'" -ErrorAction SilentlyContinue
        
        if ($mgUser) {
            # Check if mailbox exists
            $mailboxStats = Get-MailboxStatistics -Identity $adUser.mail -ErrorAction SilentlyContinue
            
            if ($mailboxStats) {
                # Get authentication methods for the user
                $methods = Get-MgUserAuthenticationMethod -UserId $mgUser.Id -ErrorAction SilentlyContinue
                
                # Check if user does not have MFA methods configured
                if (-not ($methods | Where-Object { 
                    $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod' -or 
                    $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' -or
                    $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.phoneAuthenticationMethod' 
                })) {
                    # Add user to results - they have no MFA configured
                    $result += [PSCustomObject]@{
                        DisplayName = $adUser.Name
                        Email = $adUser.mail
                        MailboxType = $mailboxStats.MailboxTypeDetail
                        LastLogonTime = $mailboxStats.LastLogonTime
                    }
                }
            }
        }
    } catch {
        Write-Host "Error processing user $($adUser.Name): $_" -ForegroundColor Yellow
        continue
    }
}

# Complete progress
Write-Progress -Activity "Checking MFA Status" -Completed

# Stop the stopwatch
$stopwatch.Stop()
$totalSeconds = $stopwatch.Elapsed.TotalSeconds

# Format time for display
if ($totalSeconds -gt 60) {
    $minutes = [Math]::Floor($totalSeconds / 60)
    $seconds = [Math]::Round($totalSeconds % 60)
    $totalTime = "$minutes min(s) and $seconds sec(s)"
} else {
    $totalTime = "$([Math]::Round($totalSeconds)) sec(s)"
}

# Display results and export to CSV
Write-Host "`nResults:" -ForegroundColor Cyan
$result | Format-Table

# Export the results to a CSV file
$result | Export-Csv -Path "users_without_mfa.csv" -NoTypeInformation

Write-Host "`nTotal Enabled Users Without MFA: $($result.Count)" -ForegroundColor Yellow
Write-Host "Total Elapsed Time: $totalTime" -ForegroundColor Green
Write-Host "Results exported to: users_without_mfa.csv" -ForegroundColor Green

# Disconnect from services
Write-Host "`nDisconnecting from services..." -ForegroundColor Cyan
Disconnect-MgGraph | Out-Null
Disconnect-ExchangeOnline -Confirm:$false | Out-Null

# No temporary file to clean up

Write-Host "Script completed successfully." -ForegroundColor Green