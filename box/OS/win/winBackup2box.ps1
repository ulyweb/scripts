<#
.SYNOPSIS
📝 How to Use This Script
Save the script as WinBackup2Box.ps1.
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

#Requires -Version 5.1
#Requires -RunAsAdministrator # Ensures the script attempts to run as admin for registry/reboot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Script-Scoped Variables for Asynchronous Control ---
$Global:CurrentSourceIndexToProcess = 0
$Global:CurrentRobocopyProcess = $null
$Global:CurrentRobocopyTempOutputFile = $null
$Global:GuiUpdateTimer = $null
$Global:RobocopyOutputBox = $null
$Global:MainLogFileForSession = $null # To store the path of the main session log
$Global:RobocopyPersistentLogFile = $null # To store the path for the current source's persistent log

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
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $message = "This script needs to run as an Administrator to check/enable Long Path Support and for Robocopy backup mode.`n`nPlease re-run the script as an Administrator."
        [System.Windows.Forms.MessageBox]::Show($message, "Administrator Privileges Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Exclamation) | Out-Null
        try {
            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($myinvocation.MyCommand.Definition)`"" # Ensure correct arguments for elevation
            Start-Process powershell -Verb RunAs -ArgumentList $arguments -ErrorAction Stop
        } catch {
             [System.Windows.Forms.MessageBox]::Show("Failed to automatically elevate to Administrator. Please right-click the script and 'Run as administrator'.`n`nScript will now exit.", "Elevation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        exit 
    }

    if (-not (Test-LongPathSupport)) {
        $title = "Long Path Support Required"
        $text = "This backup script requires 'Win32 Long Path Support' to be enabled in Windows to ensure all files can be backed up correctly.`n`nThis feature is currently NOT enabled on your system.`n`nWe can attempt to enable it now. This involves a change to the system registry and will require an IMMEDIATE SYSTEM REBOOT.`n`nIMPORTANT: Please SAVE ALL YOUR WORK and CLOSE ALL APPLICATIONS before proceeding.`n`nDo you want to enable Long Path Support and reboot your computer now?"
        $result = [System.Windows.Forms.MessageBox]::Show($text, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            if (Enable-LongPathSupportRegistry) {
                $rebootMsg = "Long Path Support has been successfully enabled in the registry.`n`nThe system MUST now be rebooted for the change to take effect.`n`nClick 'OK' to reboot your computer immediately. Click 'Cancel' to manually reboot later (the script will exit)."
                $rebootConfirmResult = [System.Windows.Forms.MessageBox]::Show($rebootMsg, "Reboot Required", [System.Windows.Forms.MessageBoxButtons]::OKCancel, [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($rebootConfirmResult -eq [System.Windows.Forms.DialogResult]::OK) { Restart-Computer -Force } 
                else { [System.Windows.Forms.MessageBox]::Show("Reboot cancelled. Please reboot manually.`nScript will exit.", "Manual Reboot Needed", "OK", "Information") | Out-Null }
            } else { [System.Windows.Forms.MessageBox]::Show("Could not enable Long Path Support. Script will exit.", "Operation Failed", "OK", "Error") | Out-Null }
            exit 
        } else { [System.Windows.Forms.MessageBox]::Show("Long Path Support not enabled. Script will exit.", "Action Cancelled", "OK", "Information") | Out-Null; exit }
    } else { Write-Host "Long Path Support is already enabled." }
}

Check-AndEnforceLongPathSupport

# --- Helper Functions ---
function Get-FolderSize { param ([string]$Path) $size = 0; try { $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue; foreach ($item in $items) { if (-not $item.PSIsContainer) { $size += $item.Length } } } catch { Write-Warning "Size for '$Path': $($_.Exception.Message)" }; return $size }
function Format-Size { param ([double]$Bytes) switch ($Bytes) { { $_ -ge 1TB } { "{0:N2} TB" -f ($_ / 1TB); break } { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); break } { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); break } { $_ -ge 1KB } { "{0:N2} KB" -f ($_ / 1KB); break } default { "$([Math]::Round($Bytes, 0)) Bytes" } } }
function Sanitize-FolderName { param([string]$FullPath) $name = $FullPath -replace '^\\\\[^\\]+\\', ''; $name = $name -replace '[:*?<>|"\\]', '_'; $name = $name -replace '__+', '_'; return $name.Trim('_') }

