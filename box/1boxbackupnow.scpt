-- Display user instructions before selecting folders
display dialog "📁 Hold the Command (⌘) key to select multiple folders." buttons {"OK"} default button "OK"

-- Prompt user to select one or more folders
set sourceFolders to choose folder with prompt "Select the folders you want to back up to Box:" with multiple selections allowed

-- Build folder list and calculate total size
set totalSize to 0
set folderListText to ""
repeat with f in sourceFolders
	set folderListText to folderListText & (POSIX path of f) & linefeed
	set folderSize to do shell script "du -sk " & quoted form of POSIX path of f & " | awk '{print $1}'"
	set totalSize to totalSize + (folderSize as number)
end repeat

-- Convert size to MB
set totalSizeMB to totalSize / 1024
set confirmText to "You selected the following folders for backup:" & linefeed & linefeed & folderListText & linefeed & "Total size: " & (round (totalSizeMB * 100) / 100) & " MB" & linefeed & linefeed & "Do you want to continue?"

-- Confirm with user before continuing
display dialog confirmText buttons {"Cancel", "Yes"} default button "Yes"
if button returned of result is "Cancel" then
	display dialog "❌ Backup cancelled by user." buttons {"OK"} default button "OK"
	return
end if

-- Prepare destination and log path
set timeStamp to do shell script "date +%Y-%m-%d_%H%M"
set userHome to POSIX path of (path to home folder)
set backupRoot to userHome & "Library/CloudStorage/Box-Box/01. My Personal Folder/recentBackup/"
do shell script "mkdir -p " & quoted form of backupRoot
set logPath to userHome & "Desktop/BoxBackupLog_" & timeStamp & ".txt"

-- Track progress
set totalFolders to count of sourceFolders
set currentFolderIndex to 1

-- Process each selected folder
repeat with f in sourceFolders
	set folderPath to POSIX path of f
	set folderName to do shell script "basename " & quoted form of folderPath
	set zipName to "Backup_" & folderName & "_" & timeStamp & ".zip"
	set zipPath to backupRoot & zipName

	-- Show native AppleScript notification for progress
	set progressPercent to round ((currentFolderIndex / totalFolders) * 100)
	set progressMsg to "Backing up " & folderName & " (" & currentFolderIndex & " of " & totalFolders & ") – " & progressPercent & "% done"
	display notification progressMsg with title "Box Backup"

	-- Perform ZIP operation
	try
		do shell script "cd " & quoted form of folderPath & " && zip -r " & quoted form of zipPath & " . >> " & quoted form of logPath & " 2>&1"
		do shell script "echo '✅ Successfully zipped " & folderName & " to " & zipPath & "' >> " & quoted form of logPath
	on error errMsg
		do shell script "echo '❌ ERROR backing up " & folderName & ": " & errMsg & "' >> " & quoted form of logPath
	end try

	set currentFolderIndex to currentFolderIndex + 1
end repeat

-- Final success message
display dialog "✅ Backup complete! All selected folders have been archived to your Box folder." & linefeed & "Log file saved to Desktop." buttons {"OK"} default button "OK"
