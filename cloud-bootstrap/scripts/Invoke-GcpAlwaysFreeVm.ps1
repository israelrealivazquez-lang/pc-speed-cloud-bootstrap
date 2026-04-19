[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [string]$ProjectId = 'antigravity-pc1-auto',

    [string]$ExpectedAccount = 'israel.realivazquez2811@gmail.com',

    [string]$InstanceName = 'antigravity-free-vm',

    [string]$Zone = 'us-central1-a',

    [string]$MachineType = 'e2-micro',

    [int]$DiskSizeGb = 30,

    [string]$ImageFamily = 'debian-12',

    [string]$ImageProject = 'debian-cloud',

    [string]$FirewallRuleName = 'allow-iap-ssh',

    [switch]$UseExternalIp,

    [switch]$OpenBillingIfDisabled
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$env:CLOUDSDK_CORE_DISABLE_PROMPTS = '1'
$chrome = Get-CloudBootstrapBrowserStatus -Name 'Chrome'

function Invoke-GcloudText {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & gcloud @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $exitCode
    }
}

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    throw 'gcloud CLI was not found in PATH.'
}

$activeAccount = (Invoke-GcloudText -Arguments @('auth', 'list', '--filter=status:ACTIVE', '--format=value(account)')).Output.Trim()
if ($activeAccount -and $ExpectedAccount -and ($activeAccount -ne $ExpectedAccount)) {
    Write-CloudBootstrapLog -Level Warn -Message "Active gcloud account is '$activeAccount', expected '$ExpectedAccount'."
} else {
    Write-CloudBootstrapLog -Level Info -Message "Active gcloud account: $activeAccount"
}

$configuredProject = (Invoke-GcloudText -Arguments @('config', 'get-value', 'project')).Output.Trim()
if ($configuredProject -and ($configuredProject -ne $ProjectId)) {
    Write-CloudBootstrapLog -Level Warn -Message "Configured gcloud project is '$configuredProject', target project is '$ProjectId'."
}

$billingInfoResult = Invoke-GcloudText -Arguments @('billing', 'projects', 'describe', $ProjectId, '--format=json')
if ($billingInfoResult.ExitCode -ne 0) {
    throw "Unable to read billing status for project '$ProjectId': $($billingInfoResult.Output)"
}

$billingInfo = $billingInfoResult.Output | ConvertFrom-Json
if (-not $billingInfo.billingEnabled) {
    Write-CloudBootstrapLog -Level Warn -Message "Billing is disabled for project '$ProjectId'. Re-enable or relink billing before creating the VM."

    if ($OpenBillingIfDisabled -and $chrome) {
        $urls = @(
            "https://console.cloud.google.com/billing/projects?project=$ProjectId",
            "https://console.cloud.google.com/billing?project=$ProjectId"
        )

        Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Open GCP billing pages in Chrome for project '$ProjectId'" -Action {
            Start-Process -FilePath $chrome -ArgumentList @('--profile-directory=Profile 6', '--new-window') + $urls
        }
    }

    return
}

$instanceDescribe = Invoke-GcloudText -Arguments @('compute', 'instances', 'describe', $InstanceName, '--project', $ProjectId, '--zone', $Zone, '--format=value(name)')
if ($instanceDescribe.ExitCode -eq 0 -and $instanceDescribe.Output.Trim()) {
    Write-CloudBootstrapLog -Level Info -Message "Instance '$InstanceName' already exists in zone '$Zone'."
    Write-CloudBootstrapLog -Level Plan -Message "Connect later with: gcloud compute ssh $InstanceName --project $ProjectId --zone $Zone --tunnel-through-iap"
    return
}

$firewallDescribe = Invoke-GcloudText -Arguments @('compute', 'firewall-rules', 'describe', $FirewallRuleName, '--project', $ProjectId, '--format=value(name)')
if (-not ($firewallDescribe.ExitCode -eq 0 -and $firewallDescribe.Output.Trim())) {
    $firewallArgs = @(
        'compute', 'firewall-rules', 'create', $FirewallRuleName,
        '--project', $ProjectId,
        '--network', 'default',
        '--direction', 'INGRESS',
        '--priority', '1000',
        '--action', 'ALLOW',
        '--rules', 'tcp:22',
        '--source-ranges', '35.235.240.0/20',
        '--target-tags', 'iap-ssh'
    )

    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create IAP SSH firewall rule '$FirewallRuleName'" -Action {
        $result = Invoke-GcloudText -Arguments $firewallArgs
        if ($result.ExitCode -ne 0) {
            throw $result.Output
        }
    }
}

$createArgs = @(
    'compute', 'instances', 'create', $InstanceName,
    '--project', $ProjectId,
    '--zone', $Zone,
    '--machine-type', $MachineType,
    '--subnet', 'default',
    '--boot-disk-type', 'pd-standard',
    '--boot-disk-size', ("{0}GB" -f $DiskSizeGb),
    '--image-family', $ImageFamily,
    '--image-project', $ImageProject,
    '--tags', 'iap-ssh',
    '--metadata', 'enable-oslogin=TRUE'
)

if (-not $UseExternalIp) {
    $createArgs += '--no-address'
}

Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create Always Free candidate VM '$InstanceName' in '$Zone' using '$MachineType'" -Action {
    $result = Invoke-GcloudText -Arguments $createArgs
    if ($result.ExitCode -ne 0) {
        throw $result.Output
    }
}

Write-CloudBootstrapLog -Level Plan -Message "Connect with: gcloud compute ssh $InstanceName --project $ProjectId --zone $Zone --tunnel-through-iap"
