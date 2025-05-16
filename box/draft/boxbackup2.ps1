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

# Verify and collect all valid files
$totalSizeBytes = 0
$allFiles = @()

foreach ($src in $SourcePaths) {
    if (-not (Test-Path $src)) {
        Write-Warning "Source path does not exist: $src"
        continue
    }
    $files = Get-ChildItem -Path $src -Recurse -File
    $allFiles += $files
    $totalSizeBytes += ($files | Measure-Object -Property Length -Sum).Sum
}

$totalFiles = $allFiles.Count

if ($totalFiles -eq 0) {
    Write-Host "No files found in the specified source path(s)." -ForegroundColor Yellow
    exit
}

# Convert size to readable format
function Convert-Size {
    param ($bytes)
    switch ($bytes) {
        { $_ -ge 1TB } { return "{0:N2} TB" -f ($bytes / 1TB) }
        { $_ -ge 1GB } { return "{0:N2} GB" -f ($bytes / 1GB) }
        { $_ -ge 1MB } { return "{0:N2} MB" -f ($bytes / 1MB) }
        { $_ -ge 1KB } { return "{0:N2} KB" -f ($bytes / 1KB) }
        default { return "$bytes Bytes" }
    }
}
$totalSizeDisplay = Convert-Size $totalSizeBytes

# Display stats and prompt user to continue
Write-Host "`nFound $totalFiles file(s) totaling $totalSizeDisplay." -ForegroundColor Cyan
$confirm = Read-Host "Are you sure you want to back up these files to Box? (Y/N)"
if ($confirm -notin @("Y", "y", "Yes", "yes")) {
    Write-Host "You cancelled the backup." -ForegroundColor Yellow
    exit
}

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
    $currentFile = 0
    foreach ($file in $allFiles) {
        $currentFile++

        # Find the source base path this file belongs to (case-insensitive match)
        $srcBase = $SourcePaths | Where-Object { $file.FullName.ToLower().StartsWith($_.ToLower()) } | Select-Object -First 1
        if (-not $srcBase) {
            Write-Warning "Unable to determine base path for file: $($file.FullName)"
            continue
        }

        # Build the relative path
        $relativePath = $file.FullName.Substring($srcBase.Length).TrimStart('\')
        $destFile = Join-Path -Path $DestinationPath -ChildPath $relativePath
        $destDir = [System.IO.Path]::GetDirectoryName($destFile)

        # Create destination directory if it doesn't exist
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
