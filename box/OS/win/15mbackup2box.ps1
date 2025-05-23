#Requires -Version 5.1
#Requires -RunAsAdministrator # Ensures the script attempts to run as admin for registry/reboot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Prerequisite Check and Configuration ---
function Test-LongPathSupport {
    try {
        $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
        if ($regValue -and $regValue.LongPathsEnabled -eq 1) {
            return $true
        }
    } catch {
        # Key or property might not exist, which means it's not enabled
    }
    return $false
}

function Enable-LongPathSupportRegistry {
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Type DWord -Force -ErrorAction Stop
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to enable Long Path Support in the registry. Error: $($_.Exception.Message)`nPlease ensure you are running the script as an Administrator.", "Registry Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }
}

function Check-AndEnforceLongPathSupport {
    # Check if running as Administrator
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $message = "This script needs to run as an Administrator to check and enable Long Path Support, which may require a system reboot.`n`nPlease re-run the script as an Administrator."
        [System.Windows.Forms.MessageBox]::Show($message, "Administrator Privileges Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Exclamation) | Out-Null
        
        # Attempt to elevate
        try {
            $arguments = "& '" + $myinvocation.mycommand.definition + "'"
            Start-Process powershell -Verb RunAs -ArgumentList $arguments -ErrorAction Stop
        } catch {
             [System.Windows.Forms.MessageBox]::Show("Failed to automatically elevate to Administrator. Please right-click the script and 'Run as administrator'.`n`nScript will now exit.", "Elevation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        exit # Exit current non-admin instance
    }

    if (-not (Test-LongPathSupport)) {
        $title = "Long Path Support Required"
        $text = "This backup script requires 'Win32 Long Path Support' to be enabled in Windows to ensure all files can be backed up correctly.`n`nThis feature is currently NOT enabled on your system.`n`nWe can attempt to enable it now. This involves a change to the system registry and will require an IMMEDIATE SYSTEM REBOOT.`n`nIMPORTANT: Please SAVE ALL YOUR WORK and CLOSE ALL APPLICATIONS before proceeding.`n`nDo you want to enable Long Path Support and reboot your computer now?"
        
        $result = [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            if (Enable-LongPathSupportRegistry) {
                $rebootMsg = "Long Path Support has been successfully enabled in the registry.`n`nThe system MUST now be rebooted for the change to take effect.`n`nClick 'OK' to reboot your computer immediately. Click 'Cancel' to manually reboot later (the script will exit)."
                $rebootConfirmResult = [System.Windows.Forms.MessageBox]::Show($rebootMsg, "Reboot Required", [System.Windows.Forms.MessageBoxButtons]::OKCancel, [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($rebootConfirmResult -eq [System.Windows.Forms.DialogResult]::OK) {
                    Restart-Computer -Force
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Reboot cancelled by user. Please reboot your computer manually for the Long Path Support to take effect.`nScript will now exit.", "Manual Reboot Needed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Could not enable Long Path Support. The script cannot continue reliably and will now exit.", "Operation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            exit # Exit script after attempting to enable or if user cancels reboot
        } else {
            [System.Windows.Forms.MessageBox]::Show("You chose not to enable Long Path Support. The script cannot continue reliably and will now exit.", "Action Cancelled", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            exit # Exit script if user cancels
        }
    } else {
        Write-Host "Long Path Support is already enabled." # This can be shown in console if script is run from there
    }
}

# Call the check at the very beginning
Check-AndEnforceLongPathSupport

# --- Helper Functions (Existing) ---
function Get-FolderSize {
    param (
        [string]$Path
    )
    $size = 0
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue 
        foreach ($item in $items) {
            if (-not $item.PSIsContainer) {
                $size += $item.Length
            }
        }
    } catch {
        Write-Warning "Unable to accurately get size for '$Path'. Error: $($_.Exception.Message)"
    }
    return $size
}

function Format-Size {
    param (
        [double]$Bytes 
    )
    switch ($Bytes) {
        { $_ -ge 1TB } { "{0:N2} TB" -f ($_ / 1TB); break }
        { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break }
        { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break }
        { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break }
        default { "$([Math]::Round($Bytes, 0)) Bytes" } 
    }
}

function Sanitize-FolderName {
    param([string]$FullPath)
    $name = $FullPath -replace '^\\\\[^\\]+\\', '' 
    $name = $name -replace '[:*?<>|"\\]', '_'    
    $name = $name -replace '__+', '_'             
    return $name.Trim('_')
}

