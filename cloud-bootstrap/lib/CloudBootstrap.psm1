Set-StrictMode -Version Latest

function Write-CloudBootstrapLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Error', 'Plan', 'Action')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp][$Level] $Message"
}

function New-CloudBootstrapContext {
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$RootPath = (Get-Location).Path,
        [bool]$DryRun = $true
    )

    [pscustomobject]@{
        Operation = $Operation
        RootPath   = (Resolve-Path -LiteralPath $RootPath).Path
        DryRun     = $DryRun
        Timestamp  = Get-Date
    }
}

function Test-CloudBootstrapPathInsideRoot {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $rootResolved = [System.IO.Path]::GetFullPath($RootPath)
    $pathResolved = [System.IO.Path]::GetFullPath($Path)

    return $pathResolved.StartsWith($rootResolved, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-CloudBootstrapPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-CloudBootstrapFileInventory {
    param(
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $items = foreach ($candidate in $Path) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }

        Get-ChildItem -LiteralPath $candidate -File -Recurse -Force -ErrorAction SilentlyContinue |
            Select-Object FullName, Length, LastWriteTime
    }

    $items | Sort-Object Length -Descending
}

function Get-CloudBootstrapDefaultDriveRoots {
    $roots = @()

    if ($env:USERPROFILE) {
        $roots += Join-Path $env:USERPROFILE 'Streaming de Google Drive\Mi unidad'
        $roots += Join-Path $env:USERPROFILE 'GoogleDrive_ProjectSpace'
        $roots += Join-Path $env:USERPROFILE 'Google Drive'
        $roots += Join-Path $env:USERPROFILE 'My Drive'
    }

    $roots += 'G:\Mi unidad'
    $roots += 'C:\Google drive\Mi unidad'
    $roots += 'C:\Google drive'

    if ($env:GOOGLE_DRIVE_ROOT) {
        $roots += $env:GOOGLE_DRIVE_ROOT
    }

    return $roots |
        Where-Object { $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -Unique
}

function Get-CloudBootstrapBrowserStatus {
    param(
        [ValidateSet('Chrome', 'Edge')]
        [string]$Name
    )

    $regPath = switch ($Name) {
        'Chrome' { 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' }
        'Edge' { 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' }
    }

    $candidates = @()
    try {
        $reg = Get-ItemProperty -Path $regPath -ErrorAction Stop
        if ($reg.'(default)') {
            $candidates += $reg.'(default)'
        }
    } catch {
    }

    switch ($Name) {
        'Chrome' {
            if ($env:USERPROFILE) {
                $candidates += Join-Path $env:USERPROFILE 'AppData\Local\Google\Chrome\Application\chrome.exe'
            }
            if ($env:ProgramFiles) {
                $candidates += Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
            }
            if (${env:ProgramFiles(x86)}) {
                $candidates += Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'
            }
        }
        'Edge' {
            if ($env:ProgramFiles) {
                $candidates += Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'
            }
            if (${env:ProgramFiles(x86)}) {
                $candidates += Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
            }
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Set-CloudBootstrapRegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord,
        [bool]$DryRun = $true
    )

    Invoke-CloudBootstrapAction -DryRun $DryRun -Description "Set registry $Path -> $Name = $Value" -Action {
        try {
            if (-not (Test-Path -LiteralPath $Path)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }

            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        } catch {
            $warnMessage = "Registry write skipped for {0} -> {1}: {2}" -f $Path, $Name, $_.Exception.Message
            Write-CloudBootstrapLog -Level Warn -Message $warnMessage
        }
    }
}

function Get-CloudBootstrapDriveSnapshot {
    $snapshot = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DeviceID -in @('C:', 'G:') } |
        Sort-Object DeviceID |
        ForEach-Object {
            [pscustomobject]@{
                Drive = $_.DeviceID
                FreeGB = [math]::Round(([double]$_.FreeSpace / 1GB), 2)
                TotalGB = [math]::Round(([double]$_.Size / 1GB), 2)
            }
        }

    return $snapshot
}

function Invoke-CloudBootstrapAction {
    param(
        [Parameter(Mandatory)]
        [string]$Description,

        [scriptblock]$Action,
        [bool]$DryRun = $true
    )

    if ($DryRun) {
        Write-CloudBootstrapLog -Level Plan -Message $Description
        return
    }

    Write-CloudBootstrapLog -Level Action -Message $Description
    & $Action
}

Export-ModuleMember -Function `
    Write-CloudBootstrapLog, `
    New-CloudBootstrapContext, `
    Test-CloudBootstrapPathInsideRoot, `
    Resolve-CloudBootstrapPath, `
    Get-CloudBootstrapFileInventory, `
    Get-CloudBootstrapDefaultDriveRoots, `
    Get-CloudBootstrapBrowserStatus, `
    Set-CloudBootstrapRegistryValue, `
    Get-CloudBootstrapDriveSnapshot, `
    Invoke-CloudBootstrapAction
