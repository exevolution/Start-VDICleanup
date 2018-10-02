# Usage Details
# Get-LastVMUser -VM myvmname01,myvmname02 -Verbose

Function Get-LastVMUser
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String[]]$VM
    )

    Begin
    {
        $VMUser = New-Object System.Collections.ArrayList
    }

    Process
    {
        ForEach ($V in $VM)
        {
            Try
            {
                Write-Verbose "Determining last user from WMI..."
                $UserName = (Get-WmiObject Win32_ComputerSystem -ComputerName $V).Username.Split("\")[-1]
            }
            Catch
            {
                Write-Verbose "Unable to determine user from WMI..."
                Try
                {
                    $DebugLogs = Get-ChildItem -Path "\\$V\c$\ProgramData\VMware\VDM\logs" -Filter "debug*" -ErrorAction Stop | Sort-Object -Property LastWriteTime -Descending
                }
                Catch
                {
                    Break
                }
            }

            If (!($UserName) -and $DebugLogs)
            {
                $UserName = ForEach ($Log in $DebugLogs)
                {
                    Write-Verbose "Scanning VDM log file: $($Log.FullName)"
                    $User = (($Log | Get-Content | Select-String -Pattern "LoggedOn_Username") -split '"')[-2]
                    If ($User -ne "" -and $Null -ne $User)
                    {
                        $User
                        Break
                    }
                }
            }
            $Hash = [Ordered]@{
                VM = $V
                LastUser = $UserName
            }
            $VMObject = New-Object PSObject -Property $Hash
            [void]$VMUser.Add($VMObject)
        }
    }
    End
    {
        Return $VMUser
    }
}
