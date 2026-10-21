# SymlinkMenu

Windows 11 Explorer context-menu entry: **copy files/folders, paste them as symlinks**.

Bulk, mixed files + folders, works like the native `Paste` / `Paste as shortcut` flow.

## Install

Double-click **`Install.bat`** (no admin needed, current user only), or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Registers the verb for the current user (`HKCU\Software\Classes`) — no admin needed.
The script is copied to `%LOCALAPPDATA%\SymlinkMenu\SymlinkMenu.ps1`.

## Use

1. Select one or more files **and/or** folders in Explorer.
2. `Ctrl+C`.
3. Right-click the target:
   - **on the folder** → links are created *inside* it, or
   - **on empty space inside the folder** → same, the folder under the cursor is used.
4. `Show more options` (or hold `Shift` + right-click / `Shift+F10`) → **Paste as symlink**.

Two registry verbs are registered, because Explorer passes the selected folder as `%1` when you
right-click a folder, but leaves it empty when you right-click *inside* one (that case uses `%V`).

A summary window lists what was created. On name conflicts the link becomes `name (2).txt`,
exactly like Explorer does.

> Windows 11 only shows custom verbs under **Show more options**. A top-level entry in the
> modern menu needs a compiled shell extension (not included).

## Symlinks vs. the fallback

A real symbolic link needs **admin** or **Developer Mode**
(`Settings > System > For developers > Developer Mode`). Without it the script falls back:

| Source | Fallback | Needs |
| --- | --- | --- |
| Folder | Junction (`mklink /J`) | nothing, local absolute targets only |
| File | Hard link (`mklink /H`) | nothing, same volume only |

The summary window states which kind was created. Nothing is silently downgraded.

## Files

| File | Purpose |
| --- | --- |
| `SymlinkMenu.ps1` | The logic: read clipboard → create links → summarize. Target folder is the first positional argument, `-NoUI` for scripts. |
| `Install.bat` / `Uninstall.bat` | One-click install / uninstall. |
| `Install.ps1` | Copies the script to `%LOCALAPPDATA%` and writes the two registry verbs. |
| `Uninstall.ps1` | Removes the registry verbs and the local folder. |
| `Test-SymlinkMenu.ps1` | Self-check: copies a file + folder to the clipboard, runs the script, asserts the links. |

## Self-check

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-SymlinkMenu.ps1
```

Overwrites the current clipboard contents.

## Uninstall

Double-click **`Uninstall.bat`**, or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

If the menu entry lingers, restart Explorer: `Stop-Process -Name explorer -Force`.

## Limits

- Junctions need a local absolute target (no UNC), hard links need the same volume.
- Relative-path symlinks and symlink target editing are not implemented.
- The verb is not on the Desktop background; right-click the Desktop folder instead.
