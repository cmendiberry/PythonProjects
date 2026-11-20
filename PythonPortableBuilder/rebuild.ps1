#Requires -Version 5.1

<#
.SYNOPSIS
    Rebuilds an existing package with its saved build configuration.

.DESCRIPTION
    Reads <Output>\<Name>\build-config.json (written by build.ps1; it contains only the
    parameters given explicitly on the command line) and runs build.ps1 again with the same
    parameters and the same output root. Any build.ps1 parameter passed here overrides the
    saved value, e.g. a new -PythonVersion or a moved -Source.

.PARAMETER Path
    Package directory (<Output>\<Name>) or the path of its build-config.json.
.PARAMETER Clean
    Recreate the build environments (recommended after dependency changes).
.PARAMETER Override
    Hashtable of build.ps1 parameters that replace saved values, e.g. @{ PythonVersion = '3.12' }.
.PARAMETER Help
    Shows this help.

.EXAMPLE
    .\rebuild.ps1 -Path D:\PortableBuilds\MonthlyReports
.EXAMPLE
    .\rebuild.ps1 -Path D:\PortableBuilds\MonthlyReports -Clean -Override @{ Source = 'E:\moved\reports' }
#>
[CmdletBinding(DefaultParameterSetName = 'Help')]
param(
    [Parameter(ParameterSetName = 'Rebuild', Mandatory, Position = 0)][string]$Path,
    [Parameter(ParameterSetName = 'Rebuild')][switch]$Clean,
    [Parameter(ParameterSetName = 'Rebuild')][hashtable]$Override,
    [Parameter(ParameterSetName = 'Help')][switch]$Help
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ParameterSetName -eq 'Help') { Get-Help $PSCommandPath -Detailed; exit 0 }
Import-Module (Join-Path $PSScriptRoot 'modules\Common.psm1') -Force -DisableNameChecking
Initialize-PpbLog

try {
    $full = Resolve-PpbPath $Path
    $cfgPath = if (Test-Path -LiteralPath $full -PathType Leaf) { $full } else { Join-Path $full 'build-config.json' }
    if (-not (Test-Path -LiteralPath $cfgPath)) { Stop-PpbWithError "No build-config.json found at '$cfgPath'. Only packages created by build.ps1 can be rebuilt." 2 }
    $packageDir = Split-Path -Parent $cfgPath
    if (-not (Test-PpbOwnershipMarker $packageDir)) { Stop-PpbWithError "'$packageDir' is not marked as a PythonPortableBuilder package directory." 2 }
    $saved = Read-PpbJsonFile $cfgPath
    $params = @{}
    foreach ($p in $saved.parameters.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [System.Object[]]) { $v = [string[]]$v }
        $params[$p.Name] = $v
    }
    if ($Override) { foreach ($k in $Override.Keys) { $params[$k] = $Override[$k] } }
    $params['Output'] = Split-Path -Parent $packageDir
    if ($Clean) { $params['Clean'] = $true }
    if ($VerbosePreference -eq 'Continue') { $params['Verbose'] = $true }
    foreach ($k in @($params.Keys)) {
        if ($params[$k] -is [bool] -and $k -notin 'CreateZip', 'Verify') { $params[$k] = [System.Management.Automation.SwitchParameter]$params[$k] }
    }
    if (-not (Test-Path -LiteralPath $params['Source'])) { Stop-PpbWithError "The saved source '$($params['Source'])' no longer exists. Pass -Override @{ Source = '<new path>' }." 2 }
    Write-Host "Rebuilding '$($params['Name'])' from $cfgPath (saved by toolkit $($saved.toolkitVersion))" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build.ps1') @params
    exit $LASTEXITCODE
} catch {
    Write-PpbLog $_.Exception.Message -Level Error
    exit (Get-PpbErrorExitCode $_)
}
