[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [string]$ConfigPath = "$env:USERPROFILE\.oci\config",

    [string]$Profile = 'DEFAULT',

    [string]$InstanceName = 'pc-offload-a1-6gb',

    [string]$VcnName = 'pc-offload-vcn',

    [string]$SubnetName = 'pc-offload-public-subnet',

    [string]$InternetGatewayName = 'pc-offload-igw',

    [string]$RouteTableName = 'pc-offload-public-rt',

    [string]$SecurityListName = 'pc-offload-ssh-current-ip',

    [string]$SshKeyPath = "$env:USERPROFILE\.ssh\oci_pc_offload_a1_ed25519",

    [int]$BootVolumeSizeGb = 50
)

if ($Commit) {
    $DryRun = $false
}

$modulePath = Join-Path $PSScriptRoot '..\lib\CloudBootstrap.psm1'
Import-Module $modulePath -Force

$ociPath = 'C:\Program Files (x86)\Oracle\oci_cli\oci.exe'
if (-not (Test-Path -LiteralPath $ociPath)) {
    $ociCommand = Get-Command oci -ErrorAction SilentlyContinue
    if (-not $ociCommand) {
        throw 'OCI CLI was not found.'
    }

    $ociPath = $ociCommand.Source
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "OCI config was not found at '$ConfigPath'."
}

function Invoke-OciJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & $ociPath @Arguments --config-file $ConfigPath --profile $Profile --output json 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    return ($output | ConvertFrom-Json)
}

function Invoke-OciText {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & $ociPath @Arguments --config-file $ConfigPath --profile $Profile 2>&1
    return [pscustomobject]@{
        Output = ($output -join [Environment]::NewLine)
        ExitCode = $LASTEXITCODE
    }
}

function New-JsonInputFile {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $root = Join-Path $env:TEMP 'oci-pc-offload'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    $path = Join-Path $root $Name
    ConvertTo-Json -InputObject $InputObject -Compress -Depth 12 |
        Set-Content -LiteralPath $path -Encoding ascii

    return "file://$path"
}

function New-CloudInitFile {
    $root = Join-Path $env:TEMP 'oci-pc-offload'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    $path = Join-Path $root 'cloud-init.yaml'
    @'
#cloud-config
package_update: true
packages:
  - git
  - python3
  - python3-venv
  - python3-pip
  - htop
  - unzip
runcmd:
  - mkdir -p /opt/pc-offload
  - git clone https://github.com/israelrealivazquez-lang/pc-speed-cloud-bootstrap.git /opt/pc-speed-cloud-bootstrap || true
  - chown -R ubuntu:ubuntu /opt/pc-offload /opt/pc-speed-cloud-bootstrap || true
  - echo "pc-offload ready" > /opt/pc-offload/READY.txt
'@ | Set-Content -LiteralPath $path -Encoding ascii

    return $path
}

function Get-OciConfigValue {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $line = Get-Content -LiteralPath $ConfigPath |
        Where-Object { $_ -match ("^{0}\s*=" -f [regex]::Escape($Name)) } |
        Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -replace ("^{0}\s*=\s*" -f [regex]::Escape($Name)), '').Trim()
}

