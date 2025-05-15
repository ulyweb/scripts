Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Box Folder Backup Tool"
$form.Size = New-Object System.Drawing.Size(600, 300)
$form.StartPosition = "CenterScreen"

# Source paths label
$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Text = "Source Folder(s) (separate with semicolons):"
$lblSource.AutoSize = $true
$lblSource.Location = New-Object System.Drawing.Point(10, 20)
$form.Controls.Add($lblSource)

# Source paths textbox
$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Size = New-Object System.Drawing.Size(450, 20)
$txtSource.Location = New-Object System.Drawing.Point(10, 45)
$form.Controls.Add($txtSource)

# Browse button
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse"
$btnBrowse.Location = New-Object System.Drawing.Point(470, 43)
$btnBrowse.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($folderBrowser.ShowDialog() -eq "OK") {
        if ($txtSource.Text.Trim()) {
            $txtSource.Text += ";$($folderBrowser.SelectedPath)"
        } else {
            $txtSource.Text = $folderBrowser.SelectedPath
        }
    }
})
$form.Controls.Add($btnBrowse)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 180)
$progressBar.Size = New-Object System.Drawing.Size(550, 20)
$form.Controls.Add($progressBar)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Waiting for user input..."
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(10, 210)
$form.Controls.Add($lblStatus)

# Start backup button
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Backup"
$btnStart.Location = New-Object System.Drawing.Point(10, 85)
$form.Controls.Add($btnStart)

$btnStart.Add_Click({
    $sourceInput = $txtSource.Text
    if ([string]::IsNullOrWhiteSpace($sourceInput)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter at least one source folder.","Input Required",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $SourcePaths = $sourceInput -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $totalSizeBytes = 0
    $allFiles = @()

    foreach ($src in $SourcePaths) {
        if (-not (Test-Path $src)) {
            [System.Windows.Forms.MessageBox]::Show("Folder does not exist: $src","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        $files = Get-ChildItem -Path $src -Recurse -File
        $allFiles += $files
        $totalSizeBytes += ($files | Measure-Object -Property Length -Sum).Sum
    }

    if ($allFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No files found to back up.","Nothing to Do",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $totalSizeFormatted = Convert-Size $totalSizeBytes
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        "Total files: $($allFiles.Count)`nTotal size: $totalSizeFormatted`nProceed with backup?",
        "Confirm Backup",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
        $lblStatus.Text = "Status: Backup canceled by user."
        return
    }

    # Prepare destination
    $CurrentUser = $env:USERNAME
    $BoxDriveRoot = "C:\Users\$CurrentUser\Box\01. My Personal Folder\recentBackup"
    $BackupFolderName = "Backup_$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
    $DestinationPath = Join-Path -Path $BoxDriveRoot -ChildPath $BackupFolderName
    if (-not (Test-Path $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    # Start logging
    $logFile = "$env:TEMP\BoxBackupLog_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    Start-Transcript -Path $logFile

    $progressBar.Value = 0
    $progressBar.Maximum = $allFiles.Count
    $lblStatus.Text = "Status: Backing up files..."

    $i = 0
    foreach ($file in $allFiles) {
        $i++

        $srcBase = $SourcePaths | Where-Object { $file.FullName.ToLower().StartsWith($_.ToLower()) } | Select-Object -First 1
        $relativePath = $file.FullName.Substring($srcBase.Length).TrimStart('\')
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
                $sourceHash = Get-FileHash -Path $file.FullName -Algorithm SHA256
                Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
                $destHash = Get-FileHash -Path $destFile -Algorithm SHA256

                if ($sourceHash.Hash -ne $destHash.Hash) {
                    throw "Hash mismatch for $($file.FullName)"
                }
                $success = $true
            }
            catch {
                $retry++
                if ($retry -gt $maxRetries) {
                    Add-Content $logFile "Failed to copy $($file.FullName): $_"
                    break
                } else {
                    Start-Sleep -Seconds 3
                }
            }
        }

        $progressBar.Value = $i
    }

    Stop-Transcript
    [System.Windows.Forms.MessageBox]::Show("Backup completed to:`n$DestinationPath`nLog file:`n$logFile", "Backup Successful", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    $lblStatus.Text = "Status: Backup complete."
})

$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
