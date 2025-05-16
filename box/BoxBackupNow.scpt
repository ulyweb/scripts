-- Notify user how to select multiple folders
display dialog "Hold down the Command (⌘) key to select multiple folders." buttons {"OK"} default button "OK"

-- Ask user to choose folders to back up
set sourceFolders to choose folder with prompt "Select one or more folders to back up to Box:" with multiple selections allowed

-- Calculate total size and display confirmation
set totalSize to 0
set folderListText to ""
repeat with f in sourceFolders
	set folderListText to folderListText & (POSIX path of f) & linefeed
	set folderSize to do shell script "du -sk " & quoted form of POSIX path of f & " | awk '{print $1}'"
	set totalSize to totalSize + (folderSize as number)
end repeat

set totalSizeMB to totalSize / 1024
set confirmText to "You've selected the following folders for backup:" & linefeed & linefeed & folderListText & linefeed & "Total size: " & (round (totalSizeMB * 100) / 100) & " MB" & linefeed & linefeed & "Do you want to continue?"

display dialog confirmText buttons {"Cancel", "Yes"} default button "Yes"
if button returned of result is "Cancel" then
	display dialog "Backup cancelled." buttons {"OK"} default button "OK"
	return
end if

-- Prepare backup destination
set timeStamp to do shell script "date +%Y-%m-%d_%H%M"
set userHome to (POSIX path of (path to home folder))
set backupRoot to userHome & "Library/CloudStorage/Box-Box/01. My Personal Folder/recentBackup/"
do shell script "mkdir -p " & quoted form of backupRoot
set logPath to userHome & "Desktop/BoxBackupLog_" & timeStamp & ".txt"

-- Initialize progress bar info
set totalFolders to count of sourceFolders
set currentFolderIndex to 1

-- Back up each folder with progress notifications
repeat with f in sourceFolders
	set folderPath to POSIX path of f
	set folderName to do shell script "basename " & quoted form of folderPath
	set zipName to "Backup_" & folderName & "_" & timeStamp & ".zip"
	set zipPath to backupRoot & zipName

	-- Update user with progress via Finder
	set progressPercent to round ((currentFolderIndex / totalFolders) * 100)
	set progressMsg to "Zipping " & folderName & " (" & currentFolderIndex & " of " & totalFolders & ") - " & progressPercent & "% done"
	do shell script "osascript -e " & quoted form of ("display notification " & quoted form of progressMsg & " with title \"Box Backup\"")

	-- Create zip archive
	try
		do shell script "cd " & quoted form of folderPath & " && zip -r " & quoted form of zipPath & " . >> " & quoted form of logPath & " 2>&1"
		do shell script "echo 'Successfully zipped " & folderName & " to " & zipPath & "' >> " & quoted form of logPath
	on error errMsg
		do shell script "echo 'ERROR backing up " & folderName & ": " & errMsg & "' >> " & quoted form of logPath
	end try

	set currentFolderIndex to currentFolderIndex + 1
end repeat

-- Final success message
display dialog "Backup complete! Your data has been backed up to your Box folder." & linefeed & "Log file saved on Desktop." buttons {"OK"} default button "OK"
