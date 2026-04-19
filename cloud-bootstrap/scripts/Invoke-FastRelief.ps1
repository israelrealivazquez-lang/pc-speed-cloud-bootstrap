[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [switch]$CleanNpmCache,

    [switch]$ApplyEdgePolicies,

    [string[]]$OneDriveOnlineOnlyPath = @(
        'C:\Users\Lenovo\OneDrive\.gemini_cloud',
        'C:\Users\Lenovo\OneDrive\.antigravity_nexus',
        'C:\Users\Lenovo\OneDrive\Nexus_Core'
    )
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$before = Get-CloudBootstrapDriveSnapshot
Write-CloudBootstrapLog -Level Info -Message ('Before snapshot: ' + (($before | ConvertTo-Json -Compress)))

if ($CleanNpmCache) {
    Invoke-CloudBootstrapAction -DryRun $DryRun -Description 'Clean npm cache with npm cache clean --force' -Action {
        npm cache clean --force | Out-Null
    }
}

if ($ApplyEdgePolicies) {
    $edgePolicyPath = 'HKCU:\Software\Policies\Microsoft\Edge'
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'BackgroundModeEnabled' -Value 0
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'StartupBoostEnabled' -Value 0
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'HideFirstRunExperience' -Value 1

    $explorerPolicyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $disallowRunPath = Join-Path $explorerPolicyPath 'DisallowRun'
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $explorerPolicyPath -Name 'DisallowRun' -Value 1
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $disallowRunPath -Name '1' -Value 'msedge.exe' -Type ([Microsoft.Win32.RegistryValueKind]::String)
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $disallowRunPath -Name '2' -Value 'msedge_proxy.exe' -Type ([Microsoft.Win32.RegistryValueKind]::String)

    if (-not $DryRun) {
        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

foreach ($path in $OneDriveOnlineOnlyPath) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-CloudBootstrapLog -Level Warn -Message "Skipping missing OneDrive path: $path"
        continue
    }

    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Convert OneDrive content to online-only: $path" -Action {
        attrib +U -P $path /S /D | Out-Null
    }
}

$after = Get-CloudBootstrapDriveSnapshot
Write-CloudBootstrapLog -Level Info -Message ('After snapshot: ' + (($after | ConvertTo-Json -Compress)))
