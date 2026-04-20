[CmdletBinding()]
param(
    [bool]$DryRun = $true,

    [switch]$Commit,

    [string]$AccountId = $env:CLOUDFLARE_ACCOUNT_ID,

    [string]$ApiToken = $env:CLOUDFLARE_API_TOKEN,

    [string]$BucketName = 'pc-offload-2811',

    [switch]$CreateBucket
)

if ($Commit) {
    $DryRun = $false
}

function New-CloudflareResult {
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [string]$Status,

        [string]$Detail = ''
    )

    [pscustomobject]@{
        Check  = $Check
        Status = $Status
        Detail = $Detail
    }
}

function Invoke-CloudflareApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [object]$Body
    )

    $headers = @{
        Authorization = "Bearer $ApiToken"
    }

    $uri = "https://api.cloudflare.com/client/v4$Path"
    $parameters = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = ($Body | ConvertTo-Json -Depth 10)
    }

    Invoke-RestMethod @parameters
}

$results = New-Object System.Collections.Generic.List[object]

if ([string]::IsNullOrWhiteSpace($AccountId)) {
    $results.Add((New-CloudflareResult -Check 'account_id' -Status 'missing' -Detail 'Set CLOUDFLARE_ACCOUNT_ID or pass -AccountId.'))
}

if ([string]::IsNullOrWhiteSpace($ApiToken)) {
    $results.Add((New-CloudflareResult -Check 'api_token' -Status 'missing' -Detail 'Set CLOUDFLARE_API_TOKEN in the current shell. Do not commit tokens.'))
}

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize
    return
}

try {
    $account = Invoke-CloudflareApi -Method GET -Path "/accounts/$AccountId"
    $accountName = if ($account.result.name) { $account.result.name } else { $AccountId }
    $results.Add((New-CloudflareResult -Check 'account' -Status 'ok' -Detail $accountName))
} catch {
    $results.Add((New-CloudflareResult -Check 'account' -Status 'failed' -Detail $_.Exception.Message))
    $results | Format-Table -AutoSize
    return
}

try {
    $buckets = Invoke-CloudflareApi -Method GET -Path "/accounts/$AccountId/r2/buckets"
    $bucketCount = @($buckets.result.buckets).Count
    $results.Add((New-CloudflareResult -Check 'r2_list' -Status 'ok' -Detail "$bucketCount bucket(s) visible"))
} catch {
    $results.Add((New-CloudflareResult -Check 'r2_list' -Status 'failed' -Detail $_.Exception.Message))
}

try {
    $workers = Invoke-CloudflareApi -Method GET -Path "/accounts/$AccountId/workers/scripts"
    $workerCount = @($workers.result).Count
    $results.Add((New-CloudflareResult -Check 'workers_list' -Status 'ok' -Detail "$workerCount worker(s) visible"))
} catch {
    $results.Add((New-CloudflareResult -Check 'workers_list' -Status 'failed' -Detail $_.Exception.Message))
}

if ($CreateBucket) {
    if ($DryRun) {
        $results.Add((New-CloudflareResult -Check 'r2_create_bucket' -Status 'dry-run' -Detail "Would create '$BucketName'. Run with -Commit to create."))
    } else {
        try {
            $body = @{
                name         = $BucketName
                storageClass = 'InfrequentAccess'
            }
            $created = Invoke-CloudflareApi -Method POST -Path "/accounts/$AccountId/r2/buckets" -Body $body
            $createdName = if ($created.result.name) { $created.result.name } else { $BucketName }
            $results.Add((New-CloudflareResult -Check 'r2_create_bucket' -Status 'ok' -Detail $createdName))
        } catch {
            $results.Add((New-CloudflareResult -Check 'r2_create_bucket' -Status 'failed' -Detail $_.Exception.Message))
        }
    }
}

$results | Format-Table -AutoSize