function Test-BoxEnvironment {
    $missingComponents = [System.Collections.ArrayList]::new()
    $boxDrivePath = Join-Path $env:ProgramFiles "Box\Box"; $boxToolsPathX86 = Join-Path ${env:ProgramFiles(x86)} "Box\Box Edit"; $boxToolsPath = Join-Path $env:ProgramFiles "Box\Box Edit"; $userBoxFolder = Join-Path $env:USERPROFILE "Box"
    if (-not (Test-Path $boxDrivePath)) { [void]$missingComponents.Add("Box Drive (expected at $boxDrivePath)") }
    if (-not ((Test-Path $boxToolsPathX86) -or (Test-Path $boxToolsPath))) { [void]$missingComponents.Add("Box Tools (expected at $boxToolsPathX86 or $boxToolsPath)") }
    if (-not (Test-Path $userBoxFolder)) { [void]$missingComponents.Add("User's Box Folder (expected at $userBoxFolder)") }
    if ($missingComponents.Count -gt 0) { $message = "Box components missing/not found:`n`n$($missingComponents -join "`n")`n`nEnsure Box Drive/Tools are installed. This script backs up to the local Box sync folder."; [System.Windows.Forms.MessageBox]::Show($message, "Box Environment Check", "OK", "Warning") | Out-Null }
}

Test-BoxEnvironment

$FolderPaths = [System.Collections.ArrayList]::new()
$UserProfile = [System.Environment]::GetFolderPath("UserProfile"); $UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$BoxSyncBasePath = Join-Path $UserProfile "Box"; $BoxBackupTargetFolder = "01. My Personal Folder\Computer Backups"

# --- Form Creation ---
$form = New-Object System.Windows.Forms.Form; $form.Text = "User Backup to Local Box Folder (Robocopy)"; $form.Size = New-Object System.Drawing.Size(820, 780); $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog; $form.MaximizeBox = $false

# --- UI Elements ---
$userLabel = New-Object System.Windows.Forms.Label; $userLabel.Text = "Logged in as: $UserName ($UserProfile)"; $userLabel.Location = New-Object System.Drawing.Point(10,10); $userLabel.Size = New-Object System.Drawing.Size(780,20); $form.Controls.Add($userLabel)
$instLabel = New-Object System.Windows.Forms.Label; $instLabel.Text = "Step 1: Add folders to back up. Long paths supported."; $instLabel.Location = New-Object System.Drawing.Point(10,35); $instLabel.Size = New-Object System.Drawing.Size(780,20); $form.Controls.Add($instLabel)
$manualInputBox = New-Object System.Windows.Forms.TextBox; $manualInputBox.Multiline = $true; $manualInputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical; $manualInputBox.Location = New-Object System.Drawing.Point(10,60); $manualInputBox.Size = New-Object System.Drawing.Size(600,80); $manualInputBox.AcceptsReturn = $true; $form.Controls.Add($manualInputBox)
$addManualBtn = New-Object System.Windows.Forms.Button; $addManualBtn.Text = "Add Manual Path(s)"; $addManualBtn.Location = New-Object System.Drawing.Point(620,60); $addManualBtn.Size = New-Object System.Drawing.Size(170,30); $form.Controls.Add($addManualBtn)
$addBtn = New-Object System.Windows.Forms.Button; $addBtn.Text = "Add Folder (Browse)"; $addBtn.Location = New-Object System.Drawing.Point(620,100); $addBtn.Size = New-Object System.Drawing.Size(170,30); $form.Controls.Add($addBtn)
$folderListBox = New-Object System.Windows.Forms.ListBox; $folderListBox.Location = New-Object System.Drawing.Point(10,150); $folderListBox.Size = New-Object System.Drawing.Size(600,200); $folderListBox.HorizontalScrollbar = $true; $form.Controls.Add($folderListBox) # Reduced height
$removeBtn = New-Object System.Windows.Forms.Button; $removeBtn.Text = "Remove Selected"; $removeBtn.Location = New-Object System.Drawing.Point(620,150); $removeBtn.Size = New-Object System.Drawing.Size(170,30); $form.Controls.Add($removeBtn)
$totalSizeLabel = New-Object System.Windows.Forms.Label; $totalSizeLabel.Location = New-Object System.Drawing.Point(10,360); $totalSizeLabel.Size = New-Object System.Drawing.Size(780,20); $totalSizeLabel.Text = "Total estimated size: 0 Bytes"; $form.Controls.Add($totalSizeLabel)

$Global:RobocopyOutputBox = New-Object System.Windows.Forms.TextBox; $Global:RobocopyOutputBox.Multiline = $true; $Global:RobocopyOutputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical; $Global:RobocopyOutputBox.Location = New-Object System.Drawing.Point(10,390); $Global:RobocopyOutputBox.Size = New-Object System.Drawing.Size(780,100); $Global:RobocopyOutputBox.ReadOnly = $true; $Global:RobocopyOutputBox.Font = New-Object System.Drawing.Font("Consolas", 8); $Global:RobocopyOutputBox.Visible = $false; $form.Controls.Add($Global:RobocopyOutputBox)

$previewBtn = New-Object System.Windows.Forms.Button; $previewBtn.Text = "Preview Summary"; $previewBtn.Location = New-Object System.Drawing.Point(10,500); $previewBtn.Size = New-Object System.Drawing.Size(180,30); $form.Controls.Add($previewBtn)
$backupBtn = New-Object System.Windows.Forms.Button; $backupBtn.Text = "Start Backup"; $backupBtn.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold); $backupBtn.Location = New-Object System.Drawing.Point(200,500); $backupBtn.Size = New-Object System.Drawing.Size(220,30); $form.Controls.Add($backupBtn)
$logBtn = New-Object System.Windows.Forms.Button; $logBtn.Text = "View Logs"; $logBtn.Location = New-Object System.Drawing.Point(430,500); $logBtn.Size = New-Object System.Drawing.Size(180,30); $form.Controls.Add($logBtn)
$exitBtn = New-Object System.Windows.Forms.Button; $exitBtn.Text = "Exit"; $exitBtn.Location = New-Object System.Drawing.Point(620,500); $exitBtn.Size = New-Object System.Drawing.Size(170,30); $form.Controls.Add($exitBtn)
$overallProgressBar = New-Object System.Windows.Forms.ProgressBar; $overallProgressBar.Location = New-Object System.Drawing.Point(10,540); $overallProgressBar.Size = New-Object System.Drawing.Size(780,20); $overallProgressBar.Visible = $false; $form.Controls.Add($overallProgressBar)
$statusStrip = New-Object System.Windows.Forms.StatusStrip; $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel "Ready"; $statusStrip.Items.Add($statusLabel); $form.Controls.Add($statusStrip)

# --- GUI Update Timer ---
$Global:GuiUpdateTimer = New-Object System.Windows.Forms.Timer
$Global:GuiUpdateTimer.Interval = 500 # Check more frequently

$Global:GuiUpdateTimer.Add_Tick({
    param($sender, $e)
    if ($Global:CurrentRobocopyProcess -ne $null -and -not $Global:CurrentRobocopyProcess.HasExited) {
        if (Test-Path $Global:CurrentRobocopyTempOutputFile) {
            try {
                # Use -Tail for efficiency, get a decent number of lines for context
                $latestOutputLines = Get-Content -Path $Global:CurrentRobocopyTempOutputFile -Tail 20 -ErrorAction SilentlyContinue 
                if ($null -ne $latestOutputLines) { 
                    $Global:RobocopyOutputBox.Text = $latestOutputLines -join [System.Environment]::NewLine
                    
                    if ($Global:RobocopyOutputBox.TextLength -gt 0) {
                        $Global:RobocopyOutputBox.SelectionStart = $Global:RobocopyOutputBox.TextLength
                        $Global:RobocopyOutputBox.ScrollToCaret()
                    }
                    $form.Update() # Force UI repaint to show the new text
                } else {
                    # Log if the temp file is empty during a tick, might indicate Robocopy isn't writing or finished quickly
                    "Timer Tick: '$($Global:CurrentRobocopyTempOutputFile)' is empty or Get-Content returned null." | Out-File -FilePath $Global:MainLogFileForSession -Append -ErrorAction SilentlyContinue
                }
            } catch {
                # Log errors during file read, but don't stop the timer
                "Timer Tick Error reading '$($Global:CurrentRobocopyTempOutputFile)': $($_.Exception.Message)" | Out-File -FilePath $Global:MainLogFileForSession -Append -ErrorAction SilentlyContinue
            }
        }
    } elseif ($Global:CurrentRobocopyProcess -ne $null -and $Global:CurrentRobocopyProcess.HasExited) {
        # Process has finished, handle it
        $Global:GuiUpdateTimer.Stop() 
        
        # Ensure final output is captured before deleting temp file
        if (Test-Path $Global:CurrentRobocopyTempOutputFile) {
             try {
                $finalOutputLines = Get-Content -Path $Global:CurrentRobocopyTempOutputFile -ErrorAction SilentlyContinue
                if ($null -ne $finalOutputLines) {
                    $Global:RobocopyOutputBox.Text = ($finalOutputLines | Select-Object -Last 30) -join [System.Environment]::NewLine # Show a bit more at the end
                    if ($Global:RobocopyOutputBox.TextLength -gt 0) {
                        $Global:RobocopyOutputBox.SelectionStart = $Global:RobocopyOutputBox.TextLength
                        $Global:RobocopyOutputBox.ScrollToCaret()
                    }
                    $form.Update()
                }
            } catch { /* ignore */ }
        }

        $exitCode = $Global:CurrentRobocopyProcess.ExitCode
        $srcPathProcessed = $FolderPaths[$Global:CurrentSourceIndexToProcess]
        $sanitizedName = Sanitize-FolderName -FullPath $srcPathProcessed

        "  Robocopy for '$srcPathProcessed' completed. Exit Code: $exitCode" | Out-File -FilePath $Global:MainLogFileForSession -Append
        if ($exitCode -ge 8) { 
            "  ERROR: Robocopy reported errors for '$srcPathProcessed'. Check Robocopy log for details: $($Global:RobocopyPersistentLogFile)" | Out-File -FilePath $Global:MainLogFileForSession -Append
            $statusLabel.Text = "Overall: ($($Global:CurrentSourceIndexToProcess+1)/$($FolderPaths.Count)) - Error copying '$sanitizedName'. Check logs."
            $script:overallSuccessInBackup = $false 
        } elseif ($exitCode -ge 1 -and $exitCode -lt 8) { 
            "  Robocopy completed with warnings/info for '$srcPathProcessed'. Check Robocopy log: $($Global:RobocopyPersistentLogFile)" | Out-File -FilePath $Global:MainLogFileForSession -Append
            $statusLabel.Text = "Overall: ($($Global:CurrentSourceIndexToProcess+1)/$($FolderPaths.Count)) - Copied '$sanitizedName' with info/warnings."
        } else { 
            "  Robocopy completed successfully for '$srcPathProcessed'. No changes or files copied." | Out-File -FilePath $Global:MainLogFileForSession -Append
            $statusLabel.Text = "Overall: ($($Global:CurrentSourceIndexToProcess+1)/$($FolderPaths.Count)) - Verified '$sanitizedName' (no changes)."
        }
        "---" | Out-File -FilePath $Global:MainLogFileForSession -Append

        $overallProgressBar.Value = $Global:CurrentSourceIndexToProcess + 1
        if (Test-Path $Global:CurrentRobocopyTempOutputFile) { Remove-Item $Global:CurrentRobocopyTempOutputFile -Force -ErrorAction SilentlyContinue }
        $Global:CurrentRobocopyProcess = $null
        $Global:CurrentSourceIndexToProcess++
        
        StartNextRobocopyProcessOrFinalize 
    }
})


# --- UI Event Handlers ---
function Update-FolderDisplayAndSize { 
    $folderListBox.BeginUpdate()
    $folderListBox.Items.Clear()
    $Global:TotalBackupSize = 0 
    
    foreach ($pathItemInList in $FolderPaths) { # Use a different loop variable name to avoid confusion
        # $statusLabel.Text = "Updating display for $pathItemInList..." # This can be too noisy, remove or make less frequent
        # $form.Update() 
        $size = Get-FolderSize -Path $pathItemInList
        $Global:TotalBackupSize += $size
        $folderListBox.Items.Add("$pathItemInList (`Est. Size: $(Format-Size $size)`)")
    }
    $totalSizeLabel.Text = "Total est. size: $(Format-Size $Global:TotalBackupSize)"
    $statusLabel.Text = "Ready." 
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
                [System.Windows.Forms.MessageBox]::Show("Path not found/not a folder: $trimmedPath", "Invalid Path", "OK", "Warning") | Out-Null 
            } 
        } 
    }
    $manualInputBox.Clear()
    Update-FolderDisplayAndSize 
})

$folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowserDialog.Description = "Select folder to back up"
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
    $selectedIndex = $folderListBox.SelectedIndex
    if ($selectedIndex -ge 0) {
        # Ensure the index is valid for the FolderPaths array as well
        if ($selectedIndex -lt $FolderPaths.Count) {
            $pathActuallyRemoved = $FolderPaths[$selectedIndex]
            $FolderPaths.RemoveAt($selectedIndex) # Remove by index from ArrayList
            $statusLabel.Text = "Removed: $pathActuallyRemoved"
            Update-FolderDisplayAndSize # This will clear and repopulate the listbox
        } else {
            # This would indicate a desync between ListBox and FolderPaths
            $statusLabel.Text = "Error: List selection out of sync. Please try again."
            Write-Error "ListBox selected index $selectedIndex is out of bounds for FolderPaths (Count: $($FolderPaths.Count))."
        }
    } else {
        $statusLabel.Text = "No folder selected to remove."
    }
})

$previewBtn.Add_Click({ 
    if ($FolderPaths.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("No folders to preview.", "Empty List", "OK", "Info") | Out-Null; return }
    $msg = "Backup Summary:`n`n"
    foreach ($path in $FolderPaths) { 
        $size = Get-FolderSize -Path $path
        $msg += "$path`n  Est. Size: $(Format-Size $size)`n`n" 
    }
    $msg += "$($totalSizeLabel.Text)`n`nDestination Base: $(Join-Path $BoxSyncBasePath $BoxBackupTargetFolder)"
    [System.Windows.Forms.MessageBox]::Show($form, $msg, "Backup Preview", "OK", "Info") | Out-Null 
})

