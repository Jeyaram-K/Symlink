<#
.SYNOPSIS
    Remove the "Paste as symlink" context-menu verbs and the local install folder.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
#>
$ErrorActionPreference = 'Stop'

$verbs = @(
    'HKCU:\Software\Classes\Directory\shell\SymlinkMenu.PasteAsSymlink',
    'HKCU:\Software\Classes\Directory\Background\shell\SymlinkMenu.PasteAsSymlink'
)

foreach ($verb in $verbs) {
    if (Test-Path -LiteralPath $verb) {
        Remove-Item -LiteralPath $verb -Recurse -Force
    }
}

$installDir = Join-Path $env:LOCALAPPDATA 'SymlinkMenu'
$scriptPath = Join-Path $installDir 'SymlinkMenu.ps1'
if (Test-Path -LiteralPath $scriptPath) {
    Remove-Item -LiteralPath $scriptPath -Force
}
if (Test-Path -LiteralPath $installDir) {
    $left = @(Get-ChildItem -LiteralPath $installDir -Force)
    if ($left.Count -eq 0) {
        Remove-Item -LiteralPath $installDir -Force
    } else {
        # Foreign files (e.g. a loaded shell extension DLL) are not ours to delete.
        Write-Host "Left in $installDir : $($left.Name -join ', ')"
    }
}

Write-Host 'Uninstalled. Explorer can be restarted with: Stop-Process -Name explorer -Force'
