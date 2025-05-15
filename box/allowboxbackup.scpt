-- Ask for source folder(s)
set sourceFolders to choose folders with prompt "Select one or more folders to back up:" with multiple selections allowed

-- Set backup root folder (you can customize this)
set userHome to (POSIX path of (path to home folder))
set backupRoot to userHome & "Library/Mobile Documents/com~apple~CloudDocs/Backups/"
set backupName to "Backup_" & do shell script "date +%Y-%m-%d_%H%M"
set destinationPath to backupRoot & backupName

-- Create the backup folder
do shell script "mkdir -p " & quoted form of destinationPath

-- Collect all files, calculate total size and file count
set totalSize to 0
set totalFiles to 0
set fileList to {}

repeat with srcFolder in sourceFolders
	set srcPath to POSIX path of srcFolder
	set findCmd to "find " & quoted form of srcPath & " -type f"
	set foundFiles to paragraphs of (do shell script findCmd)
	
	repeat with f in foundFiles
		set end of fileList to f
		set totalFiles to totalFiles + 1
		try
			set fileSize to (do shell script "stat -f%z " & quoted form of f) as number
			set totalSize to totalSize + fileSize
		end try
	end repeat
end repeat

-- Convert size to MB
set totalSizeMB to totalSize / 1024 / 1024
set totalSizeRounded to (round totalSizeMB * 100) / 100

-- Confirm with user
display dialog "Total files: " & totalFiles & return & "Total size: " & totalSizeRounded & " MB" & return & return & "Do you want to start the backup now?" buttons {"Cancel", "Yes"} default button "Yes"
if the button returned of the result is "Cancel" then
	display dialog "Backup cancelled." buttons {"OK"} default button "OK"
	return
end if

-- Begin file copy
repeat with f in fileList
	set relPath to do shell script "python3 -c 'import os; print(os.path.relpath(" & quoted form of f & ", " & quoted form of userHome & "))'"
	set destFile to destinationPath & "/" & relPath
	set destDir to do shell script "dirname " & quoted form of destFile
	do shell script "mkdir -p " & quoted form of destDir
	do shell script "cp -p " & quoted form of f & " " & quoted form of destFile
end repeat

-- Done
display dialog "Backup completed successfully." buttons {"OK"} default button "OK"
