[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [switch]$LaunchChrome,

    [switch]$LaunchEdge,

    [switch]$ApplyEdgePolicies
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$chrome = Get-CloudBootstrapBrowserStatus -Name 'Chrome'
$edge = Get-CloudBootstrapBrowserStatus -Name 'Edge'

Write-CloudBootstrapLog -Level Info -Message ("Chrome: " + ($(if ($chrome) { $chrome } else { 'not found' })))
Write-CloudBootstrapLog -Level Info -Message ("Edge: " + ($(if ($edge) { $edge } else { 'not found' })))

if ($ApplyEdgePolicies) {
    $edgePolicyPath = 'HKCU:\Software\Policies\Microsoft\Edge'
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'BackgroundModeEnabled' -Value 0
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'StartupBoostEnabled' -Value 0
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'HideFirstRunExperience' -Value 1
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $edgePolicyPath -Name 'MetricsReportingEnabled' -Value 0

    $explorerPolicyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $disallowRunPath = Join-Path $explorerPolicyPath 'DisallowRun'
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $explorerPolicyPath -Name 'DisallowRun' -Value 1
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $disallowRunPath -Name '1' -Value 'msedge.exe' -Type ([Microsoft.Win32.RegistryValueKind]::String)
    Set-CloudBootstrapRegistryValue -DryRun $DryRun -Path $disallowRunPath -Name '2' -Value 'msedge_proxy.exe' -Type ([Microsoft.Win32.RegistryValueKind]::String)

    if (-not $DryRun) {
        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

$launchPlan = @()

if ($LaunchChrome -and $chrome) {
    $launchPlan += [pscustomobject]@{ Name = 'Chrome'; Path = $chrome }
}

if ($LaunchEdge -and $edge) {
    $launchPlan += [pscustomobject]@{ Name = 'Edge'; Path = $edge }
}

if (-not $launchPlan) {
    Write-CloudBootstrapLog -Level Plan -Message 'No browser launches requested. This script only reports browser readiness in the scaffold.'
    return
}

foreach ($item in $launchPlan) {
    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Start $($item.Name) from $($item.Path)" -Action {
        Start-Process -FilePath $item.Path
    }
}
