#Requires -Version 3
#Requires -Modules VMware.Vim.Automation.Core

$LogDate = Get-Date -Format "yyyy-MM-dd"
$Transcript = Start-Transcript -LiteralPath "$PSScriptRoot\logs\transcript-$LogDate.log"
Import-Module VMware.VimAutomation.Core -PassThru

# Configuration
$MaxThreads = [Int32]32 #I found 32 threads to be a good number when running on a 12 core server
$VMRegex = "^\w{2}-\w{3,4}-\d{3,4}$" # Use Regex to filter by name for VMs you want to clean. Try Regexr.com if you need help
$VCenter = "vcd.mydomain.com" # Your vCenter server
$SMTPServer = "smtp.mydomain.com" # Your SMTP server.
$EmailFrom = "me@mydomain.com" # Who to send the email as
$EmailTo = @("somedude1@mydomain.com", "somedude2@mydomain.com") # Who to send the email to
$EmailCC = @("otherguy1@mydomain.com", "otherguy2@mydomain.com") # Carbon copy
$EnableProfileRemoval = $True #Set to $False to prevent removal of stale user profiles.
$AccountBlacklist = @("Administrator",".NET v2.0 Classic",".NET v4.5 Classic",".NET v2.0",".NET v4.5","Classic .NET AppPool","DefaultAppPool","DefaultAppPool.IIS APPPOOL","Default","Default User","systemprofile","NetworkService","LocalService")

