# Ensure running with elevated privileges
function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Cyan
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    return
}

# Prompt user for source paths
Write-Host "Enter the full path(s) to the folders you want to back up."
Write-Host "If you have multiple locations, separate them with a semicolon (;)."
Write-Host "Example: C:\Docs;D:\Projects"
$sourceInput = Read-Host "Enter source folder path(s)"
if ([string]::IsNullOrWhiteSpace($sourceInput)) {
    Write-Host "No source path entered. Exiting." -ForegroundColor Red
    return
}

# Split input into array of paths
$SourcePaths = $sourceInput -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

# Get current user's Box Drive path
$CurrentUser = $env:USERNAME
$BoxDriveRoot = "C:\Users\$CurrentUser\Box\01. My Personal Folder\recentBackup"
$BackupFolderName = "Backup_$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
$DestinationPath = Join-Path -Path $BoxDriveRoot -ChildPath $BackupFolderName

# Create destination backup folder if it doesn't exist
if (-not (Test-Path -Path $DestinationPath)) {
    New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
}

# Start logging
$logFile = "$env:TEMP\BoxBackupLog_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
$transcriptStarted = $false
try {
    Start-Transcript -Path $logFile
    $transcriptStarted = $true

    $totalFiles = 0
    $totalSize = 0
    $allFiles = @()

    foreach ($src in $SourcePaths) {
        if (-not (Test-Path $src)) {
            Write-Warning "Source path does not exist: $src"
            continue
        }

        $fullPath = (Resolve-Path $src).Path
        $files = Get-ChildItem -Path $fullPath -Recurse -File
        $allFiles += $files
        $totalFiles += $files.Count
        $totalSize += ($files | Measure-Object -Property Length -Sum).Sum
    }

    if ($totalFiles -eq 0) {
        Write-Host "No files found in the specified source path(s)." -ForegroundColor Yellow
        return
    }

    # Display total size
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "`nTotal files: $totalFiles" -ForegroundColor Cyan
    Write-Host "Total size: $totalSizeMB MB" -ForegroundColor Cyan

    $confirm = Read-Host "Are you sure you want to start copying to Box? (Y/N)"
    if ($confirm -notin @('Y', 'y')) {
        Write-Host "Backup cancelled by user." -ForegroundColor Red
        return
    }

    $currentFile = 0

    foreach ($file in $allFiles) {
        $currentFile++

        $srcBase = $SourcePaths | Where-Object { $file.FullName.ToLower().StartsWith((Resolve-Path $_).Path.ToLower()) } | Select-Object -First 1
        if (-not $srcBase) {
            Write-Warning "Skipping file (source base not found): $($file.FullName)"
            continue
        }

        $srcBaseResolved = (Resolve-Path $srcBase).Path
        $relativePath = $file.FullName.Substring($srcBaseResolved.Length).TrimStart('\')
        if ($relativePath -match "^[A-Za-z]:\\") {
            Write-Warning "Skipping invalid relative path: $relativePath"
            continue
        }

        $destFile = Join-Path -Path $DestinationPath -ChildPath $relativePath
        $destDir = [System.IO.Path]::GetDirectoryName($destFile)

        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        $maxRetries = 3
        $retry = 0
        $success = $false

        while (-not $success -and $retry -le $maxRetries) {
            try {
                Write-Progress -Activity "Backing Up Files" `
                               -Status "$currentFile/$totalFiles :: $($file.Name)" `
                               -PercentComplete ($currentFile / $totalFiles * 100)

                $sourceHash = Get-FileHash -Path $file.FullName -Algorithm SHA256
                Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
                $destHash = Get-FileHash -Path $destFile -Algorithm SHA256

                if ($sourceHash.Hash -ne $destHash.Hash) {
                    throw "Hash mismatch for $($file.FullName)"
                }

                Write-Host "Copied: $($file.FullName) -> $destFile" -ForegroundColor Green
                $success = $true
            } catch {
                $retry++
                if ($retry -gt $maxRetries) {
                    Write-Warning "Failed to copy $($file.FullName) after $maxRetries attempts: $_"
                } else {
                    Write-Warning "Retrying ($retry/$maxRetries) for $($file.FullName): $_"
                    Start-Sleep -Seconds 10
                }
            }
        }
    }
}
catch {
    Write-Error "Backup failed: $_"
}
finally {
    Write-Progress -Activity "Backing Up Files" -Completed
    if ($transcriptStarted) {
        try {
            Stop-Transcript
        } catch {
            Write-Warning "Transcript already stopped or failed to stop cleanly."
        }
    }
    Write-Host "`nBackup completed. Backup location:" -ForegroundColor Cyan
    Write-Host $DestinationPath -ForegroundColor Yellow
    Write-Host "Log file: $logFile" -ForegroundColor Gray
}