function Get-FirstActiveByName {
    param(
        [AllowNull()]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    if (-not $Items) {
        return $null
    }

    return @($Items) |
        Where-Object { $_.'display-name' -eq $DisplayName -and $_.'lifecycle-state' -ne 'TERMINATED' } |
        Select-Object -First 1
}

$tenancyId = Get-OciConfigValue -Name 'tenancy'
if (-not $tenancyId) {
    throw "OCI config '$ConfigPath' does not contain tenancy=."
}

$regionSubscriptions = Invoke-OciJson -Arguments @('iam', 'region-subscription', 'list', '--tenancy-id', $tenancyId)
$homeRegion = $regionSubscriptions.data | Where-Object { $_.'is-home-region' } | Select-Object -First 1
Write-CloudBootstrapLog -Level Info -Message "OCI profile '$Profile' works. Home region: $($homeRegion.'region-name')"

$availabilityDomain = (Invoke-OciJson -Arguments @('iam', 'availability-domain', 'list', '--compartment-id', $tenancyId)).data |
    Select-Object -First 1
if (-not $availabilityDomain) {
    throw 'No availability domain found.'
}

$shape = (Invoke-OciJson -Arguments @('compute', 'shape', 'list', '--compartment-id', $tenancyId, '--availability-domain', $availabilityDomain.name, '--all')).data |
    Where-Object { $_.shape -eq 'VM.Standard.A1.Flex' } |
    Select-Object -First 1
if (-not $shape) {
    throw 'VM.Standard.A1.Flex was not found in this availability domain.'
}

Write-CloudBootstrapLog -Level Info -Message "A1 Flex available in $($availabilityDomain.name): $($shape.ocpus) OCPU, $($shape.'memory-in-gbs') GB RAM."

$instances = (Invoke-OciJson -Arguments @('compute', 'instance', 'list', '--compartment-id', $tenancyId, '--all')).data
$instance = Get-FirstActiveByName -Items $instances -DisplayName $InstanceName
if ($instance) {
    Write-CloudBootstrapLog -Level Info -Message "Instance '$InstanceName' already exists with state '$($instance.'lifecycle-state')'."
    return $instance
}

$vcns = (Invoke-OciJson -Arguments @('network', 'vcn', 'list', '--compartment-id', $tenancyId, '--all')).data
$vcn = Get-FirstActiveByName -Items $vcns -DisplayName $VcnName
if (-not $vcn) {
    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create VCN '$VcnName' (10.60.0.0/16)" -Action {
        $script:vcn = (Invoke-OciJson -Arguments @(
            'network', 'vcn', 'create',
            '--compartment-id', $tenancyId,
            '--display-name', $VcnName,
            '--cidr-block', '10.60.0.0/16',
            '--dns-label', 'pcoffload',
            '--wait-for-state', 'AVAILABLE',
            '--max-wait-seconds', '300'
        )).data
    }
}

if ($DryRun -and -not $vcn) {
    Write-CloudBootstrapLog -Level Plan -Message "Run with -Commit to create networking and launch '$InstanceName'."
    return
}

$internetGateways = (Invoke-OciJson -Arguments @('network', 'internet-gateway', 'list', '--compartment-id', $tenancyId, '--vcn-id', $vcn.id, '--all')).data
$internetGateway = Get-FirstActiveByName -Items $internetGateways -DisplayName $InternetGatewayName
if (-not $internetGateway) {
    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create internet gateway '$InternetGatewayName'" -Action {
        $script:internetGateway = (Invoke-OciJson -Arguments @(
            'network', 'internet-gateway', 'create',
            '--compartment-id', $tenancyId,
            '--vcn-id', $vcn.id,
            '--is-enabled', 'true',
            '--display-name', $InternetGatewayName,
            '--wait-for-state', 'AVAILABLE',
            '--max-wait-seconds', '300'
        )).data
    }
}

$routeTables = (Invoke-OciJson -Arguments @('network', 'route-table', 'list', '--compartment-id', $tenancyId, '--vcn-id', $vcn.id, '--all')).data
$routeTable = Get-FirstActiveByName -Items $routeTables -DisplayName $RouteTableName
if (-not $routeTable) {
    $routeRules = New-JsonInputFile -Name 'route-rules.json' -InputObject @(
        [ordered]@{
            destination     = '0.0.0.0/0'
            destinationType = 'CIDR_BLOCK'
            networkEntityId = $internetGateway.id
            description     = 'Default route to internet gateway'
        }
    )

    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create route table '$RouteTableName'" -Action {
        $script:routeTable = (Invoke-OciJson -Arguments @(
            'network', 'route-table', 'create',
            '--compartment-id', $tenancyId,
            '--vcn-id', $vcn.id,
            '--display-name', $RouteTableName,
            '--route-rules', $routeRules,
            '--wait-for-state', 'AVAILABLE',
            '--max-wait-seconds', '300'
        )).data
    }
}

$publicIp = $null
try {
    $publicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).Trim()
} catch {
    Write-CloudBootstrapLog -Level Warn -Message "Could not read public IP for SSH allowlist: $($_.Exception.Message)"
}

$securityLists = (Invoke-OciJson -Arguments @('network', 'security-list', 'list', '--compartment-id', $tenancyId, '--vcn-id', $vcn.id, '--all')).data
$securityList = Get-FirstActiveByName -Items $securityLists -DisplayName $SecurityListName
if (-not $securityList) {
    if (-not $publicIp) {
        throw 'Cannot create SSH security list without a current public IP.'
    }

    $ingressRules = New-JsonInputFile -Name 'ingress-security-rules.json' -InputObject @(
        [ordered]@{
            protocol    = '6'
            source      = "$publicIp/32"
            sourceType  = 'CIDR_BLOCK'
            isStateless = $false
            description = 'SSH from current PC only'
            tcpOptions  = [ordered]@{
                destinationPortRange = [ordered]@{
                    min = 22
                    max = 22
                }
            }
        }
    )
    $egressRules = New-JsonInputFile -Name 'egress-security-rules.json' -InputObject @(
        [ordered]@{
            protocol        = 'all'
            destination     = '0.0.0.0/0'
            destinationType = 'CIDR_BLOCK'
            isStateless     = $false
            description     = 'Allow outbound internet for updates/offload jobs'
        }
    )

    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create SSH security list '$SecurityListName' for $publicIp/32" -Action {
        $script:securityList = (Invoke-OciJson -Arguments @(
            'network', 'security-list', 'create',
            '--compartment-id', $tenancyId,
            '--vcn-id', $vcn.id,
            '--display-name', $SecurityListName,
            '--ingress-security-rules', $ingressRules,
            '--egress-security-rules', $egressRules,
            '--wait-for-state', 'AVAILABLE',
            '--max-wait-seconds', '300'
        )).data
    }
}