# --- Backup Process Control Functions ---
function StartNextRobocopyProcessOrFinalize {
    if ($Global:CurrentSourceIndexToProcess -lt $FolderPaths.Count) {
        $srcPath = $FolderPaths[$Global:CurrentSourceIndexToProcess]
        $sanitizedSrcFolderName = Sanitize-FolderName -FullPath $srcPath
        $timestampForFile = Get-Date -Format "yyyyMMddHHmmss" # Unique for temp file
        $Global:CurrentRobocopyTempOutputFile = Join-Path $env:TEMP "RoboOutput_$(Sanitize-FolderName -FullPath $srcPath)_$timestampForFile.txt"
        
        # Construct target path for this specific source
        $timestampForSession = $Global:BackupSessionTimestamp # Use session timestamp for folder structure
        $backupSessionFolderNameForPath = "Backup_$timestampForSession"
        $targetBackupSessionPathForPath = Join-Path -Path (Join-Path -Path $BoxSyncBasePath -ChildPath $BoxBackupTargetFolder) -ChildPath $backupSessionFolderNameForPath
        $destinationForThisSource = Join-Path $targetBackupSessionPathForPath $sanitizedSrcFolderName

        # Define the persistent Robocopy log file path for the current source
        $mainLogDirForRobo = Join-Path $env:TEMP "UserBoxBackupLogs" 
        $Global:RobocopyPersistentLogFile = Join-Path $mainLogDirForRobo "Robocopy_$(Sanitize-FolderName -FullPath $srcPath)_$($Global:BackupSessionTimestamp).log"


        $statusLabel.Text = "Overall: ($($Global:CurrentSourceIndexToProcess+1)/$($FolderPaths.Count)) - Starting copy of '$sanitizedSrcFolderName'..."
        $Global:RobocopyOutputBox.Text = "Preparing to copy $sanitizedSrcFolderName..." # Initial message
        $form.Update()

        # Ensure destination directory for this source exists
        try {
            if (-not (Test-Path $destinationForThisSource)) {
                New-Item -ItemType Directory -Path $destinationForThisSource -Force -ErrorAction Stop | Out-Null
            }
        } catch {
            $errMsg = "ERROR: Could not create destination subfolder: $destinationForThisSource. Error: $($_.Exception.Message). Skipping."
            $statusLabel.Text = "Overall: ($($Global:CurrentSourceIndexToProcess+1)/$($FolderPaths.Count)) - Error for '$sanitizedSrcFolderName'. See log."
            $errMsg | Out-File -FilePath $Global:MainLogFileForSession -Append
            $script:overallSuccessInBackup = $false
            $overallProgressBar.Value = $Global:CurrentSourceIndexToProcess + 1
            $Global:CurrentSourceIndexToProcess++
            StartNextRobocopyProcessOrFinalize # Try next
            return
        }

        $robocopyArgsForCapture = @(
            "`"$srcPath`"",
            "`"$destinationForThisSource`"",
            "/E", "/ZB", "/COPY:DATSOU",
            "/R:1", "/W:2", "/MT:8", 
            "/V", "/ETA", 
            "/LOG+:`"$($Global:RobocopyPersistentLogFile)`"" 
        )
        
        "Processing Source ($($Global:CurrentSourceIndexToProcess+1)/$($FolderPaths.Count)): $srcPath" | Out-File -FilePath $Global:MainLogFileForSession -Append
        "  Targeting: $destinationForThisSource" | Out-File -FilePath $Global:MainLogFileForSession -Append
        "  Persistent Robocopy Log: $($Global:RobocopyPersistentLogFile)" | Out-File -FilePath $Global:MainLogFileForSession -Append
        "  Temp Output for GUI: $Global:CurrentRobocopyTempOutputFile" | Out-File -FilePath $Global:MainLogFileForSession -Append

        try {
            # Start Robocopy, redirecting standard output for GUI. Standard error will also go to Robocopy's own log / console (hidden).
            $Global:CurrentRobocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgsForCapture -RedirectStandardOutput $Global:CurrentRobocopyTempOutputFile -PassThru -WindowStyle Hidden
            $Global:GuiUpdateTimer.Start()
        } catch {
            $errMsg = "CRITICAL ERROR starting Robocopy for '$srcPath'. Error: $($_.Exception.Message)"
            $errMsg | Out-File -FilePath $Global:MainLogFileForSession -Append
            $statusLabel.Text = "Failed to start Robocopy for '$sanitizedSrcFolderName'."
            $script:overallSuccessInBackup = $false
            $Global:CurrentSourceIndexToProcess++
            StartNextRobocopyProcessOrFinalize
        }
    } else {
        # All folders processed
        $Global:GuiUpdateTimer.Stop()
        $backupBtn.Enabled = $true; $addBtn.Enabled = $true; $addManualBtn.Enabled = $true; $removeBtn.Enabled = $true; $previewBtn.Enabled = $true
        $backupBtn.Text = "Start Backup"
        $overallProgressBar.Visible = $false
        $Global:RobocopyOutputBox.Visible = $false

        $finalMessage = "Backup process finished."
        if ($script:overallSuccessInBackup) {
            $finalMessage += " All selected sources processed."
            if ($FolderPaths.Count -gt 0) { $finalMessage += " Some ops may have had warnings/info (check logs)." } 
            $statusLabel.Text = "Backup finished. Check logs for details."
            [System.Windows.Forms.MessageBox]::Show($form, "$finalMessage`n`nOverall session log: $Global:MainLogFileForSession`nIndividual Robocopy logs are in: $(Split-Path $Global:MainLogFileForSession -Parent)", "Backup Complete", "OK", "Info") | Out-Null
        } else {
            $finalMessage += " One or more sources encountered errors."
            $statusLabel.Text = "Backup finished with errors. Please review logs."
            [System.Windows.Forms.MessageBox]::Show($form, "$finalMessage`n`nOverall session log: $Global:MainLogFileForSession`nIndividual Robocopy logs are in: $(Split-Path $Global:MainLogFileForSession -Parent)`n`nPlease review logs for failures.", "Backup Completed with Errors", "OK", "Warning") | Out-Null
        }
        "$finalMessage. Session ended at $(Get-Date)" | Out-File -FilePath $Global:MainLogFileForSession -Append
        $form.Update()
    }
}

