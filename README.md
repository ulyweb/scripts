## 🚀Terminal/Powershell/Command Scripts!

These guide provides collective scripts to easily run commands allow for direct repair, access, and configuration file inspection.

> [!NOTE]
> ### Terminal & Powershell

> [!TIP]
> ### 🛠️ Execution Policy Considerations
> #### To ensure the script runs without execution policy restrictions, you can set the execution policy to RemoteSigned or Bypass. This can be done by running the following command in an elevated PowerShell session:
````
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

````

### Backup your data to Box.com
````
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"irm "https://raw.githubusercontent.com/ulyweb/scripts/refs/heads/main/box/OS/win/Backup_Your_Data_to_Box.ps1" | iex"' -Verb RunAs"
````
#
