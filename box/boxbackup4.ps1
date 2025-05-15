Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PowerManager {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@

# Constants for preventing sleep
$ES_CONTINUOUS = 0x80000000
$ES_SYSTEM_REQUIRED = 0x00000001
$ES_AWAYMODE_REQUIRED = 0x00000040

function Prevent-Sleep {
    [PowerManager]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_AWAYMODE_REQUIRED) | Out-Null
}

function Restore-Sleep {
    [PowerManager]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Backup to Box"
$form.Size = New-Object System.Drawing.Size(600, 400)
$form.StartPosition = "CenterScreen"

# Info Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter source folder path(s) separated by semicolons (;)"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($label)

# Textbox for source input
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(540, 20)
$textBox.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($textBox)

# Output area
$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Multiline = $true
$outputBox.ScrollBars = "Vertical"
$outputBox.ReadOnly = $true
$outputBox.Size = New-Object System.Drawing.Size(540, 200)
$outputBox.Location = New-Object System.Drawing.Point(20, 130)
$form.Controls.Add($outputBox)

# Button to start backup
$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "Start Backup"
$backupButton.Location = New-Object System.Drawing.Point(20, 90)
$form.Controls.Add($backupButton)

# Button to close
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(140, 90)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

function Show-Output($msg, $color = "Black") {
    $outputBox.SelectionColor = [System.Drawing.Color]::$color
    $outputBox.AppendText("$msg`r`n")
    $outputBox.ScrollToCaret()
}

$backupButton.Add_Click({
    $sourceInput = $textBox.Text
    if ([string]::IsNullOrWhiteSpace($sourceInput)) {
        Show-Output "No source paths provided." "Red"
        return
    }

    # Display battery/power message
    [System.Windows.Forms.MessageBox]::Show("⚠️ Please ensure your system is plugged into power. The system will be prevented from sleeping during the backup.", "Power Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)

    $SourcePaths = $sourceInput -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    $totalSize = 0
    foreach ($src in $SourcePaths) {
        if (Test-Path $src) {
            $totalSize += (Get-ChildItem -Path $src -Recurse -File | Measure-Object -Property Length -Sum).Sum
        }
    }

    $sizeMB = [Math]::Round($totalSize / 1MB, 2)
    $confirmation = [System.Windows.Forms.MessageBox]::Show("The total size of selected folders is $sizeMB MB.`nDo you want to proceed?", "Confirm Backup", "YesNo", "Question")

    if ($confirmation -ne "Yes") {
        Show-Output "Backup cancelled by user." "Orange"
        return
    }

    # Prevent sleep
    Prevent-Sleep

    $CurrentUser = $env:USERNAME
    $BoxDriveRoot = "C:\Users\$CurrentUser\Box\01. My Personal Folder\recentBackup"
    $BackupFolderName = "Backup_$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
    $DestinationPath = Join-Path -Path $BoxDriveRoot -ChildPath $BackupFolderName

    if (-not (Test-Path -Path $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    $logFile = "$env:TEMP\BoxBackupLog_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    Start-Transcript -Path $logFile | Out-Null

    try {
        $totalFiles = 0
        $allFiles = @()

        foreach ($src in $SourcePaths) {
            if (-not (Test-Path $src)) {
                Show-Output "Source path does not exist: $src" "Red"
                continue
            }
            $files = Get-ChildItem -Path $src -Recurse -File
            $allFiles += $files
            $totalFiles += $files.Count
        }

        if ($totalFiles -eq 0) {
            Show-Output "No files to copy." "Red"
            Stop-Transcript | Out-Null
            return
        }

        $currentFile = 0
        foreach ($file in $allFiles) {
            $currentFile++
            $srcBase = $SourcePaths | Where-Object { $file.FullName.StartsWith($_) } | Select-Object -First 1
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

                    Show-Output "Copied: $($file.FullName)" "Green"
                    $success = $true
                } catch {
                    $retry++
                    if ($retry -gt $maxRetries) {
                        Show-Output "❌ Failed to copy $($file.FullName) after $maxRetries attempts." "Red"
                    } else {
                        Show-Output "Retrying $($file.FullName)... ($retry/$maxRetries)" "Orange"
                        Start-Sleep -Seconds 5
                    }
                }
            }
        }

        Show-Output "`nBackup completed successfully!" "Blue"
        Show-Output "Backup location: $DestinationPath" "Blue"
        Show-Output "Log file: $logFile" "Gray"
    } catch {
        Show-Output "Backup failed: $_" "Red"
    } finally {
        Stop-Transcript | Out-Null
        Restore-Sleep
    }
})

# Run the form
[void]$form.ShowDialog()
