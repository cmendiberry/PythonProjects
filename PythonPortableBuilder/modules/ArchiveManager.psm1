#Requires -Version 5.1
<#
    ArchiveManager.psm1 - checksums and ZIP distributions.

      * SHA256SUMS inside the distribution (verified by verify.ps1)
      * <Name>-<type>[-<mode>].zip with a single top-level <Name>\ folder
      * <zip>.sha256 next to the ZIP
      * existing ZIPs are only replaced when this toolkit created them
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Get-PpbZipFileName {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Type, [string]$Mode)
    if ($Type -eq 'executable') { return "$Name-executable-$Mode.zip" }
    return "$Name-embedded.zip"
}

<#
.SYNOPSIS
    Writes SHA256SUMS (GNU format, '/' separators) for all files except the excluded ones.
#>
function New-PpbChecksumFile {
    param([Parameter(Mandatory)][string]$Root, [string[]]$Exclude = @('SHA256SUMS', 'build-manifest.json'))
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
        $rel = (Get-PpbRelativePath -Path $f.FullName -BasePath $Root).Replace('\', '/')
        if ($Exclude -contains $rel) { continue }
        $lines.Add(("{0} *{1}" -f (Get-PpbFileSha256 $f.FullName), $rel))
    }
    Write-PpbTextFile -Path (Join-Path $Root 'SHA256SUMS') -Content (($lines -join "`n") + "`n")
    return $lines.Count
}

function Get-PpbDirectoryStatistics {
    param([Parameter(Mandatory)][string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force)
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    return [ordered]@{ files = $files.Count; sizeBytes = [long]$(if ($size) { $size } else { 0 }) }
}

<#
.SYNOPSIS
    Creates the deployment ZIP and its .sha256 file. Returns artifact information.
#>
function New-PpbDistributionZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistributionPath,
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$RootFolderName,
        [Parameter(Mandatory)][string]$PackageDirectory
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipName = Split-Path -Leaf $ZipPath
    $shaPath = "$ZipPath.sha256"
    $marker = Read-PpbOwnershipMarker $PackageDirectory
    $owned = $marker -and @($marker['artifacts']) -contains $zipName
    foreach ($p in $ZipPath, $shaPath) {
        if (Test-Path -LiteralPath $p) {
            if (-not $owned) { Stop-PpbWithError "'$p' already exists and was not created by this package's builds. Move or delete it, or choose another -Output." 2 }
            Remove-Item -LiteralPath $p -Force
        }
    }
    # Register before writing so an interrupted build can still overwrite its own partial ZIP.
    Write-PpbOwnershipMarker -Directory $PackageDirectory -PackageName $RootFolderName -Artifacts @($zipName)

    $partial = "$ZipPath.partial"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    $count = 0
    $stream = [System.IO.File]::Open($partial, [System.IO.FileMode]::CreateNew)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in (Get-ChildItem -LiteralPath $DistributionPath -Recurse -File -Force | Sort-Object FullName)) {
                $rel = (Get-PpbRelativePath -Path $f.FullName -BasePath $DistributionPath).Replace('\', '/')
                [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, "$RootFolderName/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
                $count++
            }
            # Keep empty directories (e.g. packages\ without dependencies, logs\) as explicit entries.
            foreach ($d in (Get-ChildItem -LiteralPath $DistributionPath -Recurse -Directory -Force | Sort-Object FullName)) {
                if (@(Get-ChildItem -LiteralPath $d.FullName -Force | Select-Object -First 1).Count -eq 0) {
                    $rel = (Get-PpbRelativePath -Path $d.FullName -BasePath $DistributionPath).Replace('\', '/')
                    [void]$zip.CreateEntry("$RootFolderName/$rel/")
                }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    Move-Item -LiteralPath $partial -Destination $ZipPath -Force

    # Verify the archive: readable, same number of files, required top folder.
    $check = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = @($check.Entries | Where-Object { $_.FullName -notlike '*/' })
        if ($entries.Count -ne $count) { Stop-PpbWithError "ZIP verification failed: $($entries.Count) entries, expected $count." }
        $bad = @($entries | Where-Object { -not $_.FullName.StartsWith("$RootFolderName/") })
        if ($bad.Count) { Stop-PpbWithError "ZIP verification failed: entries outside '$RootFolderName/'." }
    } finally { $check.Dispose() }

    $sha = Get-PpbFileSha256 $ZipPath
    Write-PpbTextFile -Path $shaPath -Content "$sha *$zipName`n"
    Write-PpbOwnershipMarker -Directory $PackageDirectory -PackageName $RootFolderName -Artifacts @($zipName, "$zipName.sha256")
    return [ordered]@{ name = $zipName; sha256 = $sha; sizeBytes = (Get-Item -LiteralPath $ZipPath).Length; files = $count; rootFolder = $RootFolderName }
}

Export-ModuleMember -Function Get-PpbZipFileName, New-PpbChecksumFile, Get-PpbDirectoryStatistics, New-PpbDistributionZip
