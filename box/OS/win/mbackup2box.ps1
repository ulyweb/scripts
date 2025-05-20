Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global log path
$global:backupLogPath = $null

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Backup to Box"
$form.Size = New-Object System.Drawing.Size(620, 420)
$form.StartPosition = "CenterScreen"

# Instructions label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Click 'Add Folder' to select folders you want to back up:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($label)

# ListBox - selected folders
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(20, 50)
$listBox.Size = New-Object System.Drawing.Size(560, 100)
$form.Controls.Add($listBox)

# Add Folder button
$addButton = New-Object System.Windows.Forms.Button
$addButton.Text = "Add Folder"
$addButton.Location = New-Object System.Drawing.Point(20, 160)
$addButton.Size = New-Object System.Drawing.Size(100, 30)
$addButton.Add_Click({
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $fileDialog.ValidateNames = $false
    $fileDialog.CheckFileExists = $false
    $fileDialog.FileName = "Select Folder"
    $fileDialog.Title = "Select any file inside the folder to back up"

    if ($fileDialog.ShowDialog() -eq "OK") {
        $folderPath = Split-Path $fileDialog.FileName
        if (-not ($listBox.Items -contains $folderPath)) {
            $listBox.Items.Add($folderPath) | Out-Null
        }
    }
})
$form.Controls.Add($addButton)

# Remove selected folder button
$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = "Remove Selected"
$removeButton.Location = New-Object System.Drawing.Point(130, 160)
$removeButton.Size = New-Object System.Drawing.Size(120, 30)
$removeButton.Add_Click({
    if ($listBox.SelectedItem) {
        $listBox.Items.Remove($listBox.SelectedItem)
    }
})
$form.Controls.Add($removeButton)

# Preview Selection button
$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "Preview Selection"
$previewButton.Location = New-Object System.Drawing.Point(260, 160)
$previewButton.Size = New-Object System.Drawing.Size(130, 30)
$previewButton.Add_Click({
    if ($listBox.Items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one folder.", "Preview", "OK", "Warning")
        return
    }

    $totalFiles = 0
    $totalSize = 0
    $details = ""

    foreach ($folder in $listBox.Items) {
        $files = Get-ChildItem -Path $folder -Recurse -File -ErrorAction SilentlyContinue
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $count = $files.Count
        $totalFiles += $count
        $totalSize += $size
        $details += "`n$folder`n  - Files: $count`n  - Size: {0:N2} MB`n" -f ($size / 1MB)
    }

    $totalSizeFormatted = if ($totalSize -gt 1GB) {
        "{0:N2} GB" -f ($totalSize / 1GB)
    } else {
        "{0:N2} MB" -f ($totalSize / 1MB)
    }

    $summary = "PREVIEW:`nSelected folders: $($listBox.Items.Count)`nTotal files: $totalFiles`nTotal size: $totalSizeFormatted`n"
    [System.Windows.Forms.MessageBox]::Show($summary + $details, "Preview Summary", "OK", "Information")
})
$form.Controls.Add($previewButton)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 210)
$progressBar.Size = New-Object System.Drawing.Size(560, 25)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 245)
$statusLabel.Size = New-Object System.Drawing.Size(560, 30)
$statusLabel.Text = ""
$form.Controls.Add($statusLabel)

# Backup button
$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "Start Backup"
$backupButton.Location = New-Object System.Drawing.Point(150, 290)
$backupButton.Size = New-Object System.Drawing.Size(120, 35)

$backupButton.Add_Click({
    if ($listBox.Items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one folder.", "Error", "OK", "Error")
        return
    }

    $username = $env:USERNAME
    $boxPath = "C:\Users\$username\Box\01. My Personal Folder\recentBackup"
    if (-not (Test-Path $boxPath)) {
        [System.Windows.Forms.MessageBox]::Show("Box path not found:`n$boxPath", "Error", "OK", "Error")
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $destinationFolder = Join-Path -Path $boxPath -ChildPath "Backup_$timestamp"
    New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null

    $logPath = Join-Path -Path $destinationFolder -ChildPath "Backup_Log.txt"
    $log = @()
    $log += "Backup Run: $([datetime]::Now)"
    $log += "Destination: $destinationFolder`n"

    $allFiles = @()
    foreach ($folderPath in $listBox.Items) {
        $allFiles += Get-ChildItem -Path $folderPath -Recurse -File | ForEach-Object {
            [PSCustomObject]@{
                File = $_
                SourceRoot = $folderPath
            }
        }
    }

    $total = $allFiles.Count
    if ($total -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No files found in selected folders.", "Info", "OK", "Information")
        return
    }

    $progressBar.Value = 0
    $statusLabel.Text = "Copying $total files..."
    $i = 0
    $totalSize = 0

    foreach ($entry in $allFiles) {
        $file = $entry.File
        $sourceRoot = $entry.SourceRoot
        $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $safePath = $relativePath -replace "[:*?<>|]", "_"
        $destPath = Join-Path -Path $destinationFolder -ChildPath $safePath
        $destDir = Split-Path $destPath

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Copy-Item -Path $file.FullName -Destination $destPath -Force
        $log += "Copied: $($file.FullName) -> $destPath"
        $totalSize += $file.Length
        $i++
        $progressBar.Value = [math]::Round(($i / $total) * 100)
        $form.Refresh()
    }

    $log += "`nTotal files copied: $i"
    $log += "Total size: {0:N2} MB" -f ($totalSize / 1MB)

    $log | Out-File -FilePath $logPath -Encoding UTF8
    $global:backupLogPath = $logPath

    $statusLabel.Text = "Backup complete. $i files copied."
    $logButton.Enabled = $true

    [System.Windows.Forms.MessageBox]::Show("Backup completed successfully.`nLog saved to:`n$logPath", "Done", "OK", "Information")
})
$form.Controls.Add($backupButton)

# View Log button
$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "View Log"
$logButton.Location = New-Object System.Drawing.Point(280, 290)
$logButton.Size = New-Object System.Drawing.Size(90, 35)
$logButton.Enabled = $false
$logButton.Add_Click({
    if ($global:backupLogPath -and (Test-Path $global:backupLogPath)) {
        Start-Process notepad.exe $global:backupLogPath
    } else {
        [System.Windows.Forms.MessageBox]::Show("No log available yet.", "Log", "OK", "Information")
    }
})
$form.Controls.Add($logButton)

# Exit button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Location = New-Object System.Drawing.Point(380, 290)
$exitButton.Size = New-Object System.Drawing.Size(80, 35)
$exitButton.Add_Click({ $form.Close() })
$form.Controls.Add($exitButton)

# Show the form
[void]$form.ShowDialog()
