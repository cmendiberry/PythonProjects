#Requires -Version 5.1
<#
    DependencyManager.psm1 - dependency resolution, installation and inventory.

      * Chooses the dependency source (explicit file, lock file, requirements,
        pyproject, setup.cfg, setup.py) - never "everything installed locally"
      * Installs with pip into an isolated target (embedded: packages/, executable: venv)
      * Stops the build on pip failures and on unresolved imports
      * Produces an inventory (versions, licenses, wheel tags, native DLL imports)
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'PythonRuntimeManager.psm1') -DisableNameChecking

$script:InspectScript = Join-Path (Get-PpbToolkitRoot) 'python\ppb_inspect.py'

function Get-PpbPlatformTag {
    param([Parameter(Mandatory)][string]$Architecture)
    switch ($Architecture) { 'amd64' { 'win_amd64' } 'win32' { 'win32' } 'arm64' { 'win_arm64' } default { Stop-PpbWithError "Unsupported architecture $Architecture" 2 } }
}

function Test-PpbSelfInstallLine {
    param([string]$Line)
    $l = $Line.Trim()
    return ($l -match '^(-e|--editable)\s+(\.|file:\.?|\./?)(\[.*\])?$' -or $l -match '^\.(\[.*\])?$' -or $l -match '^file:\.(/)?$')
}

<#
.SYNOPSIS
    Selects the dependency source and produces a requirements file to install.
.OUTPUTS
    Hashtable: File (path or $null), Kind, SourceFile, Lines, Locked, Notes