function Test-BoxEnvironment {
    $missingComponents = [System.Collections.ArrayList]::new()
    $boxDrivePath = Join-Path $env:ProgramFiles "Box\Box"
    $boxToolsPathX86 = Join-Path ${env:ProgramFiles(x86)} "Box\Box Edit"
    $boxToolsPath = Join-Path $env:ProgramFiles "Box\Box Edit" 
    
    $userBoxFolder = Join-Path $env:USERPROFILE "Box"

    if (-not (Test-Path $boxDrivePath)) {
        [void]$missingComponents.Add("Box Drive (expected at $boxDrivePath)")
    }
    if (-not ((Test-Path $boxToolsPathX86) -or (Test-Path $boxToolsPath))) {
        [void]$missingComponents.Add("Box Tools (expected at $boxToolsPathX86 or $boxToolsPath)")
    }
    if (-not (Test-Path $userBoxFolder)) {
        [void]$missingComponents.Add("User's Box Folder (expected at $userBoxFolder)")
    }

    if ($missingComponents.Count -gt 0) {
        $message = "The following required Box components appear to be missing or not in expected locations:`n`n"
        $message += ($missingComponents -join "`n")
        $message += "`n`nPlease ensure Box Drive and Box Tools are installed and configured correctly."
        $message += "`nThis script primarily backs up to the local Box sync folder."
        [System.Windows.Forms.MessageBox]::Show($message, "Box Environment Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

# --- Global Variables & Initial Setup ---
Test-BoxEnvironment # Run the Box environment check

$FolderPaths = [System.Collections.ArrayList]::new()
$UserProfile = [System.Environment]::GetFolderPath("UserProfile")
$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$BoxSyncBasePath = Join-Path $UserProfile "Box" 
$BoxBackupTargetFolder = "01. My Personal Folder\Computer Backups" 

# --- Form Creation ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "User Backup to Local Box Folder (using Robocopy)"
$form.Size = New-Object System.Drawing.Size(820, 650) 
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog 
$form.MaximizeBox = $false

# --- UI Elements ---
$userLabel = New-Object System.Windows.Forms.Label
$userLabel.Text = "Logged in as: $UserName ($UserProfile)"
$userLabel.Location = New-Object System.Drawing.Point(10, 10)
$userLabel.Size = New-Object System.Drawing.Size(780, 20)
$form.Controls.Add($userLabel)

$instLabel = New-Object System.Windows.Forms.Label
$instLabel.Text = "Step 1: Add folders to back up. Paths longer than 260 characters are supported by Robocopy."
$instLabel.Location = New-Object System.Drawing.Point(10, 35)
$instLabel.Size = New-Object System.Drawing.Size(780, 20)
$form.Controls.Add($instLabel)

$manualInputBox = New-Object System.Windows.Forms.TextBox
$manualInputBox.Multiline = $true
$manualInputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$manualInputBox.Location = New-Object System.Drawing.Point(10, 60)
$manualInputBox.Size = New-Object System.Drawing.Size(600, 80)
$manualInputBox.AcceptsReturn = $true
$form.Controls.Add($manualInputBox)

$addManualBtn = New-Object System.Windows.Forms.Button
$addManualBtn.Text = "Add Manual Path(s)"
$addManualBtn.Location = New-Object System.Drawing.Point(620, 60)
$addManualBtn.Size = New-Object System.Drawing.Size(170, 30)
$form.Controls.Add($addManualBtn)

$addBtn = New-Object System.Windows.Forms.Button
$addBtn.Text = "Add Folder (Browse)"
$addBtn.Location = New-Object System.Drawing.Point(620, 100)
$addBtn.Size = New-Object System.Drawing.Size(170, 30)
$form.Controls.Add($addBtn)

$folderListBox = New-Object System.Windows.Forms.ListBox
$folderListBox.Location = New-Object System.Drawing.Point(10, 150)
$folderListBox.Size = New-Object System.Drawing.Size(600, 280)
$folderListBox.HorizontalScrollbar = $true
$form.Controls.Add($folderListBox)

$removeBtn = New-Object System.Windows.Forms.Button
$removeBtn.Text = "Remove Selected Folder"
$removeBtn.Location = New-Object System.Drawing.Point(620, 150)
$removeBtn.Size = New-Object System.Drawing.Size(170, 30)
$form.Controls.Add($removeBtn)

$totalSizeLabel = New-Object System.Windows.Forms.Label
$totalSizeLabel.Location = New-Object System.Drawing.Point(10, 440)
$totalSizeLabel.Size = New-Object System.Drawing.Size(600, 20)
$totalSizeLabel.Text = "Total estimated size of selected folders: 0 Bytes"
$form.Controls.Add($totalSizeLabel)

$previewBtn = New-Object System.Windows.Forms.Button
$previewBtn.Text = "Preview Backup Summary"
$previewBtn.Location = New-Object System.Drawing.Point(10, 470)
$previewBtn.Size = New-Object System.Drawing.Size(180, 30)
$form.Controls.Add($previewBtn)

$backupBtn = New-Object System.Windows.Forms.Button
$backupBtn.Text = "Start Backup to Box Folder"
$backupBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$backupBtn.Location = New-Object System.Drawing.Point(200, 470)
$backupBtn.Size = New-Object System.Drawing.Size(220, 30) 
$form.Controls.Add($backupBtn)

$logBtn = New-Object System.Windows.Forms.Button
$logBtn.Text = "View Latest Backup Log"
$logBtn.Location = New-Object System.Drawing.Point(430, 470)
$logBtn.Size = New-Object System.Drawing.Size(180, 30)
$form.Controls.Add($logBtn)

$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = "Exit"
$exitBtn.Location = New-Object System.Drawing.Point(620, 470)
$exitBtn.Size = New-Object System.Drawing.Size(170, 30)
$form.Controls.Add($exitBtn)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel "Ready"
$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

# --- UI Event Handlers ---
function Update-FolderDisplayAndSize {
    $folderListBox.BeginUpdate()
    $folderListBox.Items.Clear()
    $Global:TotalBackupSize = 0 
    
    foreach ($path in $FolderPaths) {
        $statusLabel.Text = "Calculating size for $path..."
        $form.Update() 
        $size = Get-FolderSize -Path $path
        $Global:TotalBackupSize += $size
        $folderListBox.Items.Add("$path (`Est. Size: $(Format-Size $size)`)")
    }
    $totalSizeLabel.Text = "Total estimated size of all folders: $(Format-Size $Global:TotalBackupSize)"
    $statusLabel.Text = "Ready. Select folders or start backup."
    $folderListBox.EndUpdate()
    $form.Update()
}

$addManualBtn.Add_Click({
    $manualInputBox.Lines | ForEach-Object {
        $trimmedPath = $_.Trim()
        if (-not ([string]::IsNullOrWhiteSpace($trimmedPath))) {
            if (Test-Path $trimmedPath -PathType Container) {
                if (-not $FolderPaths.Contains($trimmedPath)) {
                    [void]$FolderPaths.Add($trimmedPath)
                    $statusLabel.Text = "Added: $trimmedPath"
                } else {
                    $statusLabel.Text = "Already in list: $trimmedPath"
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Path not found or not a folder: $trimmedPath", "Invalid Path", "OK", "Warning") | Out-Null
            }
        }
    }
    $manualInputBox.Clear()
    Update-FolderDisplayAndSize
})

$folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowserDialog.Description = "Select a folder to back up"
$folderBrowserDialog.ShowNewFolderButton = $false
$addBtn.Add_Click({
    if ($folderBrowserDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedPath = $folderBrowserDialog.SelectedPath
        if (-not $FolderPaths.Contains($selectedPath)) {
            [void]$FolderPaths.Add($selectedPath)
            $statusLabel.Text = "Added: $selectedPath"
            Update-FolderDisplayAndSize
        } else {
            $statusLabel.Text = "Already in list: $selectedPath"
        }
    }
})

$removeBtn.Add_Click({
    if ($folderListBox.SelectedIndex -ge 0) {
        $selectedItemText = $folderListBox.SelectedItem.ToString()
        $pathToRemove = ($selectedItemText -split '\s\(`Est\. Size:')[0]
        if ($FolderPaths.Contains($pathToRemove)) {
            [void]$FolderPaths.Remove($pathToRemove)
            $statusLabel.Text = "Removed: $pathToRemove"
            Update-FolderDisplayAndSize
        }
    } else {
        $statusLabel.Text = "No folder selected to remove."
    }
})

$previewBtn.Add_Click({
    if ($FolderPaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No folders selected to preview.", "Empty List", "OK", "Information") | Out-Null
        return
    }
    $msg = "Backup Summary:`n`n"
    foreach ($path in $FolderPaths) {
        $size = Get-FolderSize -Path $path
        $msg += "$path`n  Est. Size: $(Format-Size $size)`n`n"
    }
    $msg += "$($totalSizeLabel.Text)`n`n"
    $msg += "Destination Base: $(Join-Path $BoxSyncBasePath $BoxBackupTargetFolder)"
    [System.Windows.Forms.MessageBox]::Show($form, $msg, "Backup Preview", "OK", "Information") | Out-Null
})

$backupBtn.Add_Click({
    if ($FolderPaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($form, "No folders selected to back up.", "Missing Folders", "OK", "Warning") | Out-Null
        return
    }

    $confirmation = [System.Windows.Forms.MessageBox]::Show($form, "This will back up the selected folders to your local Box sync folder. Robocopy will be used.`nDestination base: `n$(Join-Path $BoxSyncBasePath $BoxBackupTargetFolder)`n`nProceed with backup?", "Confirm Backup", "YesNo", "Question")
    if ($confirmation -ne "Yes") {
        $statusLabel.Text = "Backup cancelled by user."
        return
    }

    $backupBtn.Enabled = $false
    $addBtn.Enabled = $false
    $addManualBtn.Enabled = $false
    $removeBtn.Enabled = $false
    $previewBtn.Enabled = $false
    $backupBtn.Text = "Backup in Progress..."
    $form.Update()

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss" 
    $backupSessionFolderName = "Backup_$timestamp"
    $targetBackupSessionPath = Join-Path $BoxSyncBasePath $BoxBackupTargetFolder $backupSessionFolderName
    
    $mainLogDir = Join-Path $env:TEMP "UserBoxBackupLogs"
    if (-not (Test-Path $mainLogDir)) { New-Item -ItemType Directory -Path $mainLogDir -Force | Out-Null }
    $mainLogFile = Join-Path $mainLogDir "BackupSessionSummary_$timestamp.log"

    "Backup session started at $(Get-Date)" | Out-File -FilePath $mainLogFile -Append
    "Target Box sync path for this session: $targetBackupSessionPath" | Out-File -FilePath $mainLogFile -Append
    "---" | Out-File -FilePath $mainLogFile -Append

    try {
        if (-not (Test-Path $targetBackupSessionPath)) {
            New-Item -ItemType Directory -Path $targetBackupSessionPath -Force | Out-Null
            "Created session folder: $targetBackupSessionPath" | Out-File -FilePath $mainLogFile -Append
        }
    } catch {
        $errMsg = "CRITICAL ERROR: Could not create base backup session folder: $targetBackupSessionPath. Error: $($_.Exception.Message). Backup aborted."
        $statusLabel.Text = $errMsg
        $errMsg | Out-File -FilePath $mainLogFile -Append
        [System.Windows.Forms.MessageBox]::Show($form, $errMsg, "Backup Error", "OK", "Error") | Out-Null
        $backupBtn.Enabled = $true; $addBtn.Enabled = $true; $addManualBtn.Enabled = $true; $removeBtn.Enabled = $true; $previewBtn.Enabled = $true
        $backupBtn.Text = "Start Backup to Box Folder"
        return
    }
    
    $overallSuccess = $true

    foreach ($srcPath in $FolderPaths) {
        $sanitizedSrcFolderName = Sanitize-FolderName -FullPath $srcPath
        $destinationForThisSource = Join-Path $targetBackupSessionPath $sanitizedSrcFolderName
        $robocopyLogFile = Join-Path $mainLogDir "Robocopy_$(Sanitize-FolderName -FullPath $srcPath)_$timestamp.log"

        $statusLabel.Text = "Backing up $srcPath using Robocopy..."
        "Processing Source: $srcPath" | Out-File -FilePath $mainLogFile -Append
        "  Targeting: $destinationForThisSource" | Out-File -FilePath $mainLogFile -Append
        "  Robocopy Log: $robocopyLogFile" | Out-File -FilePath $mainLogFile -Append
        $form.Update() 

        try {
            if (-not (Test-Path $destinationForThisSource)) {
                New-Item -ItemType Directory -Path $destinationForThisSource -Force -ErrorAction Stop | Out-Null
            }
        } catch {
            $errMsg = "ERROR: Could not create destination subfolder: $destinationForThisSource. Error: $($_.Exception.Message). Skipping this source."
            $statusLabel.Text = "Error creating destination for $srcPath. See log."
            $errMsg | Out-File -FilePath $mainLogFile -Append
            $overallSuccess = $false
            continue 
        }

        $robocopyArgs = @(
            "`"$srcPath`"", 
            "`"$destinationForThisSource`"", 
            "/E", "/ZB", "/COPY:DATSOU",
            "/R:2", "/W:5", "/MT:8",
            "/NP", "/NFL", "/NDL", "/NJH", "/NJS",
            "/LOG+:`"$robocopyLogFile`"" 
        )

        try {
            $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
            $exitCode = $process.ExitCode

            "  Robocopy for '$srcPath' completed. Exit Code: $exitCode" | Out-File -FilePath $mainLogFile -Append
            
            if ($exitCode -ge 8) { 
                "  ERROR: Robocopy reported errors for '$srcPath'. Check Robocopy log: $robocopyLogFile" | Out-File -FilePath $mainLogFile -Append
                $statusLabel.Text = "Error during Robocopy for $srcPath. Check logs."
                $overallSuccess = $false
            } elseif ($exitCode -ge 1 -and $exitCode -lt 8) { 
                "  Robocopy completed with warnings/info for '$srcPath' (e.g., files copied, extra files). Check log: $robocopyLogFile" | Out-File -FilePath $mainLogFile -Append
            } else { 
                 "  Robocopy completed successfully for '$srcPath'. No files needed copying or no changes." | Out-File -FilePath $mainLogFile -Append
            }
        } catch {
            $errMsg = "  CRITICAL ERROR executing Robocopy for '$srcPath'. Error: $($_.Exception.Message)"
            $errMsg | Out-File -FilePath $mainLogFile -Append
            $statusLabel.Text = "Robocopy execution failed for $srcPath. Check logs."
            $overallSuccess = $false
        }
        "---" | Out-File -FilePath $mainLogFile -Append
    } 

    $backupBtn.Enabled = $true
    $addBtn.Enabled = $true
    $addManualBtn.Enabled = $true
    $removeBtn.Enabled = $true
    $previewBtn.Enabled = $true
    $backupBtn.Text = "Start Backup to Box Folder"
    $form.Update()

    $finalMessage = "Backup process finished."
    if ($overallSuccess) {
        $finalMessage += " All selected sources processed. Some operations may have had warnings."
        $statusLabel.Text = "Backup finished. Check logs for details."
        [System.Windows.Forms.MessageBox]::Show($form, "$finalMessage`n`nOverall session log: $mainLogFile`nIndividual Robocopy logs are in: $mainLogDir", "Backup Complete", "OK", "Information") | Out-Null
    } else {
        $finalMessage += " One or more sources encountered errors."
        $statusLabel.Text = "Backup finished with errors. Please review logs."
        [System.Windows.Forms.MessageBox]::Show($form, "$finalMessage`n`nOverall session log: $mainLogFile`nIndividual Robocopy logs are in: $mainLogDir`n`nPlease review the logs for details on failures.", "Backup Completed with Errors", "OK", "Warning") | Out-Null
    }
    "$finalMessage. Session ended at $(Get-Date)" | Out-File -FilePath $mainLogFile -Append
})

$logBtn.Add_Click({
    $logDir = Join-Path $env:TEMP "UserBoxBackupLogs"
    if (-not (Test-Path $logDir)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Log directory not found: $logDir", "No Logs", "OK", "Information") | Out-Null
        return
    }
    $latestSessionLog = Get-ChildItem -Path $logDir -Filter "BackupSessionSummary_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestSessionLog) {
        $result = [System.Windows.Forms.MessageBox]::Show($form, "Open the latest session summary log file?`n($($latestSessionLog.Name))`n`n(Click No to open the log directory)", "View Logs", "YesNoCancel", "Question")
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Invoke-Item $latestSessionLog.FullName
        } elseif ($result -eq [System.Windows.Forms.DialogResult]::No) {
            Invoke-Item $logDir
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show($form, "No session summary logs found. Opening log directory: $logDir", "Log Directory", "OK", "Information") | Out-Null
        Invoke-Item $logDir
    }
})

$exitBtn.Add_Click({
    $form.Close()
})

$form.Add_FormClosing({
    Write-Verbose "Exiting backup application."
})

# --- Show Form ---
$form.Topmost = $true 
# The initial Write-Host messages about manually enabling long path support are no longer needed here
# as the script handles it or exits if not possible/declined.
Write-Host "Launching User Backup to Box GUI..." # This is fine if run from console.
$statusLabel.Text = "Ready. Add folders to back up."
[void]$form.ShowDialog()

# --- Script End ---
