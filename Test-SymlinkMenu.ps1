<#
.SYNOPSIS
    Self-check for SymlinkMenu.ps1.

.DESCRIPTION
    Copies a file and a folder to the clipboard, runs SymlinkMenu.ps1 against a
    target folder, and asserts the links were created (bulk + name-conflict case).
    Note: this overwrites the current clipboard contents.

.EXAMPLE
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-SymlinkMenu.ps1
#>
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$script = Join-Path $PSScriptRoot 'SymlinkMenu.ps1'
Assert-True (Test-Path -LiteralPath $script) "SymlinkMenu.ps1 not found next to this test"

$root = Join-Path $env:TEMP ('SymlinkMenuTest_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$src  = Join-Path $root 'src'
$dst  = Join-Path $root 'dst'
New-Item -ItemType Directory -Path (Join-Path $src 'data') -Force | Out-Null
New-Item -ItemType Directory -Path $dst -Force | Out-Null

try {
    $file = Join-Path $src 'file.txt'
    Set-Content -LiteralPath $file -Value 'hello' -NoNewline
    Set-Content -LiteralPath (Join-Path $src 'data\inner.txt') -Value 'inner' -NoNewline

    # Name conflict: the target already has a "file.txt", so the link must become "file (2).txt".
    Set-Content -LiteralPath (Join-Path $dst 'file.txt') -Value 'existing' -NoNewline

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetFileDropList([string[]]@($file, (Join-Path $src 'data')))

    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $script -Target $dst -NoUI | Out-Null
    $exit = $LASTEXITCODE
    Assert-True ($exit -eq 0) "script exit code was $exit (expected 0)"

    $linkFile = Join-Path $dst 'file (2).txt'
    Assert-True (Test-Path -LiteralPath $linkFile) "conflict link 'file (2).txt' was not created"
    Assert-True ((Get-Content -LiteralPath $linkFile -Raw) -eq 'hello') "link content does not match source"

    $linkDir = Join-Path $dst 'data'
    Assert-True (Test-Path -LiteralPath $linkDir -PathType Container) "folder link 'data' was not created"
    Assert-True (Test-Path -LiteralPath (Join-Path $linkDir 'inner.txt')) "folder link does not expose source content"

    $dirItem = Get-Item -LiteralPath $linkDir -Force
    Assert-True ($dirItem.LinkType -in @('SymbolicLink', 'Junction')) "folder link type is '$($dirItem.LinkType)'"

    # Explorer passes the folder as %1 (right-click a folder) or %V (right-click inside it).
    # An empty argument must fail cleanly, not with a parameter-binding error.
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $script "" -NoUI | Out-Null
    Assert-True ($LASTEXITCODE -eq 2) "empty target exit code was $LASTEXITCODE (expected 2)"

    Write-Host 'PASS: bulk file+folder links created, conflict naming works.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
