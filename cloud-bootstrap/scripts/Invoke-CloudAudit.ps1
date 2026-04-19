[CmdletBinding()]
param(
    [string[]]$Path = @((Get-Location).Path),

    [bool]$DryRun = $true,

    [int]$Top = 25
)

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$context = New-CloudBootstrapContext -Operation 'audit' -DryRun $DryRun
Write-CloudBootstrapLog -Level Info -Message "Audit root: $($context.RootPath)"

$inventory = Get-CloudBootstrapFileInventory -Path $Path

if (-not $inventory) {
    Write-CloudBootstrapLog -Level Warn -Message 'No files found for audit.'
    return
}

$inventory |
    Select-Object -First $Top |
    ForEach-Object {
        [pscustomobject]@{
            Path          = $_.FullName
            SizeBytes     = $_.Length
            LastWriteTime  = $_.LastWriteTime
            OffloadBucket  = if ($_.Length -ge 1GB) { 'large' } elseif ($_.Length -ge 100MB) { 'medium' } else { 'small' }
        }
    } |
    Format-Table -AutoSize
