# Prompt user for source paths
Write-Host "Enter the full path(s) to the folders you want to back up."
Write-Host "If you have multiple locations, separate them with a semicolon (;)."
Write-Host "Example: C:\Docs;D:\Projects"
$sourceInput = Read-Host "Enter source folder path(s)"
if ([string]::IsNullOrWhiteSpace($sourceInput)) {
    Write-Host "No source path entered. Exiting." -ForegroundColor Red
    exit
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
Start-Transcript -Path $logFile

try {
    $totalFiles = 0
    $allFiles = @()
    foreach ($src in $SourcePaths) {
        if (-not (Test-Path $src)) {
            Write-Warning "Source path does not exist: $src"
            continue
        }
        $files = Get-ChildItem -Path $src -Recurse -File
        $allFiles += $files
        $totalFiles += $files.Count
    }

    if ($totalFiles -eq 0) {
        Write-Host "No files found in the specified source path(s)." -ForegroundColor Yellow
        Stop-Transcript
        exit
    }

    $currentFile = 0

    foreach ($file in $allFiles) {
        $currentFile++
        # Find which source path this file belongs to
        $srcBase = $SourcePaths | Where-Object { $file.FullName.StartsWith($_) } | Select-Object -First 1
        $relativePath = $file.FullName.Substring($srcBase.Length).TrimStart('\')
        $destFile = Join-Path -Path $DestinationPath -ChildPath $relativePath
        $destDir = [System.IO.Path]::GetDirectoryName($destFile)

        # Create destination directory if needed and avoid trailing backslash
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        # Copy with hash verification and retry
        $maxRetries = 3
        $retry = 0
        $success = $false

        while (-not $success -and $retry -le $maxRetries) {
            try {
                Write-Progress -Activity "Backing Up Files" `
                               -Status "$currentFile/$totalFiles :: $($file.Name)" `
                               -PercentComplete ($currentFile/$totalFiles*100)

                $sourceHash = Get-FileHash -Path $file.FullName -Algorithm SHA256
                Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
                $destHash = Get-FileHash -Path $destFile -Algorithm SHA256

                if ($sourceHash.Hash -ne $destHash.Hash) {
                    throw "Hash mismatch for $($file.FullName)"
                }

                Write-Host "Copied: $($file.FullName) -> $destFile" -ForegroundColor Green
                $success = $true
            }
            catch {
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
    Stop-Transcript
    Write-Host "`nBackup completed. Backup location:" -ForegroundColor Cyan
    Write-Host $DestinationPath -ForegroundColor Yellow
    Write-Host "Log file: $logFile" -ForegroundColor Gray
}
