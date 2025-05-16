-- Initialize the list of folders to back up
set sourceFolders to {}

-- Keep asking user to select folders until they choose to stop
repeat
	set selectedFolder to choose folder with prompt "Select a folder to back up:"
	set end of sourceFolders to selectedFolder
	set addAnother to button returned of (display dialog "Do you want to add another folder?" buttons {"No", "Yes"} default button "Yes")
	if addAnother is "No" then exit repeat
end repeat

-- Define Box backup destination
set homePath to (POSIX path of (path to home folder))
set boxBackupRoot to homePath & "Library/CloudStorage/Box-Box/01. My Personal/recentBackup/"
set backupName to "Backup_" & do shell script "date +%Y-%m-%d_%H%M"
set destinationPath to boxBackupRoot & backupName

-- Create destination directory
do shell script "mkdir -p " & quoted form of destinationPath

-- Initialize counters
set totalFiles to 0
set totalSize to 0
set fileList to {}

-- Build file list from all folders
repeat with aFolder in sourceFolders
	set folderPath to POSIX path of aFolder
	set findCommand to "find " & quoted form of folderPath & " -type f"
	set filePaths to paragraphs of (do shell script findCommand)
	
	repeat with aFile in filePaths
		set end of fileList to {filePath:aFile, baseFolder:folderPath}
		set totalFiles to totalFiles + 1
		try
			set sizeStr to do shell script "stat -f%z " & quoted form of aFile
			set totalSize to totalSize + (sizeStr as number)
		end try
	end repeat
end repeat

-- Show totals and ask to continue
set totalSizeMB to (totalSize / 1024 / 1024)
set roundedSize to ((round (totalSizeMB * 100)) / 100)

set theResponse to display dialog "Total files: " & totalFiles & return & "Total size: " & roundedSize & " MB" & return & return & "Start copying to Box?" buttons {"Cancel", "Yes"} default button "Yes"
if button returned of theResponse is "Cancel" then
	display dialog "Backup cancelled." buttons {"OK"} default button "OK"
	return
end if

-- Perform the backup copy
repeat with itemInfo in fileList
	set originalFile to filePath of itemInfo
	set baseFolder to baseFolder of itemInfo
	
	set relPath to do shell script "python3 -c \"import os; print(os.path.relpath(" & quoted form of originalFile & ", " & quoted form of baseFolder & "))\""
	set fullDestPath to destinationPath & "/" & relPath
	set destDir to do shell script "dirname " & quoted form of fullDestPath
	
	do shell script "mkdir -p " & quoted form of destDir
	do shell script "cp -p " & quoted form of originalFile & " " & quoted form of fullDestPath
end repeat

-- Done
display dialog "Backup completed successfully to Box." buttons {"OK"} default button "OK"
