-- Ask for one source folder
set sourceFolder to choose folder with prompt "Select the folder to back up:"
set sourceFolders to {sourceFolder}

-- Define backup destination in Box
set homePath to (POSIX path of (path to home folder))
set boxBackupRoot to homePath & "Library/CloudStorage/Box-Box/01. My Personal/recentBackup/"
set backupName to "Backup_" & do shell script "date +%Y-%m-%d_%H%M"
set destinationPath to boxBackupRoot & backupName

-- Create the backup folder
do shell script "mkdir -p " & quoted form of destinationPath

-- Initialize totals
set totalFiles to 0
set totalSize to 0
set fileList to {}

-- Collect files and calculate total size
repeat with aFolder in sourceFolders
	set folderPath to POSIX path of aFolder
	set findCommand to "find " & quoted form of folderPath & " -type f"
	set filePaths to paragraphs of (do shell script findCommand)
	
	repeat with aFile in filePaths
		set end of fileList to aFile
		set totalFiles to totalFiles + 1
		try
			set sizeStr to do shell script "stat -f%z " & quoted form of aFile
			set totalSize to totalSize + (sizeStr as number)
		end try
	end repeat
end repeat

-- Convert bytes to MB and round
set totalSizeMB to (totalSize / 1024 / 1024)
set roundedSize to ((round (totalSizeMB * 100)) / 100)

-- Confirm with user
set theResponse to display dialog "Total files: " & totalFiles & return & "Total size: " & roundedSize & " MB" & return & return & "Start copying to Box?" buttons {"Cancel", "Yes"} default button "Yes"
if button returned of theResponse is "Cancel" then
	display dialog "Backup cancelled." buttons {"OK"} default button "OK"
	return
end if

-- Start copying files
repeat with originalFile in fileList
	set relPath to do shell script "python3 -c \"import os; print(os.path.relpath(" & quoted form of originalFile & ", " & quoted form of folderPath & "))\""
	set fullDestPath to destinationPath & "/" & relPath
	set destDir to do shell script "dirname " & quoted form of fullDestPath
	
	do shell script "mkdir -p " & quoted form of destDir
	do shell script "cp -p " & quoted form of originalFile & " " & quoted form of fullDestPath
end repeat

-- Completion dialog
display dialog "Backup completed successfully to Box." buttons {"OK"} default button "OK"