$subnets = (Invoke-OciJson -Arguments @('network', 'subnet', 'list', '--compartment-id', $tenancyId, '--vcn-id', $vcn.id, '--all')).data
$subnet = Get-FirstActiveByName -Items $subnets -DisplayName $SubnetName
if (-not $subnet) {
    $securityListIds = New-JsonInputFile -Name 'security-list-ids.json' -InputObject @($securityList.id)
    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Create public subnet '$SubnetName'" -Action {
        $script:subnet = (Invoke-OciJson -Arguments @(
            'network', 'subnet', 'create',
            '--compartment-id', $tenancyId,
            '--vcn-id', $vcn.id,
            '--display-name', $SubnetName,
            '--cidr-block', '10.60.1.0/24',
            '--dns-label', 'public1',
            '--route-table-id', $routeTable.id,
            '--security-list-ids', $securityListIds,
            '--prohibit-public-ip-on-vnic', 'false',
            '--wait-for-state', 'AVAILABLE',
            '--max-wait-seconds', '300'
        )).data
    }
}

if ($DryRun) {
    Write-CloudBootstrapLog -Level Plan -Message "Run with -Commit to launch '$InstanceName' on VM.Standard.A1.Flex (1 OCPU, 6 GB RAM)."
    return
}

$publicKeyPath = "$SshKeyPath.pub"
if (-not (Test-Path -LiteralPath $publicKeyPath)) {
    throw "SSH public key not found at '$publicKeyPath'."
}

$cloudInitPath = New-CloudInitFile
$shapeConfig = New-JsonInputFile -Name 'shape-config.json' -InputObject ([ordered]@{
    ocpus       = 1
    memoryInGBs = 6
})
$image = (Invoke-OciJson -Arguments @(
    'compute', 'image', 'list',
    '--compartment-id', $tenancyId,
    '--shape', 'VM.Standard.A1.Flex',
    '--operating-system', 'Canonical Ubuntu',
    '--sort-by', 'TIMECREATED',
    '--sort-order', 'DESC'
)).data |
    Where-Object { $_.'display-name' -like 'Canonical-Ubuntu-24.04-aarch64-*' -and $_.'display-name' -notlike '*Minimal*' } |
    Sort-Object 'time-created' -Descending |
    Select-Object -First 1

if (-not $image) {
    throw 'No Canonical Ubuntu 24.04 aarch64 image was found for A1 Flex.'
}

Write-CloudBootstrapLog -Level Action -Message "Launching '$InstanceName' on VM.Standard.A1.Flex (1 OCPU, 6 GB RAM)."
$launch = Invoke-OciText -Arguments @(
    'compute', 'instance', 'launch',
    '--availability-domain', $availabilityDomain.name,
    '--compartment-id', $tenancyId,
    '--shape', 'VM.Standard.A1.Flex',
    '--shape-config', $shapeConfig,
    '--display-name', $InstanceName,
    '--hostname-label', 'pcoffload',
    '--image-id', $image.id,
    '--boot-volume-size-in-gbs', "$BootVolumeSizeGb",
    '--subnet-id', $subnet.id,
    '--assign-public-ip', 'true',
    '--ssh-authorized-keys-file', $publicKeyPath,
    '--user-data-file', $cloudInitPath,
    '--wait-for-state', 'RUNNING',
    '--max-wait-seconds', '900'
)

if ($launch.ExitCode -ne 0) {
    Write-CloudBootstrapLog -Level Warn -Message $launch.Output
    throw "OCI launch failed with exit code $($launch.ExitCode)."
}

$launched = $launch.Output | ConvertFrom-Json
Write-CloudBootstrapLog -Level Info -Message "Launched '$InstanceName' with state '$($launched.data.'lifecycle-state')'."
return $launched.data