#>
function Resolve-PpbRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$WorkDirectory,
        [string]$Requirements,
        [switch]$InferRequirements
    )
    $generated = Join-Path $WorkDirectory 'requirements.ppb.txt'
    $notes = New-Object System.Collections.Generic.List[string]

    if ($Requirements) {
        $path = Resolve-PpbPath $Requirements -BasePath $ProjectRoot
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-PpbWithError "Requirements file not found: $path" 2 }
        $lines = @([System.IO.File]::ReadAllLines($path) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
        $selected = @{ Kind = 'requirements'; SourceFile = $path; Lines = $lines; Locked = $false; Explicit = $true }
    } else {
        $sources = @(Get-PpbValue $Report 'dependencySources' @())
        $rank = { param($s)
            $locked = [bool](Get-PpbValue $s 'locked' $false)
            switch ($s.kind) {
                'pipfile-lock' { 0 }
                'requirements' { if ($locked) { 1 } elseif ($s.file -ieq 'requirements.txt') { 2 } else { 3 } }
                'pyproject' { 4 } 'poetry' { 5 } 'setup.cfg' { 6 } 'setup.py' { 7 } default { 9 }
            }
        }
        $ordered = @($sources | Sort-Object { & $rank $_ }, { $_.file })
        $selected = $null
        if ($ordered.Count) {
            $s = $ordered[0]
            $selected = @{ Kind = $s.kind; SourceFile = (Join-Path $ProjectRoot $s.file); Lines = @($s.requirements); Locked = [bool](Get-PpbValue $s 'locked' $false); Explicit = $false }
            if ($ordered.Count -gt 1) {
                $others = ($ordered | Select-Object -Skip 1 | ForEach-Object { "$($_.file) [$($_.kind)]" }) -join ', '
                $notes.Add("Using $($s.file) [$($s.kind)]; other declarations not used: $others")
            }
        }
    }

    if (-not $selected) {
        $required = @(@(Get-PpbValue $Report.imports 'thirdParty' @()) | Where-Object { -not $_.optional })
        if (-not $required.Count) {
            Write-PpbLog "No dependency declarations and no third-party imports: no packages to install." -Level Info
            return @{ File = $null; Kind = 'none'; SourceFile = $null; Lines = @(); Locked = $false; Notes = $notes.ToArray() }
        }
        $suggest = @($required | ForEach-Object { if ($_.suggestedDistribution) { "$($_.name) -> $($_.suggestedDistribution)" } else { "$($_.name) -> (unknown distribution name)" } })
        if (-not $InferRequirements) {
            Stop-PpbWithError ("The project imports third-party modules but declares no dependencies (no requirements.txt, pyproject.toml, setup.cfg or setup.py):`n    " +
                ($suggest -join "`n    ") + "`n  Import names do not always match pip package names. Create a requirements file and pass -Requirements, " +
                "or use -InferRequirements to accept the suggested names (unknown names still fail).") 2
        }
        $unknown = @($required | Where-Object { -not $_.suggestedDistribution -or $_.suggestedDistribution.Contains('*') })
        if ($unknown.Count) {
            Stop-PpbWithError ("-InferRequirements cannot map these imports to pip packages: $(($unknown | ForEach-Object name) -join ', '). Provide a requirements file.") 2
        }
        $lines = @($required | ForEach-Object { $_.suggestedDistribution } | Select-Object -Unique)
        Write-PpbLog "Inferred requirements from imports (unpinned): $($lines -join ', ')" -Level Warn
        $selected = @{ Kind = 'inferred'; SourceFile = $null; Lines = $lines; Locked = $false; Explicit = $false }
    }

    # Filter installs of the project itself: its source is placed in app/, not packages/.
    $clean = New-Object System.Collections.Generic.List[string]
    $needsRewrite = ($selected.Kind -ne 'requirements')
    foreach ($l in $selected.Lines) {
        if (Test-PpbSelfInstallLine $l) {
            $notes.Add("Ignored '$l': the project itself is not pip-installed; its source is copied into the distribution.")
            $needsRewrite = $true
            continue
        }
        if ($l -match '^(-r|--requirement|-c|--constraint)\s+(.+)$' -and $selected.SourceFile) {
            $inc = Resolve-PpbPath $Matches[2].Trim() -BasePath (Split-Path -Parent $selected.SourceFile)
            $clean.Add("$($Matches[1]) $inc")
            continue
        }
        if ($l -match '^(-e|--editable)\s') {
            Stop-PpbWithError "Editable requirement '$l' cannot be installed into a portable distribution. Replace it with a regular requirement." 2
        }
        $clean.Add($l)
    }
    foreach ($n in $notes) { Write-PpbLog $n -Level Info }
    if (-not $clean.Count) {
        return @{ File = $null; Kind = $selected.Kind; SourceFile = $selected.SourceFile; Lines = @(); Locked = $selected.Locked; Notes = $notes.ToArray() }
    }
    if ($needsRewrite) {
        New-PpbDirectory $WorkDirectory | Out-Null
        $header = "# Generated by PythonPortableBuilder from $($selected.Kind)$(if ($selected.SourceFile) { ': ' + (Split-Path -Leaf $selected.SourceFile) })"
        Write-PpbTextFile -Path $generated -Content (($header, ($clean -join "`r`n")) -join "`r`n")
        $file = $generated
    } else {
        $file = $selected.SourceFile
    }
    if ($selected.Kind -in 'pyproject', 'setup.cfg', 'setup.py', 'poetry', 'inferred' -and -not $selected.Locked) {
        Write-PpbLog "Dependencies come from version ranges ($($selected.Kind)); installed versions are recorded in the build manifest. Use a pinned requirements file for reproducible builds." -Level Info
    }
    return @{ File = $file; Kind = $selected.Kind; SourceFile = $selected.SourceFile; Lines = $clean.ToArray(); Locked = $selected.Locked; Notes = $notes.ToArray() }
}

function Get-PpbPipVersion {
    param([Parameter(Mandatory)][string]$PythonExe)
    $r = Invoke-PpbProcess -FilePath $PythonExe -ArgumentList @('-m', 'pip', '--version') -Quiet -Environment (Get-PpbIsolatedPipEnvironment) -TimeoutSeconds 120
    if ($r.ExitCode -ne 0 -or $r.StdOut -notmatch 'pip (\d+(\.\d+)*)') { Stop-PpbWithError "pip is not available for $PythonExe" }
    return $Matches[1]
}

<#
.SYNOPSIS
    Runs pip install. Throws (build stops) when installation fails.
