-- ✳️ Notify user about permissions
display dialog "⚠️ Before continuing, make sure this script has the necessary permissions:\n\n1. Go to System Settings > Privacy & Security > Files and Folders:\n   - Allow access to 'Desktop' and any source folders you choose.\n\n2. Go to Privacy & Security > Accessibility:\n   - Allow 'Script Editor' (or the app running this script) to control your computer.\n\nWithout these permissions, the backup may fail.\n\nClick OK when you're ready to continue." buttons {"OK"} default button "OK"

-- 📁 Set up paths
set userHome to (POSIX path of (path to home folder))
set backupRoot to userHome & "Library/CloudStorage/Box-Box/01. My Personal Folder/recentBackup/"
set logFile to userHome & "Desktop/BoxBackupLog_" & (do shell script "date +%Y%m%d%H%M%S") & ".txt"

-- 🧭 Reminder to use ⌘ to select multiple folders
display dialog "Tip: You can select multiple folders by holding the ⌘ (Command) key while clicking." buttons {"OK"} default button "OK"

-- 🔍 Ask user to select source folders using GUI
set sourceFolders to choose folder with prompt "Select the folders you want to back up (hold ⌘ to select multiple)" with multiple selections allowed

-- ✅ Confirm before starting
set totalItems to count of sourceFolders
display dialog "You selected " & totalItems & " folder(s) to back up to Box. Proceed?" buttons {"Cancel", "Yes"} default button "Yes"
if button returned of result is "Cancel" then
	display dialog "Backup cancelled by user." buttons {"OK"} default button "OK"
	return
end if

-- 🗂️ Create backup directory
set timestamp to do shell script "date +%Y-%m-%d_%H%M%S"
set backupFolderName to "Backup_" & timestamp
set finalBackupPath to backupRoot & backupFolderName
do shell script "mkdir -p " & quoted form of finalBackupPath

-- 📊 Begin backup loop with Dock progress
set totalFolders to length of sourceFolders
set folderIndex to 0

repeat with sourceFolder in sourceFolders
	set folderIndex to folderIndex + 1
	set sourcePath to POSIX path of sourceFolder
	set folderName to do shell script "basename " & quoted form of sourcePath
	set zipName to folderName & ".zip"
	set destinationZip to quoted form of (finalBackupPath & "/" & zipName)
	set progressPercent to (folderIndex * 100) / totalFolders

	-- 🚀 Attempt Dock progress (visual cue, not true progress bar)
	do shell script "osascript -e 'tell application \"System Events\" to set the dock tile size of process \"Script Editor\" to 32' >/dev/null 2>&1 &"
	do shell script "osascript -e 'tell application \"System Events\" to tell process \"Script Editor\" to set value of attribute \"AXValue\" of progress indicator 1 of window 1 to " & progressPercent & "' >/dev/null 2>&1 &"

	-- 🪄 Quick UI progress notice
	display dialog "Zipping folder " & folderIndex & " of " & totalFolders & ":\n" & folderName buttons {"OK"} giving up after 1

	-- 🗜️ Zip folder contents
	do shell script "cd " & quoted form of sourcePath & " && zip -r " & destinationZip & " ."

	-- 📝 Log each zip
	do shell script "echo 'Zipped: " & sourcePath & " -> " & destinationZip & "' >> " & quoted form of logFile
end repeat

-- ✅ Final success message
display dialog "✅ Backup complete!\n\n• Files saved to:\n" & finalBackupPath & "\n• Log saved to your Desktop:\n" & logFile buttons {"OK"} default button "OK"
