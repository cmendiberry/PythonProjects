#Requires -Version 5.1

<#
.SYNOPSIS
    Removes build-generated temporary files and caches. Never touches distributions or sources.

.DESCRIPTION
    Removes, for package directories carrying the PythonPortableBuilder ownership marker:
      * <package>\.build\   (virtual environments, staged sources, PyInstaller work files)
    With -IncludeCache, also <OutputRoot>\.ppb-cache\ (downloaded runtimes, shared pip environments).

    Distributions, ZIPs, manifests, logs and source projects are never removed. Directories
    without the ownership marker are skipped. Supports -WhatIf.

.PARAMETER Path
    One package directory (<Output>\<Name>).
.PARAMETER OutputRoot
    An output root: every marked package directory below it is cleaned.
.PARAMETER IncludeCache
    Also remove the runtime/pip cache of the output root.
.PARAMETER Help
    Shows this help.

.EXAMPLE
    .\clean.ps1 -Path D:\PortableBuilds\MonthlyReports
.EXAMPLE
    .\clean.ps1 -OutputRoot D:\PortableBuilds -IncludeCache -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Help')]
param(
    [Parameter(ParameterSetName = 'Package', Mandatory, Position = 0)][string]$Path,
    [Parameter(ParameterSetName = 'Root', Mandatory)][string]$OutputRoot,
    [Parameter(ParameterSetName = 'Root')][switch]$IncludeCache,
    [Parameter(ParameterSetName = 'Help')][switch]$Help
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ParameterSetName -eq 'Help') { Get-Help $PSCommandPath -Detailed; exit 0 }
Import-Module (Join-Path $PSScriptRoot 'modules\Common.psm1') -Force -DisableNameChecking
Initialize-PpbLog

function Clear-PpbPackage([string]$PackageDir) {
    if (-not (Test-PpbOwnershipMarker $PackageDir)) { Write-PpbLog "Skipped (no ownership marker): $PackageDir" -Level Warn; return 0 }
    $work = Join-Path $PackageDir '.build'
    if (-not (Test-Path -LiteralPath $work)) { Write-PpbLog "Nothing to clean: $PackageDir" -Level Info; return 0 }
    if ($PSCmdlet.ShouldProcess($work, 'Remove build work directory')) {
        Remove-PpbItem -Path $work -OwnerRoot $PackageDir
        Write-PpbLog "Removed $work" -Level Success
    }
    return 1
}

try {
    $removed = 0
    if ($PSCmdlet.ParameterSetName -eq 'Package') {
        $pkg = Resolve-PpbPath $Path
        if (-not (Test-Path -LiteralPath $pkg -PathType Container)) { Stop-PpbWithError "Not found: $pkg" 2 }
        if (-not (Test-PpbOwnershipMarker $pkg)) { Stop-PpbWithError "'$pkg' is not a PythonPortableBuilder package directory (ownership marker missing). Nothing was removed." 2 }
        $removed += Clear-PpbPackage $pkg
    } else {
        $root = Resolve-PpbPath $OutputRoot
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { Stop-PpbWithError "Not found: $root" 2 }
        foreach ($d in Get-ChildItem -LiteralPath $root -Directory -Force) {
            if ($d.Name -eq '.ppb-cache') { continue }
            if (Test-PpbOwnershipMarker $d.FullName) { $removed += Clear-PpbPackage $d.FullName }
        }
        if ($IncludeCache) {
            $cache = Join-Path $root '.ppb-cache'
            if (Test-Path -LiteralPath $cache) {
                if (-not (Test-PpbOwnershipMarker $cache)) { Write-PpbLog "Cache '$cache' has no ownership marker; skipped." -Level Warn }
                elseif ($PSCmdlet.ShouldProcess($cache, 'Remove runtime and pip cache')) {
                    foreach ($sub in Get-ChildItem -LiteralPath $cache -Force) {
                        if ($sub.Name -eq '.ppb-owned.json') { continue }
                        Remove-PpbItem -Path $sub.FullName -OwnerRoot $cache
                    }
                    Write-PpbLog "Cleared cache $cache" -Level Success
                    $removed++
                }
            }
        }
    }
    Write-PpbLog "Clean finished ($removed location(s) processed)." -Level Info
    exit 0
} catch {
    Write-PpbLog $_.Exception.Message -Level Error
    exit (Get-PpbErrorExitCode $_)
}