$backupBtn.Add_Click({
    if ($FolderPaths.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show($form, "No folders to back up.", "Missing Folders", "OK", "Warning") | Out-Null; return }
    $confirmation = [System.Windows.Forms.MessageBox]::Show($form, "Back up selected folders to local Box sync folder?`nDestination base: `n$(Join-Path $BoxSyncBasePath $BoxBackupTargetFolder)`n`nProceed?", "Confirm Backup", "YesNo", "Question")
    if ($confirmation -ne "Yes") { $statusLabel.Text = "Backup cancelled."; return }

    $backupBtn.Enabled = $false; $addBtn.Enabled = $false; $addManualBtn.Enabled = $false; $removeBtn.Enabled = $false; $previewBtn.Enabled = $false
    $overallProgressBar.Minimum = 0; $overallProgressBar.Maximum = $FolderPaths.Count; $overallProgressBar.Value = 0; $overallProgressBar.Visible = $true
    $Global:RobocopyOutputBox.Text = ""; $Global:RobocopyOutputBox.Visible = $true
    $backupBtn.Text = "Backup in Progress..."
    $form.Update()

    $Global:BackupSessionTimestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss" 
    $backupSessionFolderName = "Backup_$($Global:BackupSessionTimestamp)"
    $targetBackupSessionPath = Join-Path -Path (Join-Path -Path $BoxSyncBasePath -ChildPath $BoxBackupTargetFolder) -ChildPath $backupSessionFolderName
    
    $mainLogDir = Join-Path $env:TEMP "UserBoxBackupLogs"
    if (-not (Test-Path $mainLogDir)) { New-Item -ItemType Directory -Path $mainLogDir -Force | Out-Null }
    $Global:MainLogFileForSession = Join-Path $mainLogDir "BackupSessionSummary_$($Global:BackupSessionTimestamp).log" 

    "Backup session started at $(Get-Date)" | Out-File -FilePath $Global:MainLogFileForSession -Append
    "Target Box sync path for this session: $targetBackupSessionPath" | Out-File -FilePath $Global:MainLogFileForSession -Append
    "---" | Out-File -FilePath $Global:MainLogFileForSession -Append

    try {
        if (-not (Test-Path $targetBackupSessionPath)) { New-Item -ItemType Directory -Path $targetBackupSessionPath -Force | Out-Null; "Created session folder: $targetBackupSessionPath" | Out-File -FilePath $Global:MainLogFileForSession -Append }
    } catch {
        $errMsg = "CRITICAL ERROR: Could not create base backup session folder: $targetBackupSessionPath. Error: $($_.Exception.Message). Backup aborted."
        $statusLabel.Text = $errMsg; $errMsg | Out-File -FilePath $Global:MainLogFileForSession -Append; [System.Windows.Forms.MessageBox]::Show($form, $errMsg, "Backup Error", "OK", "Error") | Out-Null
        $backupBtn.Enabled = $true; $addBtn.Enabled = $true; $addManualBtn.Enabled = $true; $removeBtn.Enabled = $true; $previewBtn.Enabled = $true; $backupBtn.Text = "Start Backup"; $overallProgressBar.Visible = $false; $Global:RobocopyOutputBox.Visible = $false
        return
    }
    
    $script:overallSuccessInBackup = $true 
    $Global:CurrentSourceIndexToProcess = 0 
    
    StartNextRobocopyProcessOrFinalize 
})

