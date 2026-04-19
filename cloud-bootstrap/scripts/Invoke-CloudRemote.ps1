[CmdletBinding()]
param(
    [ValidateSet('Ssh', 'WinRM')]
    [string]$Transport = 'Ssh',

    [Parameter(Mandatory)]
    [string]$HostName,

    [Parameter(Mandatory)]
    [string]$Command,

    [bool]$DryRun = $true,

    [switch]$Commit
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

switch ($Transport) {
    'Ssh' {
        $planned = "ssh $HostName `"$Command`""
        Invoke-CloudBootstrapAction -DryRun $DryRun -Description $planned -Action {
            ssh $HostName $Command
        }
    }
    'WinRM' {
        $planned = "Invoke-Command -ComputerName $HostName -ScriptBlock { $Command }"
        Invoke-CloudBootstrapAction -DryRun $DryRun -Description $planned -Action {
            Invoke-Command -ComputerName $HostName -ScriptBlock ([scriptblock]::Create($Command))
        }
    }
}