#>
function Install-PpbRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PythonExe,
        [string]$RequirementsFile,
        [string[]]$Packages,
        [string]$Target,
        [string]$CrossVersion,
        [string]$CrossArchitecture,
        [string]$ReportFile,
        [int]$TimeoutSeconds = 1800
    )
    $pipVersion = Get-PpbPipVersion $PythonExe
    $pipArgs = @('-m', 'pip', 'install', '--no-input', '--disable-pip-version-check', '--no-warn-script-location')
    if ($Target) { $pipArgs += @('--target', $Target, '--upgrade') }
    if ($CrossVersion) {
        $mm = Get-PpbMajorMinor $CrossVersion
        $pipArgs += @('--platform', (Get-PpbPlatformTag $CrossArchitecture), '--python-version', $mm, '--implementation', 'cp',
            '--abi', ('cp' + $mm.Replace('.', '')), '--only-binary=:all:')
    }
    if ($ReportFile -and (Compare-PpbVersion $pipVersion '22.2') -ge 0) { $pipArgs += @('--report', $ReportFile) }
    if ($RequirementsFile) { $pipArgs += @('-r', $RequirementsFile) }
    if ($Packages) { $pipArgs += $Packages }
    Write-PpbLog "pip $pipVersion installing $(if ($RequirementsFile) { Split-Path -Leaf $RequirementsFile } else { $Packages -join ' ' })$(if ($Target) { ' into ' + $Target })" -Level Info
    $r = Invoke-PpbProcess -FilePath $PythonExe -ArgumentList $pipArgs -Environment (Get-PpbIsolatedPipEnvironment) -TimeoutSeconds $TimeoutSeconds
    if ($r.TimedOut) { Stop-PpbWithError "pip install timed out after $TimeoutSeconds seconds." }
    if ($r.ExitCode -ne 0) {
        $tail = (($r.StdErr.Trim() -split "`r?`n") | Select-Object -Last 25) -join "`n    "
        $hint = ''
        if ($CrossVersion -and $r.StdErr -match 'No matching distribution|only-binary') {
            $hint = "`n  Cross-installation only accepts binary wheels. Install Python $CrossVersion ($CrossArchitecture) on the build machine to allow source builds."
        }
        Stop-PpbWithError "Dependency installation failed (pip exit $($r.ExitCode)). The build was stopped; no packages were silently skipped.`n    $tail$hint"
    }
}

