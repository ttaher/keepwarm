$ErrorActionPreference = 'Stop'

$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [string]$Name,
        [ValidateSet('pass', 'fail', 'warn', 'info')][string]$Status,
        [string]$Message
    )

    $checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        message = $Message
    })
}

function Test-HttpEndpoint {
    param([string]$Uri)

    try {
        Invoke-WebRequest -Uri $Uri -TimeoutSec 3 -UseBasicParsing | Out-Null
        return $true
    } catch {
        return $false
    }
}

try {
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
    $backendPath = Join-Path $repoRoot 'backend'

    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) {
        Add-Check 'Node.js' 'fail' 'Node.js is not installed or is not on PATH.'
    } else {
        $nodeVersionText = (& node --version 2>$null | Select-Object -First 1).Trim()
        $nodeVersion = $null
        if ($nodeVersionText -match '^v?(\d+\.\d+\.\d+)') {
            $nodeVersion = [version]$Matches[1]
        }

        if ($nodeVersion -and $nodeVersion.Major -ge 18) {
            Add-Check 'Node.js' 'pass' "Node.js $nodeVersionText is installed (18+ required)."
        } else {
            Add-Check 'Node.js' 'fail' "Node.js version '$nodeVersionText' is unsupported or could not be read; version 18+ is required."
        }
    }

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Add-Check 'npm' 'pass' 'npm is available on PATH.'
    } else {
        Add-Check 'npm' 'fail' 'npm is not installed or is not on PATH.'
    }

    foreach ($part in @('frontend', 'backend')) {
        $modulesPath = Join-Path (Join-Path $repoRoot $part) 'node_modules'
        if (Test-Path -LiteralPath $modulesPath -PathType Container) {
            Add-Check "$part dependencies" 'pass' 'node_modules is present.'
        } else {
            Add-Check "$part dependencies" 'fail' 'node_modules is missing; project dependencies may not be installed.'
        }
    }

    foreach ($port in @(5173, 3000)) {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
        if ($listeners.Count -eq 0) {
            Add-Check "Port $port" 'pass' 'No process is listening on this port.'
        } else {
            $processIds = @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
            $processNames = @(
                foreach ($processId in $processIds) {
                    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                    if ($process) { $process.ProcessName }
                }
            )
            $owners = if ($processNames.Count -gt 0) { $processNames -join ', ' } else { 'unknown process' }
            Add-Check "Port $port" 'warn' "Port is occupied by $owners; confirm it is the expected app server."
        }
    }

    if (Test-HttpEndpoint 'http://localhost:5173/') {
        Add-Check 'Frontend' 'pass' 'The Vite frontend responds at http://localhost:5173/.'
    } else {
        Add-Check 'Frontend' 'fail' 'The frontend did not respond at http://localhost:5173/.'
    }

    try {
        $health = Invoke-RestMethod -Uri 'http://localhost:3000/health' -TimeoutSec 3
        if ($health.status -eq 'ok') {
            Add-Check 'Backend API' 'pass' 'The API health endpoint responds successfully.'
        } else {
            Add-Check 'Backend API' 'fail' 'The API responded, but its health status was not ok.'
        }
    } catch {
        Add-Check 'Backend API' 'fail' 'The API health endpoint did not respond at http://localhost:3000/health.'
    }

    $databasePath = if ($env:DB_PATH) { $env:DB_PATH } else { 'keepwarm.db' }
    if (-not [System.IO.Path]::IsPathRooted($databasePath)) {
        $databasePath = Join-Path $backendPath $databasePath
    }
    $databasePath = [System.IO.Path]::GetFullPath($databasePath)

    if (Test-Path -LiteralPath $databasePath -PathType Leaf) {
        try {
            $databaseHandle = [System.IO.File]::Open(
                $databasePath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::ReadWrite
            )
            $databaseHandle.Dispose()
            Add-Check 'SQLite database' 'pass' "Database file exists and is accessible: $databasePath"
        } catch {
            Add-Check 'SQLite database' 'fail' "Database file exists but cannot be opened for read/write access: $databasePath"
        }
    } elseif (Test-Path -LiteralPath (Split-Path -Parent $databasePath) -PathType Container) {
        Add-Check 'SQLite database' 'warn' "Database file does not exist yet; the backend normally creates it on startup: $databasePath"
    } else {
        Add-Check 'SQLite database' 'fail' "The database directory does not exist: $(Split-Path -Parent $databasePath)"
    }

    $overallStatus = if (@($checks | Where-Object status -eq 'fail').Count -gt 0) {
        'fail'
    } elseif (@($checks | Where-Object status -eq 'warn').Count -gt 0) {
        'warn'
    } else {
        'pass'
    }

    [pscustomobject]@{
        project = 'KeepWarm'
        overallStatus = $overallStatus
        checks = @($checks)
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    [pscustomobject]@{
        project = 'KeepWarm'
        overallStatus = 'error'
        checks = @($checks)
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 5 -Compress
}