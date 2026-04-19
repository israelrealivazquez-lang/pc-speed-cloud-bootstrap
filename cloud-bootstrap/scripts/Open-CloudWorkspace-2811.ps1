[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit
)

$scriptPath = Join-Path $PSScriptRoot 'Open-CloudWorkspace.ps1'
if ($Commit) {
    & $scriptPath -Commit -ProfileDirectory 'Profile 6' -IncludeActions
    return
}

& $scriptPath -DryRun:$DryRun -ProfileDirectory 'Profile 6' -IncludeActions
