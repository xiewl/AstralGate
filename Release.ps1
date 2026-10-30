# Run with: powershell -ExecutionPolicy Bypass -File .\Release.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$addonRoot = $PSScriptRoot
$tocPath = Join-Path $addonRoot 'AstralGate.toc'
$outputDirectory = Join-Path $addonRoot 'dist'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$originalToc = [System.IO.File]::ReadAllText($tocPath)
$versionPattern = '(?m)^(## Version:\s*)(\d+)\.(\d+)\.(\d+)([ \t]*)(\r?)$'
$versionMatches = [regex]::Matches($originalToc, $versionPattern)
if ($versionMatches.Count -ne 1) {
    throw 'Expected exactly one TOC version in major.minor.patch format.'
}
$versionMatch = $versionMatches[0]
$newVersion = '{0}.{1}.{2}' -f $versionMatch.Groups[2].Value, $versionMatch.Groups[3].Value, ([long]::Parse($versionMatch.Groups[4].Value) + 1)
$newToc = $originalToc.Substring(0, $versionMatch.Index) + $versionMatch.Groups[1].Value + $newVersion + $versionMatch.Groups[5].Value + $versionMatch.Groups[6].Value + $originalToc.Substring($versionMatch.Index + $versionMatch.Length)
$zipPath = Join-Path $outputDirectory ("AstralGate-{0}.zip" -f $newVersion)
if (Test-Path -LiteralPath $zipPath) { throw "Archive already exists: $zipPath" }

# Package runtime folders and root documentation only; exclude scripts, Git and old archives.
$runtimeDirectories = @('Art', 'Core', 'Data', 'Libs', 'Locales', 'Services', 'UI')
$files = @()
foreach ($directory in $runtimeDirectories) {
    $directoryPath = Join-Path $addonRoot $directory
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) { throw "Missing runtime directory: $directory" }
    $files += Get-ChildItem -LiteralPath $directoryPath -File -Recurse
}
$files += Get-ChildItem -LiteralPath $addonRoot -File | Where-Object { $_.Name -match '^(README|LICENSE|CHANGELOG)' -or $_.Extension -eq '.lua' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$temporaryZip = Join-Path $outputDirectory ([guid]::NewGuid().ToString() + '.tmp')
$tocWritten = $false
try {
    $stream = [System.IO.File]::Open($temporaryZip, [System.IO.FileMode]::CreateNew)
    $archive = New-Object System.IO.Compression.ZipArchive($stream, ([System.IO.Compression.ZipArchiveMode]::Create), $false)
    try {
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($addonRoot.Length).TrimStart('\', '/').Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, ('AstralGate/' + $relativePath), [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
        $entry = $archive.CreateEntry('AstralGate/AstralGate.toc')
        $writer = New-Object System.IO.StreamWriter($entry.Open(), $utf8)
        try { $writer.Write($newToc) } finally { $writer.Dispose() }
    } finally { $archive.Dispose(); $stream.Dispose() }
    [System.IO.File]::WriteAllText($tocPath, $newToc, $utf8)
    $tocWritten = $true
    Move-Item -LiteralPath $temporaryZip -Destination $zipPath -ErrorAction Stop
} catch {
    if ($tocWritten) { [System.IO.File]::WriteAllText($tocPath, $originalToc, $utf8) }
    if (Test-Path -LiteralPath $temporaryZip) { Remove-Item -LiteralPath $temporaryZip }
    throw
}
Write-Host "Version: $newVersion"
Write-Host "Archive: $zipPath"

