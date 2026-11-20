#Requires -Version 5.1
<#
    PackageValidator.psm1 - validation of generated distributions.

    The distribution's own verify.ps1 (templates/distribution/verify.ps1) is the single
    implementation of runtime/launcher/application checks, so the same checks run on the
    build machine and on the destination server. This module adds build-side checks:
      * references to build-machine absolute paths inside the distribution
      * running the checks from a temporary COPY of the distribution, so accidental
        dependencies on the build output location are detected
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

$script:TextExtensions = @('.cmd', '.bat', '.ps1', '.py', '.json', '._pth', '.pth', '.txt', '.cfg', '.ini', '.toml', '.yaml', '.yml', '.md', '.spec')
$script:CriticalPattern = '^(run\.cmd|run\.ps1|verify\.ps1|launcher/.*|runtime/[^/]+\._pth|packages/[^/]+\.pth)$'

<#
.SYNOPSIS
    Scans distribution text files for absolute build-machine paths.
.OUTPUTS
    PSCustomObject[] { RelativePath, Needle, Critical }
#>
function Find-PpbBuildPathReferences {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string[]]$Needles)
    $variants = New-Object System.Collections.Generic.List[string]
    foreach ($n in $Needles) {
        if (-not $n -or $n.Length -lt 4) { continue }
        $full = (Resolve-PpbPath $n).TrimEnd('\')
        foreach ($v in @($full, $full.Replace('\', '/'), $full.Replace('\', '\\'))) { if (-not $variants.Contains($v)) { $variants.Add($v) } }
    }
    $hits = @()
    foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $rel = (Get-PpbRelativePath -Path $f.FullName -BasePath $Root).Replace('\', '/')
        if ($rel.StartsWith('app/') -or $rel -eq 'SHA256SUMS') { continue }   # application sources are reported by the analysis
        $ext = [System.IO.Path]::GetExtension($f.Name).ToLowerInvariant()
        if ($f.Name -like '*._pth') { $ext = '._pth' }
        if ($script:TextExtensions -notcontains $ext -or $f.Length -gt 5MB) { continue }
        $text = [System.IO.File]::ReadAllText($f.FullName)
        foreach ($v in $variants) {
            if ($text.IndexOf($v, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits += [pscustomobject]@{ RelativePath = $rel; Needle = $v; Critical = [bool]($rel -match $script:CriticalPattern) }
                break
            }
        }
    }
    return $hits
}

<#
.SYNOPSIS
    Validates a distribution. Returns @{ Status; Results }.
.PARAMETER BuildPaths
    Absolute build-machine paths that must not be referenced (source, output, toolkit, interpreter).
#>
function Invoke-PpbDistributionValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistributionPath,
        [string[]]$BuildPaths,
        [switch]$InTempCopy,
        [switch]$SkipAppRun,
        [int]$TimeoutSeconds = 60
    )
    $results = New-Object System.Collections.Generic.List[object]
    $DistributionPath = Resolve-PpbPath $DistributionPath
    if (-not (Test-Path -LiteralPath (Join-Path $DistributionPath 'verify.ps1'))) {
        Stop-PpbWithError "Not a PythonPortableBuilder distribution (verify.ps1 missing): $DistributionPath" 2
    }

    if ($BuildPaths) {
        $hits = @(Find-PpbBuildPathReferences -Root $DistributionPath -Needles $BuildPaths)
        $critical = @($hits | Where-Object { $_.Critical })
        $other = @($hits | Where-Object { -not $_.Critical })
        if ($critical.Count) {
            $results.Add([pscustomobject]@{ name = 'no-build-paths'; status = 'failed'; detail = 'launch files reference build-machine paths: ' + (($critical | ForEach-Object { "$($_.RelativePath) ($($_.Needle))" }) -join '; ') })
        } elseif ($other.Count) {
            $results.Add([pscustomobject]@{ name = 'no-build-paths'; status = 'warning'; detail = 'non-launch files mention build-machine paths: ' + (($other | Select-Object -First 10 | ForEach-Object { $_.RelativePath }) -join ', ') })
        } else {
            $results.Add([pscustomobject]@{ name = 'no-build-paths'; status = 'passed'; detail = 'launchers, runtime configuration and package files contain no build-machine paths' })
        }
    }

    $target = $DistributionPath
    $temp = $null
    try {
        if ($InTempCopy) {
            $temp = New-PpbTempDirectory -Prefix 'ppb-verify'
            $target = Join-Path $temp (Split-Path -Leaf (Split-Path -Parent $DistributionPath))
            Write-PpbLog "Copying the distribution to $target for location-independent validation" -Level Debug
            $r = Invoke-PpbProcess -FilePath "$env:SystemRoot\System32\robocopy.exe" -ArgumentList @($DistributionPath, $target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1') -Quiet -TimeoutSeconds 1800
            if ($r.ExitCode -ge 8) { Stop-PpbWithError "Copying the distribution for validation failed (robocopy exit $($r.ExitCode))." }
        }
        $reportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ppb-verify-report-{0}.json" -f [Guid]::NewGuid().ToString('N'))
        $psArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $target 'verify.ps1'),
            '-Path', $target, '-ReportPath', $reportPath, '-TimeoutSeconds', [string]$TimeoutSeconds)
        if ($SkipAppRun) { $psArgs += '-SkipAppRun' }
        $r = Invoke-PpbProcess -FilePath (Get-PpbPowerShellExecutable) -ArgumentList $psArgs -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds ([Math]::Max(600, $TimeoutSeconds * 20))
        if (Test-Path -LiteralPath $reportPath) {
            $rep = Read-PpbJsonFile $reportPath
            Remove-Item -LiteralPath $reportPath -Force
            foreach ($x in @($rep.results)) { $results.Add([pscustomobject]@{ name = $x.name; status = $x.status; detail = $x.detail }) }
        } else {
            $results.Add([pscustomobject]@{ name = 'verify-script'; status = 'failed'; detail = "verify.ps1 produced no report (exit $($r.ExitCode)): $($r.StdErr.Trim())" })
        }
        if ($InTempCopy) { $results.Add([pscustomobject]@{ name = 'location-independence'; status = 'passed'; detail = 'checks above ran from a copy outside the build output directory' }) }
    } finally {
        if ($temp) { Remove-PpbItem -Path $temp -AllowTempOwned }
    }

    $failed = @($results | Where-Object { $_.status -eq 'failed' }).Count
    $warn = @($results | Where-Object { $_.status -eq 'warning' }).Count
    $status = if ($failed) { 'failed' } elseif ($warn) { 'passed-with-warnings' } else { 'passed' }
    return @{ Status = $status; Results = $results.ToArray(); TimestampUtc = [DateTime]::UtcNow.ToString('o') }
}

function Write-PpbValidationSummary {
    param([Parameter(Mandatory)][hashtable]$Validation)
    foreach ($r in $Validation.Results) {
        $level = switch ($r.status) { 'passed' { 'Success' } 'failed' { 'Error' } 'warning' { 'Warn' } default { 'Info' } }
        Write-PpbLog ("[{0}] {1}{2}" -f $r.status, $r.name, $(if ($r.detail) { " - $($r.detail)" } else { '' })) -Level $level
    }
    $counts = @('passed', 'failed', 'warning', 'skipped' | ForEach-Object { $s = $_; "{0} {1}" -f @($Validation.Results | Where-Object { $_.status -eq $s }).Count, $s })
    Write-PpbLog ("Validation {0}: {1}" -f $Validation.Status, ($counts -join ', ')) -Level $(if ($Validation.Status -eq 'failed') { 'Error' } else { 'Info' })
}

Export-ModuleMember -Function Find-PpbBuildPathReferences, Invoke-PpbDistributionValidation, Write-PpbValidationSummary
