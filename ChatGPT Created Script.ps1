# 1) Prompt for credentials if not already provided
if (-not $MyCredential) {
    $MyCredential = Get-Credential -Message "Enter credentials for AD02"
}

# 2) Grab your enabled‐user list **into** your local session
Write-Host "Retrieving enabled users from AD02…" -ForegroundColor Cyan
$EnableUser = Invoke-Command -ComputerName "AD02" -Credential $MyCredential -ScriptBlock {
        Import-Module ActiveDirectory
        Get-ADUser -Filter 'Enabled -eq $true' -Properties mail |
          Where-Object { $_.mail } |
          Select-Object Name, UserPrincipalName, mail
    }

Write-Host "Fetched $($EnableUser.Count) enabled users with mail addresses." -ForegroundColor Green

Import-Module Microsoft.Graph.Authentication
Import-Module ExchangeOnlineManagement

# 3) Connect to Graph **and** to Exchange Online (so Get-MailboxStatistics works)
 Connect-MgGraph -NoWelcome
 Connect-ExchangeOnline

# 4) Pull down your Graph users
Write-Host "Retrieving Microsoft 365 users…" -ForegroundColor Cyan
$users = Get-MgUser -All |
         Where-Object { $_.Mail -like '*inland*' } |
         Select-Object Id, DisplayName, Mail

Write-Host "Fetched $($users.Count) users from Microsoft 365.`n" -ForegroundColor Green

# 5) Loop and build your result set
$result = foreach ($user in $users) {
    # Check MFA methods
    $methods = Get-MgUserAuthenticationMethod -UserId $user.Id

    # Only proceed for users who:
    #  A) Have an Exchange mailbox
    #  B) ARE in your AD‐02 enabled list
    #  C) Do NOT have either the SoftwareOath or MS Authenticator method
    if (
        (Get-MailboxStatistics -Identity $user.Mail -ErrorAction SilentlyContinue) -and
        ($EnableUser.Name -contains $user.DisplayName) -and
        -not ($methods |
              Where-Object {
                  $_.AdditionalProperties['@odata.type'] -in (
                      '#microsoft.graph.softwareOathAuthenticationMethod',
                      '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
                  )
              })
    ) {
        # Pull mailbox stats only once
        $mbStats = Get-MailboxStatistics -Identity $user.Mail

        [PSCustomObject]@{
            DisplayName   = $user.DisplayName
            Mail          = $user.Mail
            MailboxType   = $mbStats.MailboxTypeDetail
            LastLogonTime = $mbStats.LastLogonTime
        }
    }
}

# 6) Show and export
if ($result) {
    $result | Format-Table -AutoSize
    $result | Export-Csv "users_without_software_mfa.csv" -NoTypeInformation
    Write-Host "Found $($result.Count) users; exported to users_without_software_mfa.csv" -ForegroundColor Yellow
} else {
    Write-Host "No matching users found."}
