# Backup Configuration
$SourcePath = "C:\CriticalData"
$BoxDrivePath = "C:\Users\username\Box"
$BackupFolderName = "Backup_$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
$DestinationPath = Join-Path -Path $BoxDrivePath -ChildPath $BackupFolderName
$RetryCount = 3
$RetryDelay = 30 # seconds

# Create destination folder
New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null

# Initialize logging
Start-Transcript -Path "$env:TEMP\BoxBackupLog_$(Get-Date -Format 'yyyyMMddHHmmss').txt"

try {
    # Get all source files with progress display
    $allFiles = Get-ChildItem -Path $SourcePath -Recurse -File
    $totalFiles = $allFiles.Count
    $currentFile = 0

    foreach ($file in $allFiles) {
        $currentFile++
        $relativePath = $file.FullName.Substring($SourcePath.Length)
        $destFile = Join-Path -Path $DestinationPath -ChildPath $relativePath
        $destDir = [System.IO.Path]::GetDirectoryName($destFile)

        # Create target directory structure
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        # Copy with retry logic
        $retry = 0
        while ($retry -le $RetryCount) {
            try {
                Write-Progress -Activity "Backing Up Files" -Status "$currentFile/$totalFiles :: $($file.Name)" -PercentComplete ($currentFile/$totalFiles*100)
                
                # Calculate source hash
                $sourceHash = Get-FileHash -Path $file.FullName -Algorithm SHA256
                
                # Perform copy
                Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
                
                # Verify destination hash
                $destHash = Get-FileHash -Path $destFile -Algorithm SHA256
                
                if ($sourceHash.Hash -ne $destHash.Hash) {
                    throw "Hash mismatch detected for $($file.Name)"
                }
                
                Write-Host "Successfully copied: $($file.FullName)" -ForegroundColor Green
                break
            }
            catch {
                if ($retry -eq $RetryCount) {
                    Write-Warning "Final copy attempt failed for $($file.Name): $_"
                    throw
                }
                Write-Warning "Attempt $($retry+1)/$RetryCount failed for $($file.Name): $_"
                Start-Sleep -Seconds $RetryDelay
                $retry++
            }
        }
    }
}
catch {
    Write-Error "Backup failed with error: $_"
    throw
}
finally {
    Write-Progress -Activity "Backing Up Files" -Completed
    Stop-Transcript
}

Write-Host "Backup completed successfully to: $DestinationPath" -ForegroundColor Green
