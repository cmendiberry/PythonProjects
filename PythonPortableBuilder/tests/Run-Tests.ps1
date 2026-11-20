#Requires -Version 5.1

<#
.SYNOPSIS
    Runs the PythonPortableBuilder test suite.

.DESCRIPTION
    * Python unit tests (unittest) for the analyzer and inspection helpers
    * Pester 5 unit tests for the PowerShell modules
    * With -Integration: end-to-end builds (needs internet access to python.org and PyPI,
      takes several minutes). Builds go to a temporary directory that is removed afterwards.

    Pester 5 is required. Windows ships Pester 3.4, which is NOT compatible. Install it with
        Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck
    or point -PesterPath to a folder containing Pester\<version>\Pester.psd1.

.PARAMETER Integration
    Also run the integration tests.
.PARAMETER PesterPath
    Directory that contains a Pester 5 module (added to PSModulePath for this run).
.PARAMETER Output
    Pester output verbosity: None, Normal, Detailed, Diagnostic.

.EXAMPLE
    .\tests\Run-Tests.ps1
.EXAMPLE
    .\tests\Run-Tests.ps1 -Integration -Output Detailed
#>
[CmdletBinding()]
param(
    [switch]$Integration,
    [string]$PesterPath,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')][string]$Output = 'Normal'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = 0

if ($PesterPath) { $env:PSModulePath = (Resolve-Path $PesterPath).Path + [IO.Path]::PathSeparator + $env:PSModulePath }
$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.3' } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 5.3+ is required. Install it with:' -ForegroundColor Red
    Write-Host '  Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck' -ForegroundColor Yellow
    exit 2
}
Import-Module $pester.Path -Force

Write-Host '==> Python unit tests' -ForegroundColor Cyan
$python = (Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $python) { Write-Host 'python.exe not found on PATH' -ForegroundColor Red; exit 2 }
& $python.Source -B -m unittest discover -s (Join-Path $root 'tests\unit') -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) { $failures++ }

Write-Host '==> PowerShell tests' -ForegroundColor Cyan
$paths = @(Join-Path $root 'tests\unit')
if ($Integration) { $paths += (Join-Path $root 'tests\integration') }
$cfg = New-PesterConfiguration
$cfg.Run.Path = $paths
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = $Output
$result = Invoke-Pester -Configuration $cfg
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { $failures++ }

Write-Host ''
if ($failures) { Write-Host 'TEST SUITE FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.' -ForegroundColor Green
exit 0