Function Get-VDIInventory
{
    [CmdletBinding(SupportsShouldProcess=$True, ConfirmImpact="Medium")]
    Param()

    Write-Verbose "Building VDI Inventory..."
    $DiskTable = New-Object System.Collections.ArrayList
    $Inventory = @(VMWare.VimAutomation.Core\Get-VM | Where-Object {$_.Name -Match $VMRegex -and $_.PowerState -eq "PoweredOn"})
    Write-Verbose "Building storage report..."
    $Inventory | ForEach-Object {
        $FreespaceC = [Double]($_.Guest.Disks | Where-Object {$_.Path -eq "C:\"}).FreeSpaceGB
        $CapacityC = [Double]($_.Guest.Disks | Where-Object {$_.Path -eq "C:\"}).CapacityGB
        $PercentageC = [Double][Math]::Round(($FreespaceC / $CapacityC) * 100,2)
        $FreespaceD = [Double]($_.Guest.Disks | Where-Object {$_.Path -eq "D:\"}).FreeSpaceGB
        $CapacityD = [Double]($_.Guest.Disks | Where-Object {$_.Path -eq "D:\"}).CapacityGB
        $PercentageD = [Double][Math]::Round(($FreespaceD / $CapacityD) * 100,2)

        $Hash = [Ordered]@{
            "VM" = $_.Name
            "[C:] Free Space (GB)" = $FreespaceC
            "[C:] Disk Capacity (GB)" = $CapacityC
            "[C:] Percent Free" = $PercentageC
            "[D:] Free Space (GB)" = $FreespaceD
            "[D:] Disk Capacity (GB)" = $CapacityD
            "[D:] Percent Free" =  $PercentageD
        }
        [void]$DiskTable.Add((New-Object PSObject -Property $Hash))
    }
    $DiskTableSorted = $DiskTable | Sort-Object -Property {$_."[D:] Percent Free"}
    Write-Verbose "$($DiskTableSorted.Count) VMs in Inventory"
    Return $DiskTableSorted
}

Connect-VIServer -Server $VCenter -Force -Verbose
$Inventory = Get-VDIInventory -Verbose
$Inventory | Export-Csv -LiteralPath "$PSScriptRoot\spacereport-pre.csv" -NoTypeInformation
Disconnect-VIServer -Server $VCenter -Force -Confirm:$False -Verbose

[Scriptblock]$Init = [Scriptblock]::Create((Get-Content $PSScriptRoot\Modules\Get-LastVMUser.psm1 -Raw))

ForEach ($VM in $Inventory)
{
    Write-Host "Current VM: $($Inventory.IndexOf($VM) + 1) of $($Inventory.Count)"

    While (@(Get-Job -State Running).Count -ge $MaxThreads)
    {
        Write-Host "Waiting for available thread... ($MaxThreads Maximum)"
        Start-Sleep -Seconds 5
    }

    Write-Host "Starting background cleanup on $($VM.VM)..."
    Start-Job -InitializationScript $Init -ArgumentList $VM, $AccountBlacklist, $EnableProfileRemoval -Name "$($VM.VM) Cleanup Job" -ScriptBlock {
        $Paths = @()
        $Paths += "\\$($Args[0].VM)\c$\Temp"
        $Paths += "\\$($Args[0].VM)\c$\Windows\Temp"
        $Paths += "\\$($Args[0].VM)\c$\Windows\ProPatches\Patches"
        $Paths += "\\$($Args[0].VM)\c$\Windows\MiniDump"
        $Paths += "\\$($Args[0].VM)\c$\Windows\LiveKernelReports"
        $Paths += "\\$($Args[0].VM)\c$\NVIDIA\DisplayDriver"
        $Paths += "\\$($Args[0].VM)\d$\Temp"
        $Paths += "\\$($Args[0].VM)\c$\$`Recycle.Bin"
        $Paths += "\\$($Args[0].VM)\d$\$`Recycle.Bin"
        $LastUser = (Get-LastVMUser -VM $Args[0].VM).LastUser
        
        # This section cleans up the assigned user profile, if the assigned user could not be detected, they will be skipped.
        If ($LastUser)
        {
            Write-Host "Last Signed In User on $($Args[0].VM): $LastUser"
            $Blacklist = $Args[1] + $LastUser
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Microsoft\Windows\INetCache"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Microsoft\Windows\Temporary Internet Files"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Google\Chrome\User Data\Default\Cache"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Google\Chrome\User Data\Default\Media Cache"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Google\Chrome\Update"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Google\Chrome SxS\User Data\Default\Cache"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Google\Chrome SxS\Update"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\CrashDumps"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Local\Microsoft\Terminal Server Client\Cache"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\LocalLow\Sun\Java\Deployment\cache\6.0"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Roaming\Five9\Logs"
            $Paths += "\\$($Args[0].VM)\d$\Users\$LastUser\AppData\Roaming\Microsoft\Excel"
            
            # If $EnableProfileRemoval is set to $True in configuration, the script will attempt to remove profiles all profiles that aren't in the blacklist
            If ($Args[2] -eq $True)
            {
                ForEach ($User in (Get-WmiObject -Class Win32_UserProfile -ComputerName $Args[0].VM | Where-Object {$_.LocalPath.Split("\")[-1] -notin $Blacklist -and $_.LocalPath.Split("\")[-1] -notlike "*00*"}))
                {
                    Write-Output "Attempting to remove profile: $($User.LocalPath)"
                    Try
                    {
                        $User | Remove-WmiObject -ErrorAction Stop
                    }
                    Catch
                    {
                        Write-Output "Unable to remove $($User.LocalPath)"
                    }
                }
            }
        }
        $Paths | ForEach-Object {
            If (Test-Path $_)
            {
                Write-Output "Emptying folder: $_"
                Remove-Item -Path $_\* -Recurse -Force -Confirm:$False -ErrorAction SilentlyContinue
            }
        }
    } | Out-Null
}
While (@(Get-Job -State Running).Count -gt 0)
{
    Write-Host "Waiting for background jobs..."
    Get-Job -State Running | Format-Table -AutoSize
    Start-Sleep -Seconds 5
}

Write-Host "Receiving failed background jobs..."
Get-Job -State Failed,Blocked | Export-Csv -LiteralPath "$PSScriptRoot\logs\FailedJobs-$LogDate.csv" -NoTypeInformation
Get-Job -State Failed,Blocked | Receive-Job | Out-File -LiteralPath "$PSScriptRoot\logs\FailedJobs-Detailed-$LogDate.log"
Get-Job -State Failed,Blocked | Remove-Job -Force

Write-Host "Receiving background jobs..."
$JobLog = Get-Job | Receive-Job
Get-Job | Remove-Job

$JobLog | Out-File -FilePath "$PSScriptRoot\logs\VDIcleanup-$LogDate.log"

# Make a post cleanup report and email the reports.
Connect-VIServer -Server $VCenter -Force -Verbose
$Inventory = Get-VDIInventory -Verbose
$Inventory | Export-Csv -LiteralPath "$PSScriptRoot\spacereport-post.csv" -NoTypeInformation
Disconnect-VIServer -Server $VCenter -Force -Confirm:$False -Verbose

Stop-Transcript

Send-MailMessage -From $EmailFrom -Subject "Automated VDI Cleanup Results" -To $EmailTo -Cc $EmailCC -Attachments $Transcript.Path,$PSScriptRoot\spacereport-pre.csv,$PSScriptRoot\spacereport-post.csv,$PSScriptRoot\logs\VDIcleanup-$LogDate.log,$PSScriptRoot\logs\FailedJobs-$LogDate.csv,$PSScriptRoot\logs\FailedJobs-Detailed-$LogDate.log -SmtpServer $SMTPServer -BodyAsHtml -Body "
<p>Team,</p>
<p>Please see the attached results for the automated VDI cleanup script.</p>
<p>Help Desk, please review the attached <b>spacereport-post.csv</b> file and perform manual cleanup on systems with low disk space.</p>"
