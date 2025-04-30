# Import required modules
# Import-Module Microsoft.Graph.Users
# Import-Module Microsoft.Graph.Authentication

# Connect to Microsoft Graph (uncomment for interactive login)
 Connect-MgGraph

# Define output file path
# $outputPath = "C:\Users\charlesh\OneDrive - Inland Seafood\Desktop\Scipts\Powershell\users_without_mfa.csv"

# Get all active users with necessary properties
# $users = Get-MgUser -All | Select-Object Id, UserPrincipalName, DisplayName, AuthenticationMethods, Mail
 $users = Get-MgUser -Consistencylevel eventual -Search '"DisplayName:c"' | Select-Object Id, DisplayName, Mail
# $users = Get-MgUser -All | Where-Object { $_.Mail -and $_.Mail -like '*inland*' } | Select-Object DisplayName, UserPrincipalName, Id, Mail, AccountEnabled, AuthenticationMethods

# Filter out users whose email does not contain 'inland'
#    $users = $users | Where-Object { $_.Mail -like '*inland*' }

# Initialize progress variables
$totalUsers = $users.Count
$processedUsers = 0

# Array to store users with MFA disabled
$mfaDisabledUsers = @()

# Define MFA method types to check
$mfaMethodTypes = @(
    "#microsoft.graph.phoneAuthenticationMethod",
    "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod",
    "#microsoft.graph.softwareOathAuthenticationMethod",
    "#microsoft.graph.fido2AuthenticationMethod",
    "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod",
    "#microsoft.graph.temporaryAccessPassAuthenticationMethod", 
    "microsoft.graph.emailAuthenticationMethod",
    "#microsoft.graph.securityKeyAuthenticationMethod"
    
)

# Process each user
foreach ($user in $users) {
    # Get authentication methods
    $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id
    $mfaStatus = $false

    # Check if any MFA methods are registered
    foreach ($method in $authMethods) {
        if ($mfaMethodTypes -contains $method.AdditionalProperties['@odata.type']) {
            $mfaStatus = $true
            break
        }
    }

    # If no MFA methods are found, add user to the list
    if (-not $mfaStatus) {
        $mfaDisabledUsers += [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName       = $user.DisplayName
            AccountEnabled    = $user.AccountEnabled
            Mail             = $user.Mail
            MFAStatus        = $user.AuthenticationMethods
            MFAEnabled       = $mfaStatus
        
            
        }
    }

    # Update progress
    $processedUsers++
    $percentComplete = [math]::Round(($processedUsers / $totalUsers) * 100)
    Write-Progress -Activity "Checking MFA Status" `
                   -Status "Processing user $processedUsers of $totalUsers" `
                   -PercentComplete $percentComplete `
                   -CurrentOperation "User: $($user.UserPrincipalName)"
}

# Close the progress bar
Write-Progress -Activity "Checking MFA Status" -Completed

# Export results to CSV
$mfaDisabledUsers | Export-Csv -Path "outputPath.csv" -NoTypeInformation -Force

# Display results in a filterable table
$mfaDisabledUsers | Out-GridView -Title "Users with MFA Disabled"

# Display summary
if ($mfaDisabledUsers.Count -eq 0) {
    Write-Host "No users with MFA disabled were found."
} else {
    Write-Host "Found $($mfaDisabledUsers.Count) users with MFA disabled. Report saved to: $outputPath"
}