function Invoke-PpbInspect {
    param([Parameter(Mandatory)][string]$PythonExe, [Parameter(Mandatory)][string[]]$Arguments, [switch]$NoIsolation, [int]$TimeoutSeconds = 600)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ppb-inspect-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    try {
        $pyArgs = @()
        if (-not $NoIsolation) { $pyArgs += '-I' }
        $pyArgs += @('-B', $script:InspectScript, '--output', $tmp) + $Arguments
        $r = Invoke-PpbProcess -FilePath $PythonExe -ArgumentList $pyArgs -Quiet -TimeoutSeconds $TimeoutSeconds -Environment @{ PYTHONUTF8 = '1' }
        if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { Stop-PpbWithError "Inspection '$($Arguments[0])' failed (exit $($r.ExitCode)): $($r.StdErr)" }
        return Read-PpbJsonFile $tmp
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

<#
.SYNOPSIS
    Inventory of installed distributions (versions, licenses, wheel tags, native files).
#>
function Get-PpbDependencyInventory {
    param(
        [Parameter(Mandatory)][string]$PythonExe,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Architecture
    )
    $abi = 'cp' + (Get-PpbMajorMinor $Version).Replace('.', '')
    return Invoke-PpbInspect -PythonExe $PythonExe -Arguments @('inventory', '--path', $Path, '--abi', $abi, '--platform', (Get-PpbPlatformTag $Architecture))
}

<#
.SYNOPSIS
    Classifies the DLL imports of every native binary below Root.
#>
function Get-PpbNativeDependencyReport {
    param([Parameter(Mandatory)][string]$PythonExe, [Parameter(Mandatory)][string]$Root, [string[]]$SearchDirectories)
    $a = @('pe-imports', '--root', $Root)
    foreach ($d in $SearchDirectories) { $a += @('--search', $d) }
    return Invoke-PpbInspect -PythonExe $PythonExe -Arguments $a
}

<#
.SYNOPSIS
    Checks that third-party imports resolve in the target interpreter (find_spec, no execution).
#>
function Test-PpbImportResolution {
    param(
        [Parameter(Mandatory)][string]$PythonExe,
        [string[]]$Names,
        [string]$LauncherDirectory,
        [string[]]$ExtraPaths,
        [switch]$EmbeddedRuntime
    )
    if (-not $Names -or $Names.Count -eq 0) { return @() }
    $a = @('resolve', '--names', ($Names -join ','))
    if ($LauncherDirectory) { $a += @('--launcher', $LauncherDirectory) }
    foreach ($p in $ExtraPaths) { $a += @('--path', $p) }
    $r = Invoke-PpbInspect -PythonExe $PythonExe -Arguments $a -NoIsolation:$EmbeddedRuntime
    $missing = @()
    foreach ($p in $r.modules.PSObject.Properties) { if (-not $p.Value.found) { $missing += $p.Name } }
    return $missing
}

<#
.SYNOPSIS
    Reports binary-compatibility problems and native DLL prerequisites.
.OUTPUTS
    Hashtable: Incompatible (list), MissingDlls (list of {dll, requiredBy}), Machines
#>
function Get-PpbBinaryCompatibility {
    param($Inventory, $NativeReport, [Parameter(Mandatory)][string]$Architecture)
    $incompatible = @()
    if ($Inventory) {
        foreach ($d in @($Inventory.distributions)) {
            if (-not $d.binaryCompatible) {
                $incompatible += "$($d.name) $($d.version): $($d.compatibilityNote)"
            }
        }
    }
    $wrongMachine = @()
    $missing = @()
    if ($NativeReport) {
        foreach ($p in $NativeReport.machines.PSObject.Properties) {
            if ($p.Name -ne $Architecture) { $wrongMachine += "$($p.Value) binaries for $($p.Name): $((@($NativeReport.machineFiles.($p.Name)) | Select-Object -First 5) -join ', ')" }
        }
        $missing = @($NativeReport.missing)
    }
    return @{ Incompatible = $incompatible; WrongMachine = $wrongMachine; MissingDlls = $missing }
}

<#
.SYNOPSIS
    Known external DLL prerequisites (Visual C++ runtime, database clients ...).
#>
function Get-PpbDllPrerequisiteHint {
    param([Parameter(Mandatory)][string]$Dll)
    $d = $Dll.ToLowerInvariant()
    if ($d -match '^(msvcp140|vcruntime140|vcruntime140_1|concrt140|vcomp140|msvcp140_\d+)\.dll$') { return 'Microsoft Visual C++ 2015-2022 Redistributable' }
    if ($d -match '^libpq') { return 'PostgreSQL client library (libpq)' }
    if ($d -match '^oci\.dll$') { return 'Oracle Instant Client' }
    if ($d -match '^libmysql') { return 'MySQL client library' }
    if ($d -match '^msodbcsql') { return 'Microsoft ODBC Driver for SQL Server' }
    if ($d -match '^(libssl|libcrypto)') { return 'OpenSSL libraries' }
    if ($d -match '^(d3d|dxgi|opengl32|glu32)') { return 'Graphics/DirectX components' }
    return 'External DLL (not bundled, not a Windows system DLL on the build machine)'
}

Export-ModuleMember -Function Resolve-PpbRequirements, Install-PpbRequirements, Get-PpbDependencyInventory, Get-PpbNativeDependencyReport,
    Test-PpbImportResolution, Get-PpbBinaryCompatibility, Get-PpbDllPrerequisiteHint, Get-PpbPlatformTag, Test-PpbSelfInstallLine, Invoke-PpbInspect, Get-PpbPipVersion
