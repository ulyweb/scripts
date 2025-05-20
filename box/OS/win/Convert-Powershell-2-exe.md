## ✅ PART 1: Convert PowerShell Script to `.exe`

We’ll use **PS2EXE** — a trusted PowerShell script-to-EXE compiler available from the PowerShell Gallery.

---

### 🔧 Step-by-Step Instructions

#### 🧱 Step 1: Install `ps2exe` module

Open **PowerShell (as Current User — not admin)** and run:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force
```

If prompted to trust the repository, type `Y`.

---

#### 🧱 Step 2: Convert your script to `.exe`

Assuming your script is saved as:

```
C:\Scripts\Backup_your_data_to_box.ps1
```

Then use this command to convert it:

```powershell
Invoke-ps2exe -InputFile "C:\Scripts\Backup_your_data_to_box.ps1" `
              -OutputFile "C:\Scripts\Backup_your_data_to_box.exe" `
              -Title "Box Backup Tool" `
              -IconFile "C:\Windows\System32\shell32.dll" `
              -NoConsole:$false `
              -Verbose
```

> 💡 The `-NoConsole:$false` ensures that users **can see the output window** and interact with `Read-Host`.

You can change the icon using any `.ico` file if you like.

---

#### 🧪 Step 3: Test the EXE

Now double-click the `.exe` file or run it in PowerShell or cmd:

```bash
C:\Scripts\Backup_your_data_to_box.exe
```

It should:

* Prompt for folder(s)
* Backup the files to Box Drive
* Show log and results
* Wait for Enter key before closing

---

### ⚠️ Notes

* The `.exe` will run independently, and **you don’t need PowerShell open**.
* Make sure users’ machines have PowerShell 5.1+ (included in all modern Windows).
* The `ps2exe` tool **embeds** your script into an `.exe` wrapper using .NET.

---

### 🗃️ Optional: Create an icon `.ico` file?

If you want a custom icon for branding, I can help generate a `.ico` for you.

---


### ❌ Root Cause:

The error is:

```
Error reading icon 'c:\Windows\System32\shell32.dll' -- The data is invalid.
```

That’s because:

> `shell32.dll` is a **Windows system DLL file**, not an actual `.ico` (icon) file.

The `ps2exe` tool expects a valid **`.ico` file**, not a `.dll`.

---

## ✅ Solution: Use a Proper `.ico` File

### Option 1: Use a Valid `.ico` File

If you already have an icon file (e.g., `backup.ico`), use this instead:

```powershell
Invoke-ps2exe -InputFile "C:\VSC\draft\User-Backup2box.ps1" `
              -OutputFile "C:\VSC\draft\User-Backup2box.exe" `
              -Title "Box Backup Tool" `
              -IconFile "C:\Path\To\Your\backup.ico" `
              -NoConsole:$false `
              -Verbose
```

---

### Option 2: Remove Icon (for now)

If you don’t need an icon yet, simply omit the `-IconFile` flag:

```powershell
Invoke-ps2exe -InputFile "C:\VSC\draft\User-Backup2box.ps1" `
              -OutputFile "C:\VSC\draft\User-Backup2box.exe" `
              -Title "Box Backup Tool" `
              -NoConsole:$false `
              -Verbose
```

✅ This will compile successfully and run fine.

---

### Option 3: Extract `.ico` from `shell32.dll` (advanced)

If you really want an icon from `shell32.dll`, you'd first extract it into an `.ico` file using a tool like **IcoFX** or **Resource Hacker**, and then pass that `.ico` file to `-IconFile`.

---

