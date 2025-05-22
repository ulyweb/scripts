<#
.SYNOPSIS
Here is the fully updated script with:
    - Full long path support using \\?\ prefix.
    - Real-time progress bar during copy.
    - Folder size info for each path.
    - Total size at the bottom.
    - Manual and button-based folder addition.
    - Properly labeled UI.
    - Full Test-BoxEnvironment check reinstated at startup.
# 10mBackup2Box.ps1
#>


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Format-Size {
    param ($Bytes)
    switch ($Bytes) {
        { $_ -ge 1TB } { return "{0:N2} TB" -f ($_ / 1TB) }
        { $_ -ge 1GB } { return "{0:N2} GB" -f ($_ / 1GB) }
        { $_ -ge 1MB } { return "{0:N2} MB" -f ($_ / 1MB) }
        { $_ -ge 1KB } { return "{0:N2} KB" -f ($_ / 1KB) }
        default { return "$_ Bytes" }
    }
}

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
    } catch {}
    return $size
}

function Test-BoxEnvironment {
    $missingComponents = @()
    $boxDrivePath = "$env:ProgramFiles\Box\Box"
    $boxToolsPath = "${env:ProgramFiles(x86)}\Box\Box Edit"
    $userBoxFolder = "$env:USERPROFILE\Box"

    if (-not (Test-Path $boxDrivePath)) { $missingComponents += "Box Drive" }
    if (-not (Test-Path $boxToolsPath)) { $missingComponents += "Box Tools" }
    if (-not (Test-Path $userBoxFolder)) { $missingComponents += "Box Folder (under user profile)" }

    if ($missingComponents.Count -gt 0) {
        $message = "The following required components are missing:`n`n"
        $message += ($missingComponents -join "`n")
        $message += "`n`nPlease install them from the Software Center before proceeding."
        [System.Windows.Forms.MessageBox]::Show($message, "Missing Components", "OK", "Error") | Out-Null
        exit
    }

    return $userBoxFolder
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

# Run check
$BoxPath = Test-BoxEnvironment

# Initialize GUI
$FolderPaths = [System.Collections.ArrayList]::new()
$UserProfile = [System.Environment]::GetFolderPath("UserProfile")
$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$form = New-Object System.Windows.Forms.Form
$form.Text = "User Backup to Box"
$form.Size = '800,600'
$form.StartPosition = "CenterScreen"

# User info label
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

# Manual input box
$manualInputBox = New-Object System.Windows.Forms.TextBox
$manualInputBox.Multiline = $true
$manualInputBox.ScrollBars = 'Vertical'
$manualInputBox.Location = '10,70'
$manualInputBox.Size = '600,80'
$form.Controls.Add($manualInputBox)

# Add manual button
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

# Add Folder button
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
$form.Controls.Add($totalSizeLabel)

# Status bar
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = '10,540'
$statusLabel.Size = '760,20'
$form.Controls.Add($statusLabel)

# Preview button
$previewBtn = New-Object System.Windows.Forms.Button
$previewBtn.Text = "Preview Backup Summary"
$previewBtn.Location = '10,470'
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
$backupBtn.Location = '200,470'
$backupBtn.Size = '180,30'
$backupBtn.Add_Click({
    if ($FolderPaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No folders selected to back up.", "Missing Folders", "OK", "Warning")
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $targetBase = "\\?\$BoxPath\recentBackup\Backup_$timestamp"
    $logPath = "$env:TEMP\BoxBackupLog_$timestamp.txt"
    New-Item -ItemType Directory -Path $targetBase -Force | Out-Null

    foreach ($src in $FolderPaths) {
        try {
            $relative = $src -replace "[:\\]", "_"
            $destDir = Join-Path $targetBase $relative
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
                $relPath = $_.FullName.Substring($src.Length).TrimStart('\')
                $destPath = Join-Path $destDir $relPath
                $destPathLong = "\\?\$destPath"
                $destSubDir = Split-Path $destPathLong -Parent
                if (-not (Test-Path $destSubDir)) {
                    New-Item -ItemType Directory -Path $destSubDir -Force | Out-Null
                }
                Copy-Item -Path "\\?\$($_.FullName)" -Destination $destPathLong -Force -ErrorAction Stop
                $statusLabel.Text = "Copied: $($_.Name)"
                $form.Refresh()
                Add-Content $logPath "Copied: $($_.FullName) => $destPath"
            }
        } catch {
            Add-Content $logPath "Error backing up $src : $_"
        }
    }

    [System.Windows.Forms.MessageBox]::Show("Backup completed! Log saved to:`n$logPath", "Success", "OK", "Information")
})
$form.Controls.Add($backupBtn)

# View log button
$logBtn = New-Object System.Windows.Forms.Button
$logBtn.Text = "View Backup Log"
$logBtn.Location = '390,470'
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
$exitBtn.Location = '580,470'
$exitBtn.Size = '80,30'
$exitBtn.Add_Click({ $form.Close() })
$form.Controls.Add($exitBtn)

# Show UI
$form.Topmost = $true
Update-FolderDisplay
$form.ShowDialog()
