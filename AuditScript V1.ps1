# Connect to Microsoft Graph
#Connect-MgGraph

# Get all users
$users = Get-MgUser -All

# Filter for users with MFA disabled
$mfaDisabledUsers = @()

foreach ($user in $users) {
    $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id

    # Check if StrongAuthenticationRequirements is null or if its State is 'Disabled'
    if (($user.StrongAuthenticationRequirements -eq $null -or $user.StrongAuthenticationRequirements.State -eq "Disabled") -or ($authMethods | Where-Object {$_.AuthenticationMethodType -eq "Password"})) {
        $mfaDisabledUsers += $user.UserPrincipalName
    }
}

# Display the results
Write-Host "Users with MFA Disabled:" -ForegroundColor Yellow
$mfaDisabledUsers | ForEach-Object {
    Write-Host $_
}

# Export to CSV
#$mfaDisabledUsers | ForEach-Object {
#    $result = New-Object PSObject -Property @{
#        DisplayName = $_
#        MFAStatus = "Disabled"
#    }
#    $result
#} | Export-Csv -Path "C:\MFA_Disabled_Users.csv" -NoTypeInformation