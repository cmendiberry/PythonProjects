#Requires -Version 5.1
<#
    ProjectAnalyzer.psm1 - inspects the source project.

    Static analysis is delegated to python/ppb_analyzer.py (AST based; it never
    executes project code). This module runs it, interprets the result, and
    turns analysis errors (ambiguous or missing entry point, invalid metadata)
    into clear, actionable build errors.
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

<#
.SYNOPSIS
    Reads the optional per-project configuration file ppb.json from the project root.
#>
function Get-PpbProjectConfig {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'ppb.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [ordered]@{} }
    Write-PpbLog "Using project configuration: ppb.json" -Level Info
    $cfg = ConvertTo-PpbHashtable (Read-PpbJsonFile $path)
    $allowed = 'name', 'type', 'mode', 'entryPoint', 'pythonVersion', 'requirements', 'architecture', 'include', 'exclude',
        'hiddenImports', 'dataFiles', 'additionalPaths', 'windowed', 'icon', 'safeTestArgs', 'workingDirectory',
        'externalPrerequisites', 'collectPackages', 'specFile', '$schema', 'comment'
    foreach ($k in @($cfg.Keys)) {
        if ($allowed -notcontains $k) { Write-PpbLog "ppb.json: unknown key '$k' ignored." -Level Warn }
    }
    return $cfg
}

<#
.SYNOPSIS
    Runs the static analyzer and returns the parsed report.
#>
function Invoke-PpbProjectAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$PythonExe,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$EntryPoint,
        [string[]]$Include
    )
    $analyzer = Join-Path (Get-PpbToolkitRoot) 'python\ppb_analyzer.py'
    $pyArgs = @('-I', '-B', '-X', 'utf8', $analyzer, '--source', $Source, '--output', $ReportPath)
    if ($EntryPoint) { $pyArgs += @('--entry-point', $EntryPoint) }
    foreach ($d in $Config['excludeDirectories']) {
        # Directories explicitly re-included by -Include are analysed as well.
        if ($Include -and (Test-PpbGlobMatch -RelativePath $d -Patterns $Include)) { continue }
        $pyArgs += @('--exclude-dir', $d)
    }
    foreach ($d in $Config['excludeDirectoryPatterns']) { $pyArgs += @('--exclude-dir-pattern', $d) }

    $result = Invoke-PpbProcess -FilePath $PythonExe -ArgumentList $pyArgs -Quiet -TimeoutSeconds 600 -Description 'Running static project analysis'
    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ReportPath)) {
        Stop-PpbWithError "Project analysis failed (exit $($result.ExitCode)): $($result.StdErr)"
    }
    $report = Read-PpbJsonFile $ReportPath
    return $report
}

<#
.SYNOPSIS
    Converts analyzer errors into build errors with actionable messages.
#>
function Assert-PpbAnalysisUsable {
    param([Parameter(Mandatory)]$Report)
    $errors = @(Get-PpbValue $Report 'errors' @())
    if ($errors.Count -eq 0) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    $exitCode = 2
    foreach ($e in $errors) {
        $lines.Add("$($e.message)")
        if ($e.code -eq 'ambiguous-entry-point') {
            foreach ($c in @($e.candidates)) { $lines.Add("    -EntryPoint `"$($c.value)`"    ($($c.reason))") }
        }
        if ($e.code -eq 'analyzer-crash') { $exitCode = 1; $lines.Add((Get-PpbValue $e 'traceback' '')) }
    }
    foreach ($l in $lines) { Write-PpbLog $l -Level Error }
    Stop-PpbWithError ("Project analysis reported problems:`n  " + ($lines -join "`n  ")) $exitCode
}

<#
.SYNOPSIS
    Infers a distribution name from the analysis or the source path, and sanitises it.
#>
function Resolve-PpbPackageName {
    param([string]$Name, $Report, [Parameter(Mandatory)][string]$Source)
    $candidate = $Name
    if (-not $candidate -and $Report) { $candidate = Get-PpbValue $Report 'projectName' $null }
    if (-not $candidate) {
        $leaf = Split-Path -Leaf $Source
        if (Test-Path -LiteralPath $Source -PathType Leaf) { $leaf = [System.IO.Path]::GetFileNameWithoutExtension($leaf) }
        $candidate = $leaf
    }
    $clean = ($candidate -replace '[^A-Za-z0-9._-]+', '-').Trim('-', '.')
    if (-not $clean) { Stop-PpbWithError "Could not infer a valid package name from '$candidate'. Use -Name." 2 }
    if ($clean -ne $candidate) { Write-PpbLog "Package name sanitised: '$candidate' -> '$clean'" -Level Info }
    return $clean
}

<#
.SYNOPSIS
    Prints a concise human-readable analysis summary.
#>
function Write-PpbAnalysisSummary {
    param([Parameter(Mandatory)]$Report)
    $ep = Get-PpbValue $Report 'entryPoint'
    Write-PpbLog ("Project layout     : {0} (import roots: {1})" -f $Report.layout, (@($Report.importRoots) -join ', '))
    if ($ep) { Write-PpbLog ("Entry point        : {0} [{1}] - {2}" -f $ep.display, $ep.kind, $ep.selectionReason) }
    Write-PpbLog ("Application type   : {0}" -f (@($Report.applicationTypes) -join ', '))
    $third = @($Report.imports.thirdParty)
    Write-PpbLog ("Third-party imports: {0}" -f $(if ($third.Count) { ($third | ForEach-Object { $_.name }) -join ', ' } else { '(none)' }))
    $srcs = @($Report.dependencySources)
    Write-PpbLog ("Dependency sources : {0}" -f $(if ($srcs.Count) { ($srcs | ForEach-Object { "$($_.file) [$($_.kind)]" }) -join ', ' } else { '(none)' }))
    $req = Get-PpbValue $Report 'pythonRequirement'
    if ($req) { Write-PpbLog ("Python requirement : {0} ({1})" -f $req.specifier, $req.source) }
    $envs = @($Report.environmentVariables)
    if ($envs.Count) { Write-PpbLog ("Environment vars   : {0}" -f (($envs | ForEach-Object { $_.name }) -join ', ')) }
    foreach ($w in @($Report.warnings)) {
        Write-PpbLog $w.message -Level Warn
        foreach ($loc in @(Get-PpbValue $w 'locations' @())) { Write-PpbLog "    $loc" -Level Debug }
    }
}

Export-ModuleMember -Function Get-PpbProjectConfig, Invoke-PpbProjectAnalysis, Assert-PpbAnalysisUsable, Resolve-PpbPackageName, Write-PpbAnalysisSummary
