Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

function Test-BoxEnvironment {
    $missingComponents = @()
    $boxDrivePath = "$env:ProgramFiles\Box\Box"  # Box Drive default location
    $boxToolsPath = "$env:ProgramFiles\Box\Box Edit"  # Box Tools default location
    $userBoxFolder = "$env:USERPROFILE\Box"

    if (-not (Test-Path $boxDrivePath)) {
        $missingComponents += "Box Drive"
    }
    if (-not (Test-Path $boxToolsPath)) {
        $missingComponents += "Box Tools"
    }
    if (-not (Test-Path $userBoxFolder)) {
        $missingComponents += "Box Folder (under user profile)"
    }

    if ($missingComponents.Count -gt 0) {
        $message = "The following required components are missing:`n`n"
        $message += ($missingComponents -join "`n")
        $message += "`n`nPlease install them from the Software Center before proceeding."
        [System.Windows.MessageBox]::Show($message, "Missing Components", 'OK', 'Error') | Out-Null
        exit
    }
}

function Get-FolderSize {
    param ([string]$Path)
    $size = 0
    try {
        $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $size += $file.Length
        }
    } catch {
        return 0
    }
    return [Math]::Round($size / 1MB, 2)
}

function Get-TotalSizeDisplay {
    param ([System.Collections.ObjectModel.ObservableCollection[string]]$Paths)
    $info = @()
    $totalSize = 0

    foreach ($folder in $Paths) {
        if (Test-Path $folder) {
            $size = Get-FolderSize -Path $folder
            $info += "[$size MB] $folder"
            $totalSize += $size
        }
    }

    return ,(@($info -join "`n"), "`nTotal Size: $([Math]::Round($totalSize, 2)) MB")
}

# Box Environment Check
Test-BoxEnvironment

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Backup to Box Tool" Height="600" Width="800">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Name="UserProfileBlock" Grid.Row="0" FontWeight="Bold" FontSize="14" TextWrapping="Wrap"/>

        <TextBlock Grid.Row="1" FontWeight="Bold" FontSize="13" Text="Step 1: Add folders to back up (select using Add Folder or enter paths manually below)" />

        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBox Name="FolderTextBox" Grid.Column="0" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Height="150" TextWrapping="Wrap"/>

            <StackPanel Grid.Column="1" Margin="10,0,0,0">
                <Button Name="AddFolderButton" Content="Add Folder" Width="100" Margin="0,0,0,5" />
                <Button Name="RemoveFolderButton" Content="Remove Folder" Width="100" Margin="0,0,0,5" />
                <Button Name="PreviewButton" Content="Preview Selection" Width="100" Margin="0,0,0,5" />
            </StackPanel>
        </Grid>

        <TextBlock Name="SizeInfoBlock" Grid.Row="3" FontStyle="Italic" Foreground="DarkSlateGray" Margin="0,5,0,0"/>

        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10">
            <Button Name="StartButton" Content="Start Backup" Width="120" Margin="5" />
            <Button Name="LogButton" Content="View Log File" Width="120" Margin="5" />
            <Button Name="ExitButton" Content="Exit" Width="80" Margin="5" />
        </StackPanel>

        <ProgressBar Name="BackupProgressBar" Grid.Row="5" Height="20" Minimum="0" Maximum="100" Visibility="Collapsed"/>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$folderTextBox = $window.FindName("FolderTextBox")
$addFolderButton = $window.FindName("AddFolderButton")
$removeFolderButton = $window.FindName("RemoveFolderButton")
$previewButton = $window.FindName("PreviewButton")
$startButton = $window.FindName("StartButton")
$logButton = $window.FindName("LogButton")
$exitButton = $window.FindName("ExitButton")
$progressBar = $window.FindName("BackupProgressBar")
$sizeInfoBlock = $window.FindName("SizeInfoBlock")
$userProfileBlock = $window.FindName("UserProfileBlock")

$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userProfileBlock.Text = "Current User: $user ($env:USERPROFILE)"

$backupLogPath = "$env:TEMP\BoxBackupLog.txt"
if (Test-Path $backupLogPath) { Remove-Item $backupLogPath -Force }

function Write-Log {
    param ($message)
    Add-Content -Path $backupLogPath -Value ("[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] $message")
}

$folderList = New-Object System.Collections.ObjectModel.ObservableCollection[string]

$addFolderButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select one or more folders to back up"
    if ($dialog.ShowDialog() -eq 'OK') {
        if (-not ($folderList -contains $dialog.SelectedPath)) {
            $folderList.Add($dialog.SelectedPath)
            $folderTextBox.Text += "$($dialog.SelectedPath)`n"
        }
    }
})

$removeFolderButton.Add_Click({
    $selectedText = $folderTextBox.SelectedText.Trim()
    if ($selectedText -and $folderList -contains $selectedText) {
        $folderList.Remove($selectedText)
        $folderTextBox.Text = ($folderList -join "`n") + "`n"
    }
})

$previewButton.Add_Click({
    $manualPaths = $folderTextBox.Text -split "`n" | Where-Object { $_ -and (Test-Path $_) }
    $folderList.Clear()
    $manualPaths | ForEach-Object { $folderList.Add($_) }
    $preview = Get-TotalSizeDisplay -Paths $folderList
    $sizeInfoBlock.Text = $preview -join ""
})

$logButton.Add_Click({
    if (Test-Path $backupLogPath) {
        Start-Process notepad.exe $backupLogPath
    } else {
        [System.Windows.MessageBox]::Show("No log file found.", "Box Backup Tool", 'OK', 'Warning') | Out-Null
    }
})

$exitButton.Add_Click({ $window.Close() })

$startButton.Add_Click({
    $progressBar.Visibility = 'Visible'
    $progressBar.Value = 0
    $folderList.Clear()
    $manualPaths = $folderTextBox.Text -split "`n" | Where-Object { $_ -and (Test-Path $_) }
    $manualPaths | ForEach-Object { $folderList.Add($_) }

    if ($folderList.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select or enter at least one folder to back up.", "Missing Input", 'OK', 'Warning') | Out-Null
        return
    }

    $destinationRoot = "$env:USERPROFILE\Box\01. My Personal Folder\recentBackup"
    if (-not (Test-Path $destinationRoot)) { New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $backupFolder = Join-Path $destinationRoot "Backup_$timestamp"
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null

    Write-Log "Backup started to: $backupFolder"

    $fileCount = 0
    $totalFiles = ($folderList | ForEach-Object { Get-ChildItem -Path $_ -Recurse -File -ErrorAction SilentlyContinue }).Count

    foreach ($source in $folderList) {
        $files = Get-ChildItem -Path $source -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($source.Length).TrimStart('\')
            $destPath = Join-Path -Path (Join-Path $backupFolder (Split-Path $source -Leaf)) $relativePath
            $destDir = Split-Path -Path $destPath
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -Path $file.FullName -Destination $destPath -Force
            Write-Log "Copied: $($file.FullName) to $destPath"
            $fileCount++
            $progressBar.Value = [math]::Round(($fileCount / $totalFiles) * 100)
        }
    }

    Write-Log "Backup completed. Total files copied: $fileCount."
    [System.Windows.MessageBox]::Show("Backup completed successfully! Log file saved to $backupLogPath", "Success", 'OK', 'Info') | Out-Null
    $progressBar.Visibility = 'Collapsed'
})

$window.ShowDialog() | Out-Null
