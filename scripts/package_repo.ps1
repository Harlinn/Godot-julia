# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Packages every file git would push (tracked + untracked, not ignored) into godotJL-<date>-<NNN>.7z.
.DESCRIPTION
    Uses `git ls-files --cached --others --exclude-standard`, so the archive matches the working tree of what a
    commit of all current changes would contain. Submodule contents (native/godot-cpp) are not included, as git
    pushes only their commit reference. NNN is the first unused number for the day (001, 002, ...).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/package_repo.ps1
    powershell -ExecutionPolicy Bypass -File scripts/package_repo.ps1 -OutDir D:\backup
#>
param(
    [string]$OutDir,
    [string]$Name
)

$ErrorActionPreference = 'Stop'

$sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue).Source
if (-not $sevenZip) { $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
if (-not (Test-Path -LiteralPath $sevenZip)) { throw "7-Zip not found (install it or put 7z on PATH)." }

$root = (& git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw "Not inside a git repository." }
$root = [IO.Path]::GetFullPath($root)
if (-not $OutDir) { $OutDir = $root }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $Name) {
    $date = Get-Date -Format 'yyyy-MM-dd'
    $n = 1
    do {
        $Name = 'godotJL-{0}-{1:D3}.7z' -f $date, $n
        $n++
    } while (Test-Path -LiteralPath (Join-Path $OutDir $Name))
}
$archive = Join-Path $OutDir $Name
if (Test-Path -LiteralPath $archive) { throw "$archive already exists." }

Push-Location $root
$oldEncoding = [Console]::OutputEncoding
try {
    # git emits UTF-8 paths; -z avoids quoting of non-ASCII names.
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
    $raw = (& git ls-files -z --cached --others --exclude-standard) -join ''
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed." }
    # Leaf filter drops tracked files deleted from the working tree and submodule directories.
    $files = @($raw -split "`0" | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Sort-Object -Unique)
    if ($files.Count -eq 0) { throw "No files to package." }

    $list = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllLines($list, [string[]]$files, (New-Object Text.UTF8Encoding $false))
        & $sevenZip a -t7z -mx=9 -bso0 -bsp0 -scsUTF-8 $archive "@$list"
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed with exit code $LASTEXITCODE." }
    } finally {
        Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
    }
} finally {
    [Console]::OutputEncoding = $oldEncoding
    Pop-Location
}

$size = (Get-Item -LiteralPath $archive).Length / 1MB
Write-Output ("{0}: {1} files, {2:N1} MB" -f $archive, $files.Count, $size)
