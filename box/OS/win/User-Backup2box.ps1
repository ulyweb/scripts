# User-Level Version
# User-Backup2box.ps1
# Description: Backs up specified user folders to Box.com under '01. My Personal Folder\recentBackup'.

# Check execution policy and warn if it's set to Restricted
$ep = Get-ExecutionPolicy -Scope CurrentUser
if ($ep -eq 'Restricted') {
    Write-Warning "Your current execution policy is '$ep', which may prevent this script from running properly."
    Write-Host "To fix this, run the following command in PowerShell:"
    Write-Host "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" -ForegroundColor Yellow
    Read-Host "Press Enter to continue (or close this window to cancel)"
}

# Prompt user for source folder paths
$CurrentUser = $env:USERNAME
Write-Host "Enter the full path(s) to the folders you want to back up." -ForegroundColor Cyan
Write-Host "If you have multiple locations, separate them with a semicolon (;)." -ForegroundColor Cyan
Write-Host "Example: C:\Users\$CurrentUser\Documents;C:\Users\$CurrentUser\Downloads;C:\Users\$CurrentUser\Desktop" -ForegroundColor Cyan
$sourceInput = Read-Host "Enter source folder path(s)"

if ([string]::IsNullOrWhiteSpace($sourceInput)) {
    Write-Host "No source path entered. Exiting." -ForegroundColor Red
    exit
}

# Split input into array of paths
$SourcePaths = $sourceInput -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

# Define Box Drive backup destination
$BoxDriveRoot = "C:\Users\$CurrentUser\Box\01. My Personal Folder\recentBackup"
$BackupFolderName = "Backup_$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
$DestinationPath = Join-Path -Path $BoxDriveRoot -ChildPath $BackupFolderName

# Create destination backup folder if it doesn't exist
if (-not (Test-Path -Path $DestinationPath)) {
    try {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create backup directory at $DestinationPath. $_"
        exit
    }
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
        exit
    }

    # Display total size
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "`nTotal files to back up: $totalFiles" -ForegroundColor Cyan
    Write-Host "Total size: $totalSizeMB MB" -ForegroundColor Cyan

    $confirm = Read-Host "Are you sure you want to start copying to Box? (Y/N)"
    if ($confirm -notin @('Y', 'y')) {
        Write-Host "Backup cancelled by user." -ForegroundColor Red
        exit
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
            try {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            } catch {
                Write-Warning "Failed to create directory: $destDir. $_"
                continue
            }
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
} catch {
    Write-Error "Backup failed: $_"
} finally {
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
    Write-Host "Log file: $logFile" -ForegroundColor Cyan
    Read-Host "`nPress Enter to close this window"
}
