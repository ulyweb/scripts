-- Ask user to choose folders to back up
set sourceFolders to choose folder with prompt "Select one or more folders to back up to Box:" with multiple selections allowed

-- Ask for confirmation before proceeding
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

-- Prepare destination in Box
set timeStamp to do shell script "date +%Y-%m-%d_%H%M"
set userHome to (POSIX path of (path to home folder))
set backupRoot to userHome & "Library/CloudStorage/Box-Box/01. My Personal Folder/recentBackup/"
do shell script "mkdir -p " & quoted form of backupRoot
set logPath to userHome & "Desktop/BoxBackupLog_" & timeStamp & ".txt"

-- Back up each folder to a zip archive
repeat with f in sourceFolders
	set folderPath to POSIX path of f
	set folderName to do shell script "basename " & quoted form of folderPath
	set zipName to "Backup_" & folderName & "_" & timeStamp & ".zip"
	set zipPath to backupRoot & zipName
	
	-- Notify user in Finder
	set notifyScript to "display notification \"Zipping " & folderName & "...\" with title \"Box Backup\""
	do shell script "osascript -e " & quoted form of notifyScript
	
	-- Create ZIP file
	try
		do shell script "cd " & quoted form of folderPath & " && zip -r " & quoted form of zipPath & " . >> " & quoted form of logPath & " 2>&1"
		do shell script "echo 'Successfully zipped " & folderName & " to " & zipPath & "' >> " & quoted form of logPath
	on error errMsg
		do shell script "echo 'ERROR backing up " & folderName & ": " & errMsg & "' >> " & quoted form of logPath
	end try
end repeat

-- Final success notification
display dialog "Backup complete!" & linefeed & "Log file saved to Desktop." buttons {"OK"} default button "OK"
