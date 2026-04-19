[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$chrome = Get-CloudBootstrapBrowserStatus -Name 'Chrome'
$url = 'https://colab.research.google.com/github/israelrealivazquez-lang/pc-speed-cloud-bootstrap/blob/main/cloud-bootstrap/colab/pc_offload_colab_bootstrap.ipynb'

if (-not $chrome) {
    Write-CloudBootstrapLog -Level Warn -Message 'Chrome was not found. Open the Colab bootstrap URL manually.'
    Write-CloudBootstrapLog -Level Plan -Message $url
    return
}

Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Open Colab bootstrap in Chrome: $url" -Action {
    Start-Process -FilePath $chrome -ArgumentList $url
}
