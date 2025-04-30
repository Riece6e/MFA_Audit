$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

#$user = Get-MailboxStatistics -Identity "riece@inlandseafood.com"
#Write-Host $user.MailboxTypeDetail

# Retrieve users whose Mail property contains '@inland'
$users = Get-MgUser -All | Where-Object {$_.Mail -like '*inland*'} | Select-Object DisplayName, Mail
$users
$users.Count
#Write-Host "Users Collected"

#-and (Get-MailboxStatistics -Identity $_.Mail -ErrorAction SilentlyContinue)

<#
$result = @()
foreach ($user in $users) {
    if (Get-MailboxStatistics -Identity $user.Mail -ErrorAction SilentlyContinue) {
        $result += [PSCustomObject]@{
            DisplayName = $user.DisplayName
        }
        $user.DisplayName
    }
}


$result | Format-Table
$result.Count 
#>

$stopwatch.Stop()
$stopwatch.Elapsed.TotalSeconds