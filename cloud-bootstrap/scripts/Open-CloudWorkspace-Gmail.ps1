[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit
)

$scriptPath = Join-Path $PSScriptRoot 'Open-CloudWorkspace.ps1'
if ($Commit) {
    & $scriptPath -Commit -ProfileDirectory 'Default'
    return
}

& $scriptPath -DryRun:$DryRun -ProfileDirectory 'Default'