$logBtn.Add_Click({
    $logDir = Join-Path $env:TEMP "UserBoxBackupLogs"
    if (-not (Test-Path $logDir)) { [System.Windows.Forms.MessageBox]::Show($form, "Log directory not found: $logDir", "No Logs", "OK", "Info") | Out-Null; return }
    $latestSessionLog = Get-ChildItem -Path $logDir -Filter "BackupSessionSummary_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestSessionLog) {
        $result = [System.Windows.Forms.MessageBox]::Show($form, "Open latest session log?`n($($latestSessionLog.Name))`n`n(No to open log directory)", "View Logs", "YesNoCancel", "Question")
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { Invoke-Item $latestSessionLog.FullName } 
        elseif ($result -eq [System.Windows.Forms.DialogResult]::No) { Invoke-Item $logDir }
    } else { [System.Windows.Forms.MessageBox]::Show($form, "No session logs found. Opening log directory: $logDir", "Log Directory", "OK", "Info") | Out-Null; Invoke-Item $logDir }
})

$exitBtn.Add_Click({ $form.Close() })
$form.Add_FormClosing({ Write-Verbose "Exiting backup application."; if($Global:GuiUpdateTimer -and $Global:GuiUpdateTimer.Enabled){ $Global:GuiUpdateTimer.Stop(); $Global:GuiUpdateTimer.Dispose() }; if($Global:CurrentRobocopyProcess -and -not $Global:CurrentRobocopyProcess.HasExited){ try { $Global:CurrentRobocopyProcess.Kill() } catch { Write-Warning "Could not kill active Robocopy process on exit."}} })

# --- Show Form ---
$form.Topmost = $true; Write-Host "Launching User Backup to Box GUI..."; $statusLabel.Text = "Ready."; [void]$form.ShowDialog()