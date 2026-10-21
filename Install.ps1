<#
.SYNOPSIS
    Install the "Paste as symlink" Explorer context-menu verb for the current user.

.DESCRIPTION
    Registers two verbs under HKCU\Software\Classes (no admin needed):
        Directory\shell\...             -> right-click a folder
        Directory\Background\shell\...   -> right-click empty space inside a folder

    Windows 11 shows them under "Show more options" (or Shift+F10).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
#>
$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'SymlinkMenu'
$scriptPath = Join-Path $installDir 'SymlinkMenu.ps1'

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SymlinkMenu.ps1') -Destination $scriptPath -Force

$verbs = @(
    # Right-click a folder: %1 is the clicked folder.
    @{ Key = 'Directory\shell\SymlinkMenu.PasteAsSymlink'; Target = '%1' }
    # Right-click empty space inside a folder: %1 is EMPTY here, %V is the current folder.
    @{ Key = 'Directory\Background\shell\SymlinkMenu.PasteAsSymlink'; Target = '%V' }
)

foreach ($verb in $verbs) {
    $path = Join-Path 'HKCU:\Software\Classes' $verb.Key
    New-Item -Path $path -Force | Out-Null
    Set-Item -Path $path -Value 'Paste as symlink'
    New-ItemProperty -Path $path -Name 'Icon' -Value "$env:SystemRoot\System32\shell32.dll,3" -PropertyType String -Force | Out-Null

    # Target folder is passed positionally: an empty %1/%V must not break parameter binding.
    $command = 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" "{1}"' -f $scriptPath, $verb.Target

    $commandKey = Join-Path $path 'Command'
    New-Item -Path $commandKey -Force | Out-Null
    Set-Item -Path $commandKey -Value $command
}

Write-Host "Installed. Script: $scriptPath"
Write-Host 'Right-click a folder (or empty space in one) > Show more options (Shift+F10) > "Paste as symlink".'
