[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [switch]$RetryOracle,

    [string]$GitHubRepo = 'israelrealivazquez-lang/pc-speed-cloud-bootstrap'
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

function New-StatusRow {
    param(
        [Parameter(Mandatory)]
        [string]$Provider,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Use,

        [string]$NextStep = ''
    )

    [pscustomobject]@{
        Provider = $Provider
        Status   = $Status
        Use      = $Use
        NextStep = $NextStep
    }
}

$rows = New-Object System.Collections.Generic.List[object]

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghStatus = (& gh auth status 2>&1) -join [Environment]::NewLine
    $active = if ($ghStatus -match 'Logged in to github.com account') { 'authenticated' } else { 'needs auth' }
    $rows.Add((New-StatusRow -Provider 'GitHub' -Status $active -Use 'Actions/Codespaces for repo-heavy work without local RAM.' -NextStep "Run workflow_dispatch in $GitHubRepo or start an existing Codespace only when needed."))
} else {
    $rows.Add((New-StatusRow -Provider 'GitHub' -Status 'gh missing' -Use 'Actions/Codespaces.' -NextStep 'Install or repair GitHub CLI.'))
}

if (Get-Command hf -ErrorAction SilentlyContinue) {
    $hfStatus = (& hf auth whoami 2>&1) -join ' '
    $rows.Add((New-StatusRow -Provider 'Hugging Face' -Status $hfStatus -Use 'Jobs for CPU/GPU batch work when plan/quota allows.' -NextStep 'Use the Hugging Face MCP Jobs tool for actual submissions.'))
} else {
    $rows.Add((New-StatusRow -Provider 'Hugging Face' -Status 'hf CLI missing; MCP lane is available in Codex' -Use 'Jobs through MCP, no local RAM used.' -NextStep 'Install hf CLI only if local Hub file operations are needed.'))
}

if (Get-Command wrangler -ErrorAction SilentlyContinue) {
    $wranglerStatus = (& wrangler whoami 2>&1) -join ' '
    $rows.Add((New-StatusRow -Provider 'Cloudflare' -Status $wranglerStatus -Use 'Workers/R2 for lightweight orchestration and object storage.' -NextStep 'Use R2/Workers after API auth is repaired.'))
} else {
    $rows.Add((New-StatusRow -Provider 'Cloudflare' -Status 'API auth failed; wrangler missing' -Use 'Potential R2/Workers lane once authenticated.' -NextStep 'Authenticate Cloudflare API or install/login wrangler.'))
}

if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    $account = (& gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>&1) -join ' '
    $project = (& gcloud config get-value project 2>&1) -join ' '
    $rows.Add((New-StatusRow -Provider 'GCP' -Status "account=$account project=$project" -Use 'Always Free e2-micro / Cloud Shell style offload.' -NextStep 'Use Invoke-GcpAlwaysFreeVm.ps1 when billing is ready.'))
} else {
    $rows.Add((New-StatusRow -Provider 'GCP' -Status 'gcloud missing' -Use 'Always Free or Cloud Shell.' -NextStep 'Install Google Cloud SDK.'))
}

$ociScript = Join-Path $PSScriptRoot 'Invoke-OciA1OffloadVm.ps1'
if (Test-Path -LiteralPath $ociScript) {
    try {
        if ($RetryOracle) {
            & $ociScript -DryRun:$DryRun -Commit:$Commit
            $rows.Add((New-StatusRow -Provider 'Oracle OCI' -Status 'retry attempted' -Use 'Persistent Always Free A1 VM when host capacity is available.' -NextStep 'If capacity is exhausted, heartbeat retries later.'))
        } else {
            & $ociScript
            $rows.Add((New-StatusRow -Provider 'Oracle OCI' -Status 'verified' -Use 'Persistent Always Free A1 VM when host capacity is available.' -NextStep 'Run this hub with -RetryOracle -Commit to attempt launch.'))
        }
    } catch {
        $message = $_.Exception.Message
        if ($message -match 'Out of host capacity|TooManyRequests') {
            $rows.Add((New-StatusRow -Provider 'Oracle OCI' -Status 'capacity/rate limited' -Use 'Persistent Always Free A1 VM.' -NextStep 'Retry later; do not switch to paid shapes.'))
        } else {
            $rows.Add((New-StatusRow -Provider 'Oracle OCI' -Status 'needs attention' -Use 'Persistent Always Free A1 VM.' -NextStep $message))
        }
    }
} else {
    $rows.Add((New-StatusRow -Provider 'Oracle OCI' -Status 'script missing' -Use 'Persistent Always Free A1 VM.' -NextStep 'Restore Invoke-OciA1OffloadVm.ps1.'))
}

$rows | Format-Table -AutoSize

Write-CloudBootstrapLog -Level Info -Message 'Recommended lane order: Google Drive/Colab for file-backed batches, GitHub Actions for repo tasks, Oracle/GCP for persistent VM, Hugging Face Jobs for paid CPU/GPU batches, Cloudflare after auth repair.'

# This hub is a readiness report. Missing optional CLIs should not make CI fail.
$global:LASTEXITCODE = 0
