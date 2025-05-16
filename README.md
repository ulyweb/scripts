## 🚀Terminal/Powershell/Command Scripts!

These guide provides collective scripts to easily run commands allow for direct repair, access, and configuration file inspection.

> [!NOTE]
> ### Terminal & Powershell
> 

### Backup your data to Box.com
````
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"irm "https://raw.githubusercontent.com/ulyweb/scripts/refs/heads/main/box/OS/win/Backup_your_data_to_box.ps1" | iex"' -Verb RunAs"
````
