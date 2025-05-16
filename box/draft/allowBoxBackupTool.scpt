-- Prompt user for folders to back up
display dialog "Enter full folder paths separated by semicolons (;)\nExample: /Users/you/Documents;/Users/you/Downloads" default answer ""
set folderInput to text returned of result

if folderInput is "" then
	display dialog "No folder entered. Backup cancelled." buttons {"OK"} default button 1
	return
end if

-- Parse folder paths
set AppleScript's text item delimiters to ";"
set folderPaths to text items of folderInput
set AppleScript's text item delimiters to ""

-- Define backup destination
set homePath to (POSIX path of (path to home folder))
set backupRoot to homePath & "Library/CloudStorage/Box-Box/01. My Personal Folder/recentBackup/"
do shell script "mkdir -p " & quoted form of backupRoot

-- Create log file
set timestamp to do shell script "date +%Y-%m-%d_%H%M%S"
set logPath to (homePath & "Desktop/BackupLog_" & timestamp & ".txt")
set logText to "Backup started at " & timestamp & linefeed & linefeed

-- Prepare zip filename
set zipFileName to "Backup_" & timestamp & ".zip"
set zipFullPath to backupRoot & zipFileName

-- Build zip command
set zipCommand to "zip -r " & quoted form of zipFullPath
set fileCount to 0

repeat with folderPath in folderPaths
	set trimmedPath to (do shell script "echo " & quoted form of folderPath & " | sed 's/[[:space:]]*$//'")
	if trimmedPath is not "" then
		set exists to (do shell script "test -d " & quoted form of trimmedPath & " && echo yes || echo no")
		if exists is "yes" then
			set zipCommand to zipCommand & " " & quoted form of trimmedPath
			set fileCount to fileCount + 1
			set logText to logText & "Included: " & trimmedPath & linefeed
		else
			set logText to logText & "Skipped (not found): " & trimmedPath & linefeed
		end if
	end if
end repeat

if fileCount is 0 then
	display dialog "No valid folders to back up. Exiting." buttons {"OK"} default button 1
	return
end if

-- Confirm with user
display dialog "Ready to back up " & fileCount & " folder(s) to Box.\nContinue?" buttons {"Cancel", "Yes"} default button 2
if button returned of result is not "Yes" then
	display dialog "Backup cancelled by user." buttons {"OK"} default button 1
	return
end if

-- Notify starting
display notification "Backup starting…" with title "Box Backup"

-- Show Finder progress bar by copying large dummy file first to force animation
do shell script "dd if=/dev/zero of=" & quoted form of (backupRoot & "._progress_dummy") & " bs=1m count=1"

-- Run zip backup
try
	do shell script zipCommand
	set logText to logText & linefeed & "Backup completed successfully." & linefeed
	display notification "Backup complete!" with title "Box Backup"
on error errMsg
	set logText to logText & linefeed & "Backup failed: " & errMsg & linefeed
	display dialog "Backup failed:\n" & errMsg buttons {"OK"} default button 1
end try

-- Clean up dummy file
do shell script "rm -f " & quoted form of (backupRoot & "._progress_dummy")

-- Save log file
do shell script "echo " & quoted form of logText & " > " & quoted form of logPath

-- Open backup location in Finder
do shell script "open " & quoted form of backupRoot
