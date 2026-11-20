#Requires -Version 5.1

<#
.SYNOPSIS
    Validates an existing distribution without rebuilding it.

.DESCRIPTION
    Accepts a package directory (<Output>\<Name>), its distribution\ folder, or a ZIP created
    by build.ps1. Runs the distribution's own verify.ps1 from a temporary copy (so dependencies
    on the build location are detected) and, when the package directory is available, scans for
    references to build-machine paths. Nothing in the distribution is modified.

    Exit codes: 0 passed, 2 invalid input, 3 validation failed.

.PARAMETER Path
    Package directory, distribution directory or ZIP file.
.PARAMETER SkipAppRun
    Do not start the application, even with its recorded safe test option.
.PARAMETER NoTempCopy
    Validate in place instead of from a temporary copy.
.PARAMETER ReportPath
    Write the results as JSON to this file.
.PARAMETER Help
    Shows this help.

.EXAMPLE
    .\verify.ps1 -Path D:\PortableBuilds\E2Reports
.EXAMPLE
    .\verify.ps1 -Path D:\PortableBuilds\DBUserManager-executable-onedir.zip
#>
[CmdletBinding(DefaultParameterSetName = 'Help')]
param(
    [Parameter(ParameterSetName = 'Verify', Mandatory, Position = 0)][string]$Path,
    [Parameter(ParameterSetName = 'Verify')][switch]$SkipAppRun,
    [Parameter(ParameterSetName = 'Verify')][switch]$NoTempCopy,
    [Parameter(ParameterSetName = 'Verify')][string]$ReportPath,
    [Parameter(ParameterSetName = 'Help')][switch]$Help
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ParameterSetName -eq 'Help') { Get-Help $PSCommandPath -Detailed; exit 0 }

foreach ($m in 'Common', 'PackageValidator') { Import-Module (Join-Path $PSScriptRoot "modules\$m.psm1") -Force -DisableNameChecking }
Initialize-PpbLog -VerboseOutput:($VerbosePreference -eq 'Continue')
$exitCode = 0
$temp = $null
try {
    $target = Resolve-PpbPath $Path
    if (-not (Test-Path -LiteralPath $target)) { Stop-PpbWithError "Not found: $target" 2 }
    $buildPaths = @()
    $distDir = $null
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and $target -like '*.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $sha = "$target.sha256"
        if (Test-Path -LiteralPath $sha) {
            $expected = ([System.IO.File]::ReadAllText($sha).Trim() -split '\s+')[0]
            $actual = Get-PpbFileSha256 $target
            if ($expected -ne $actual) { Stop-PpbWithError "ZIP checksum mismatch: expected $expected, got $actual" 3 }
            Write-PpbLog "ZIP checksum matches $([System.IO.Path]::GetFileName($sha))" -Level Success
        }
        $temp = New-PpbTempDirectory -Prefix 'ppb-zip'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($target, $temp)
        $roots = @(Get-ChildItem -LiteralPath $temp -Directory)
        if ($roots.Count -ne 1) { Stop-PpbWithError "The ZIP must contain exactly one top-level folder." 2 }
        $distDir = $roots[0].FullName
        $NoTempCopy = $true   # already a temporary copy
    } elseif (Test-Path -LiteralPath (Join-Path $target 'distribution\verify.ps1')) {
        $distDir = Join-Path $target 'distribution'
        $cfgPath = Join-Path $target 'build-config.json'
        $buildPaths += $target
        if (Test-Path -LiteralPath $cfgPath) {
            $cfg = Read-PpbJsonFile $cfgPath
            $src = [string]$cfg.parameters.Source
            if ($src) { $buildPaths += $(if (Test-Path -LiteralPath $src -PathType Leaf) { Split-Path -Parent $src } else { $src }) }
        }
        $buildPaths += (Get-PpbToolkitRoot)
    } elseif (Test-Path -LiteralPath (Join-Path $target 'verify.ps1')) {
        $distDir = $target
        $buildPaths += (Get-PpbToolkitRoot)
    } else {
        Stop-PpbWithError "'$target' is not a package directory, distribution directory or ZIP created by PythonPortableBuilder." 2
    }

    Write-PpbLog "Verifying $distDir" -Level Step
    $validation = Invoke-PpbDistributionValidation -DistributionPath $distDir -BuildPaths $buildPaths -InTempCopy:(-not $NoTempCopy) -SkipAppRun:$SkipAppRun
    Write-PpbValidationSummary -Validation $validation
    if ($ReportPath) { Write-PpbJsonFile -Path (Resolve-PpbPath $ReportPath) -Data ([ordered]@{ status = $validation.Status; timestampUtc = $validation.TimestampUtc; target = $target; results = $validation.Results }) }
    if ($validation.Status -eq 'failed') { $exitCode = 3 }
} catch {
    $exitCode = Get-PpbErrorExitCode $_
    Write-PpbLog $_.Exception.Message -Level Error
} finally {
    if ($temp) { Remove-PpbItem -Path $temp -AllowTempOwned }
}
exit $exitCode
