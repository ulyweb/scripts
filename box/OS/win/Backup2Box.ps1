<#
.SYNOPSIS
📝 How to Use This Script
Save the script as Backup2Box.ps1.
Launch it by right-clicking → Run with PowerShell, or run it directly in pwsh or powershell.
Step 1: You can either:
Use "Add Folder" to pick one folder at a time.
Paste paths into the multiline box and click "Add Manual Path(s)".
Use "Remove Selected Folder" to remove.
Click "Preview Backup Summary" to view each folder’s size and total.
Click "Start Backup" to perform the backup.
Click "View Backup Log" to open the log.
Click "Exit" to close.

✅ Shows the current user's profile path and name at the top.
✅ Displays the size of each selected folder.
✅ Shows the combined total size at the bottom.
✅ Keeps all previous functionality: adding/removing folders, preview, backup, logging, exit.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-FolderSize {
    param ($Path)
    $size = 0
    try {
        $items = Get-ChildItem -Path $Path -Recurse -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if (-not $item.PSIsContainer) {
                $size += $item.Length
            }
        }
    } catch {
        Write-Warning "Unable to get size for $Path"
    }
    return $size
}

function Format-Size {
    param ($Bytes)
    switch ($Bytes) {
        { $_ -ge 1TB } { "{0:N2} TB" -f ($_ / 1TB); break }
        { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
        { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
        { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
        default { "$_ Bytes" }
    }
}

function Update-FolderDisplay {
    $folderListBox.Items.Clear()
    $TotalSize = 0
    foreach ($path in $FolderPaths) {
        $size = Get-FolderSize -Path $path
        $TotalSize += $size
        $folderListBox.Items.Add("$path (`Size: $(Format-Size $size)`)")
    }
    $totalSizeLabel.Text = "Total size of all folders: $(Format-Size $TotalSize)"
}

# Initial Data
$FolderPaths = [System.Collections.ArrayList]::new()
$UserProfile = [System.Environment]::GetFolderPath("UserProfile")
$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$BoxPath = Join-Path $UserProfile "Box\01. My Personal Folder"

# Check Box Drive
if (-not (Test-Path $BoxPath)) {
    [System.Windows.Forms.MessageBox]::Show("Box Drive or required folders not found at: $BoxPath`n`nPlease ensure Box Drive and Box Tools are installed before proceeding.", "Box Not Found", "OK", "Error")
    return
}

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "User Backup to Box"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

# Header label with user info
$userLabel = New-Object System.Windows.Forms.Label
$userLabel.Text = "Logged in as: $UserName ($UserProfile)"
$userLabel.Location = '10,10'
$userLabel.Size = '760,20'
$form.Controls.Add($userLabel)

# Instruction label
$instLabel = New-Object System.Windows.Forms.Label
$instLabel.Text = "Step 1: Add folders to back up (select using Add Folder or enter paths manually below)"
$instLabel.Location = '10,40'
$instLabel.Size = '760,20'
$form.Controls.Add($instLabel)

# Manual path input box
$manualInputBox = New-Object System.Windows.Forms.TextBox
$manualInputBox.Multiline = $true
$manualInputBox.ScrollBars = 'Vertical'
$manualInputBox.Location = '10,70'
$manualInputBox.Size = '600,80'
$form.Controls.Add($manualInputBox)

# Add from textbox button
$addManualBtn = New-Object System.Windows.Forms.Button
$addManualBtn.Text = "Add Manual Path(s)"
$addManualBtn.Location = '620,70'
$addManualBtn.Size = '150,30'
$addManualBtn.Add_Click({
    $lines = $manualInputBox.Lines | Where-Object { $_ -and (Test-Path $_) }
    foreach ($line in $lines) {
        if (-not $FolderPaths.Contains($line)) {
            [void]$FolderPaths.Add($line)
        }
    }
    Update-FolderDisplay
})
$form.Controls.Add($addManualBtn)

# Add folder dialog
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$addBtn = New-Object System.Windows.Forms.Button
$addBtn.Text = "Add Folder"
$addBtn.Location = '620,110'
$addBtn.Size = '150,30'
$addBtn.Add_Click({
    if ($folderBrowser.ShowDialog() -eq "OK") {
        if (-not $FolderPaths.Contains($folderBrowser.SelectedPath)) {
            [void]$FolderPaths.Add($folderBrowser.SelectedPath)
            Update-FolderDisplay
        }
    }
})
$form.Controls.Add($addBtn)

# Folder list display
$folderListBox = New-Object System.Windows.Forms.ListBox
$folderListBox.Location = '10,160'
$folderListBox.Size = '600,250'
$form.Controls.Add($folderListBox)

# Remove folder button
$removeBtn = New-Object System.Windows.Forms.Button
$removeBtn.Text = "Remove Selected Folder"
$removeBtn.Location = '620,160'
$removeBtn.Size = '150,30'
$removeBtn.Add_Click({
    if ($folderListBox.SelectedIndex -ge 0) {
        $selected = $FolderPaths[$folderListBox.SelectedIndex]
        $FolderPaths.Remove($selected)
        Update-FolderDisplay
    }
})
$form.Controls.Add($removeBtn)

# Total size label
$totalSizeLabel = New-Object System.Windows.Forms.Label
$totalSizeLabel.Location = '10,420'
$totalSizeLabel.Size = '600,20'
$totalSizeLabel.Text = "Total size of all folders: 0 Bytes"
$form.Controls.Add($totalSizeLabel)

# Preview button
$previewBtn = New-Object System.Windows.Forms.Button
$previewBtn.Text = "Preview Backup Summary"
$previewBtn.Location = '10,450'
$previewBtn.Size = '180,30'
$previewBtn.Add_Click({
    $msg = ""
    foreach ($path in $FolderPaths) {
        $size = Get-FolderSize -Path $path
        $msg += "$path`n  Size: $(Format-Size $size)`n`n"
    }
    $msg += $totalSizeLabel.Text
    [System.Windows.Forms.MessageBox]::Show($msg, "Backup Preview", "OK", "Information")
})
$form.Controls.Add($previewBtn)

# Backup button
$backupBtn = New-Object System.Windows.Forms.Button
$backupBtn.Text = "Start Backup"
$backupBtn.Location = '200,450'
$backupBtn.Size = '180,30'
$backupBtn.Add_Click({
    if ($FolderPaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No folders selected to back up.", "Missing Folders", "OK", "Warning")
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $targetBase = Join-Path $BoxPath "recentBackup\Backup_$timestamp"
    $logPath = Join-Path $env:TEMP "BoxBackupLog_$timestamp.txt"

    foreach ($src in $FolderPaths) {
        try {
            $relative = $src -replace "[:\\]", "_"
            $destDir = Join-Path $targetBase $relative
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
                $relPath = $_.FullName.Substring($src.Length)
                $destPath = Join-Path $destDir $relPath
                $destSubDir = Split-Path $destPath -Parent
                if (-not (Test-Path $destSubDir)) {
                    New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $destPath -Force
                Add-Content $logPath "Copied: $($_.FullName) => $destPath"
            }
        } catch {
            Add-Content $logPath "Error backing up $src : $_"
        }
    }

    [System.Windows.Forms.MessageBox]::Show("Backup completed! Log saved to:`n$logPath", "Success", "OK", "Information")
})
$form.Controls.Add($backupBtn)

# Log button
$logBtn = New-Object System.Windows.Forms.Button
$logBtn.Text = "View Backup Log"
$logBtn.Location = '390,450'
$logBtn.Size = '180,30'
$logBtn.Add_Click({
    $latestLog = Get-ChildItem "$env:TEMP\BoxBackupLog_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        notepad $latestLog.FullName
    } else {
        [System.Windows.Forms.MessageBox]::Show("No log file found.", "Error", "OK", "Error")
    }
})
$form.Controls.Add($logBtn)

# Exit button
$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = "Exit"
$exitBtn.Location = '580,450'
$exitBtn.Size = '80,30'
$exitBtn.Add_Click({ $form.Close() })
$form.Controls.Add($exitBtn)

# Show form
$form.Topmost = $true
[void]$form.ShowDialog()
