[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [string]$ProfileDirectory = 'Profile 6',

    [string]$DriveQuery = 'Antigravity_Cloud_Migration',

    [switch]$IncludeActions
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$chrome = Get-CloudBootstrapBrowserStatus -Name 'Chrome'
$repoUrl = 'https://github.com/israelrealivazquez-lang/pc-speed-cloud-bootstrap'
$colabUrl = 'https://colab.research.google.com/github/israelrealivazquez-lang/pc-speed-cloud-bootstrap/blob/main/cloud-bootstrap/colab/pc_offload_colab_bootstrap.ipynb'
$driveUrl = "https://drive.google.com/drive/search?q=$([System.Uri]::EscapeDataString($DriveQuery))"

$urls = @(
    $colabUrl,
    $driveUrl,
    $repoUrl
)

if ($IncludeActions) {
    $urls += "$repoUrl/actions"
}

if (-not $chrome) {
    Write-CloudBootstrapLog -Level Warn -Message 'Chrome was not found. Open the cloud workspace URLs manually.'
    foreach ($url in $urls) {
        Write-CloudBootstrapLog -Level Plan -Message $url
    }
    return
}

$description = "Open cloud workspace in Chrome profile '$ProfileDirectory'"
Invoke-CloudBootstrapAction -DryRun $DryRun -Description $description -Action {
    Start-Process -FilePath $chrome -ArgumentList @(
        "--profile-directory=$ProfileDirectory",
        '--new-window'
    ) + $urls
}
