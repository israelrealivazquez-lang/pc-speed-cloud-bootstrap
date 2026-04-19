[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$SourcePath,

    [string]$DestinationRoot,

    [ValidateSet('Copy', 'Move')]
    [string]$Mode = 'Copy',

    [bool]$DryRun = $true,

    [switch]$Commit
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$context = New-CloudBootstrapContext -Operation 'drive-offload' -DryRun $DryRun

if (-not $DestinationRoot) {
    $defaults = Get-CloudBootstrapDefaultDriveRoots
    if ($defaults.Count -gt 0) {
        $DestinationRoot = $defaults[0]
    }
}

if (-not $DestinationRoot) {
    Write-CloudBootstrapLog -Level Error -Message 'No destination root provided and no Google Drive root could be inferred.'
    return
}

if (-not (Test-Path -LiteralPath $DestinationRoot)) {
    if ($context.DryRun) {
        Write-CloudBootstrapLog -Level Plan -Message "Destination root does not exist yet, but this is acceptable for planning: $DestinationRoot"
    }
    else {
        Write-CloudBootstrapLog -Level Error -Message "Destination root does not exist: $DestinationRoot"
        return
    }
}

foreach ($source in $SourcePath) {
    if (-not (Test-Path -LiteralPath $source)) {
        Write-CloudBootstrapLog -Level Warn -Message "Skipping missing source: $source"
        continue
    }

    $resolvedSource = Resolve-CloudBootstrapPath -Path $source
    $safe = Test-CloudBootstrapPathInsideRoot -Path $resolvedSource -RootPath (Get-Location).Path

    if (-not $safe) {
        Write-CloudBootstrapLog -Level Warn -Message "Source is outside the current workspace root and will only be planned: $resolvedSource"
    }

    $batchRoot = Join-Path $DestinationRoot ("Offload_" + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    $target = Join-Path $batchRoot (Split-Path -Path $resolvedSource -Leaf)
    $description = "$Mode $resolvedSource to $target"

    Invoke-CloudBootstrapAction -DryRun $context.DryRun -Description $description -Action {
        New-Item -ItemType Directory -Path $batchRoot -Force | Out-Null

        if ($Mode -eq 'Move') {
            Move-Item -LiteralPath $resolvedSource -Destination $target -Force
        }
        else {
            Copy-Item -LiteralPath $resolvedSource -Destination $target -Recurse -Force
        }
    }
}

if ($context.DryRun) {
    Write-CloudBootstrapLog -Level Plan -Message 'Dry-run mode completed. No files were copied.'
}
