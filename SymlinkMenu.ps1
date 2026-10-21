<#
.SYNOPSIS
    Create symlinks in a target folder for every file/folder on the Explorer clipboard.

.DESCRIPTION
    Invoked by the "Paste as symlink" Explorer context-menu verb:
        powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File SymlinkMenu.ps1 "<folder>"

    Works on the whole clipboard selection at once (bulk), for files and folders mixed.
    Real symlinks need admin or Developer Mode; without it the script falls back to
    a junction (folders) or a hard link (files, same volume only) and says so.

.EXAMPLE
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\SymlinkMenu.ps1 "D:\Links"
#>
param(
    # Target folder the links are created in. Positional so an empty Explorer argument
    # ("" gets dropped by the command line) still binds instead of failing to parse.
    [Parameter(Position = 0)]
    [string]$Target = '',

    # Suppress the summary window (used by the self-check).
    [switch]$NoUI
)

$ErrorActionPreference = 'Stop'

$SYMLINK_FLAG_DIRECTORY        = 0x1
$SYMLINK_FLAG_ALLOW_UNPRIVILEGED = 0x2

if (-not ('SymlinkNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class SymlinkNative
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateSymbolicLink(string link, string target, int flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateHardLink(string link, string existing, IntPtr attributes);
}
'@
}

function Show-Message {
    param([string]$Text, [string]$Title = 'Symlink Menu', [string]$Icon = 'Information')

    if ($NoUI) {
        Write-Host $Text
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    $boxIcon = switch ($Icon) {
        'Error'   { [System.Windows.Forms.MessageBoxIcon]::Error }
        'Warning' { [System.Windows.Forms.MessageBoxIcon]::Warning }
        default   { [System.Windows.Forms.MessageBoxIcon]::Information }
    }
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $boxIcon) | Out-Null
}

function Get-ClipboardPaths {
    # Explorer stores a FileDropList on the clipboard; read it as real paths.
    try {
        $paths = @()
        foreach ($item in (Get-Clipboard -Format FileDropList -ErrorAction Stop)) {
            if ($item.FullName) { $paths += $item.FullName }
        }
        if ($paths.Count -gt 0) { return $paths }
    } catch {
        # fall through to the WinForms clipboard
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $drop = [System.Windows.Forms.Clipboard]::GetFileDropList()
        $paths = @($drop | ForEach-Object { $_.FullName } | Where-Object { $_ })
        if ($paths.Count -gt 0) { return $paths }
    } catch {
    }

    return @()
}

function Get-UniqueLinkPath {
    param([string]$Dir, [string]$Name, [System.Collections.Generic.HashSet[string]]$Taken)

    if (-not $Taken.Contains($Name)) { return (Join-Path $Dir $Name) }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $ext  = [System.IO.Path]::GetExtension($Name)
    for ($i = 2; $i -le 999; $i++) {
        $candidate = '{0} ({1}){2}' -f $base, $i, $ext
        if (-not $Taken.Contains($candidate)) { return (Join-Path $Dir $candidate) }
    }
    throw "Could not find a free name for '$Name'"
}

function New-Link {
    # Returns 'Symlink', 'Junction' or 'HardLink'; throws when nothing could be created.
    param([string]$Source, [string]$Link)

    $item = Get-Item -LiteralPath $Source -Force
    $isDir = $item.PSIsContainer

    $flags = $SYMLINK_FLAG_ALLOW_UNPRIVILEGED
    if ($isDir) { $flags = $flags -bor $SYMLINK_FLAG_DIRECTORY }

    if ([SymlinkNative]::CreateSymbolicLink($Link, $item.FullName, $flags)) {
        return 'Symlink'
    }
    $symlinkError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if ($isDir) {
        # Junctions need no privileges, but only work for local absolute targets.
        try {
            New-Item -ItemType Junction -Path $Link -Target $item.FullName -ErrorAction Stop | Out-Null
            return 'Junction'
        } catch {
            throw "symlink failed (Win32 $symlinkError); junction failed: $($_.Exception.Message)"
        }
    }

    if ([SymlinkNative]::CreateHardLink($Link, $item.FullName, [IntPtr]::Zero)) {
        return 'HardLink'
    }
    $hardLinkError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "symlink failed (Win32 $symlinkError); hard link failed (Win32 $hardLinkError)"
}

# --- main ----------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Target)) {
    Show-Message 'No target folder was passed to SymlinkMenu.' -Icon 'Error'
    exit 2
}

if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Show-Message "Target folder not found:`n$Target" -Icon 'Error'
    exit 2
}
$Target = (Get-Item -LiteralPath $Target -Force).FullName

$sources = @(Get-ClipboardPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
if ($sources.Count -eq 0) {
    Show-Message 'Clipboard has no files or folders to paste.' -Icon 'Warning'
    exit 2
}

$taken = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($Target)) {
    [void]$taken.Add([System.IO.Path]::GetFileName($entry))
}

$results = @()
foreach ($source in $sources) {
    $name = Split-Path -Leaf $source
    try {
        $link = Get-UniqueLinkPath -Dir $Target -Name $name -Taken $taken
        $type = New-Link -Source $source -Link $link
        [void]$taken.Add([System.IO.Path]::GetFileName($link))
        $results += [pscustomobject]@{ Name = $name; Type = $type; Detail = '' }
    } catch {
        $results += [pscustomobject]@{ Name = $name; Type = 'Failed'; Detail = $_.Exception.Message }
    }
}

$ok = @($results | Where-Object { $_.Type -ne 'Failed' })
$bad = @($results | Where-Object { $_.Type -eq 'Failed' })

$lines = @()
if ($ok.Count -gt 0) {
    $lines += "Created $($ok.Count) link(s) in $Target`n"
    foreach ($r in $ok) { $lines += ('  {0,-9} {1}' -f $r.Type, $r.Name) }
}
if ($bad.Count -gt 0) {
    if ($ok.Count -gt 0) { $lines += '' }
    $lines += "Failed $($bad.Count):"
    foreach ($r in $bad) { $lines += "  $r.Name - $($r.Detail)" }
}
if ($ok.Count -gt 0 -and ($ok.Type | Where-Object { $_ -ne 'Symlink' })) {
    $lines += ''
    $lines += 'Symlink needs admin or Developer Mode; junctions/hard links were used instead.'
}

Show-Message ($lines -join "`n") -Icon $(if ($bad.Count -gt 0) { 'Warning' } else { 'Information' })

if ($bad.Count -gt 0) { exit 1 }
exit 0
