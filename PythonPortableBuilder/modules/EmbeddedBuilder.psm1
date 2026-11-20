#Requires -Version 5.1
<#
    EmbeddedBuilder.psm1 - Option B: official CPython embeddable distribution.

    Produces:
        distribution\
            runtime\    official embeddable runtime (pythonXY._pth adjusted)
            packages\   third-party dependencies (pip --target)
            app\        project files (unchanged copy)
            launcher\   ppb_launch.py, ppb_selftest.py, launch.json
            config\  logs\
            run.cmd  run.ps1  verify.ps1  README.md  DEPLOYMENT.md  build-manifest.json  SHA256SUMS
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'PythonRuntimeManager.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'DependencyManager.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'ResourceManager.psm1') -DisableNameChecking

# Standard-library modules that depend on native extension modules shipped with the runtime.
$script:NativeStdlib = @('ssl', 'sqlite3', 'ctypes', 'lzma', 'bz2', 'socket', 'select', 'unicodedata', 'decimal', 'hashlib', 'pyexpat', 'zoneinfo', 'asyncio', 'multiprocessing', 'uuid', 'winsound', 'overlapped')

<#
.SYNOPSIS
    Chooses the exact embeddable version (X.Y.Z) to use.
#>
function Resolve-PpbEmbeddedVersion {
    param([Parameter(Mandatory)][hashtable]$Context)
    $target = $Context.PythonTarget
    $cfg = $Context.Config
    $explicitFull = $Context.RequestedPythonVersion -and (($Context.RequestedPythonVersion -split '\.').Count -eq 3)
    if ($target.Version) {
        $info = $null
        try { $info = Get-PpbEmbeddedRuntimeInfo -Version $target.Version -Architecture $target.Architecture -Config $cfg }
        catch { Write-PpbLog "Release API lookup failed: $($_.Exception.Message)" -Level Debug; return $target.Version }
        if ($info) { return $target.Version }
        if ($explicitFull) { Stop-PpbWithError "Python $($target.Version) does not publish an embeddable package for $($target.Architecture). Choose another patch release." 2 }
        Write-PpbLog "Python $($target.Version) has no embeddable package for $($target.Architecture); looking for the newest $($target.MajorMinor).x that has one." -Level Warn
    }
    $latest = Find-PpbLatestEmbeddableVersion -MajorMinor $target.MajorMinor -Architecture $target.Architecture -Config $cfg
    if (-not $latest) { Stop-PpbWithError "No Python $($target.MajorMinor).x release publishes an embeddable package for $($target.Architecture)." 2 }
    return $latest
}

<#
.SYNOPSIS
    Copies tkinter (package, _tkinter.pyd, Tcl/Tk DLLs and libraries) from the build
    interpreter, because the embeddable package does not include it.
#>
function Copy-PpbTkinterSupport {
    param([Parameter(Mandatory)]$BuildPython, [Parameter(Mandatory)][string]$RuntimeDir, [Parameter(Mandatory)][string]$RuntimeVersion)
    if ($BuildPython.majorMinor -ne (Get-PpbMajorMinor $RuntimeVersion)) {
        Stop-PpbWithError "tkinter must be copied from a Python $((Get-PpbMajorMinor $RuntimeVersion)) installation, but the build interpreter is $($BuildPython.version)." 2
    }
    if (-not $BuildPython.hasTkinter) { Stop-PpbWithError "The application uses tkinter, but the build interpreter ($($BuildPython.executable)) was installed without Tcl/Tk. Reinstall Python with 'tcl/tk and IDLE' enabled." 2 }
    $base = [string]$BuildPython.basePrefix
    $items = @(
        @{ From = Join-Path $base 'Lib\tkinter'; To = Join-Path $RuntimeDir 'tkinter' },
        @{ From = Join-Path $base 'tcl'; To = Join-Path $RuntimeDir 'tcl' }
    )
    foreach ($i in $items) {
        if (-not (Test-Path -LiteralPath $i.From)) { Stop-PpbWithError "tkinter support files not found: $($i.From)" }
        Copy-Item -LiteralPath $i.From -Destination $i.To -Recurse -Force
    }
    $dlls = Join-Path $base 'DLLs'
    $patterns = '_tkinter.pyd', 'tcl*.dll', 'tk*.dll', 'zlib*.dll'
    foreach ($p in $patterns) { Get-ChildItem -LiteralPath $dlls -Filter $p -ErrorAction SilentlyContinue | Copy-Item -Destination $RuntimeDir -Force }
    Get-ChildItem -LiteralPath (Join-Path $RuntimeDir 'tkinter') -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
    if ($BuildPython.version -ne $RuntimeVersion) {
        Write-PpbLog "tkinter copied from Python $($BuildPython.version) into a $RuntimeVersion runtime (same minor version)." -Level Warn
    }
    Write-PpbLog "Copied tkinter and Tcl/Tk from $base" -Level Success
}

<#
.SYNOPSIS
    Builds the embedded distribution described by the build context.
.OUTPUTS
    Hashtable with manifest fragments.
#>
function Invoke-PpbEmbeddedBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Context)
    $ctx = $Context
    $dist = $ctx.DistDir
    $report = $ctx.Report
    $cfg = $ctx.Config

    # 1. Runtime ---------------------------------------------------------------
    Write-PpbLog 'Preparing the official Python embeddable runtime' -Level Step
    $version = Resolve-PpbEmbeddedVersion -Context $ctx
    $ctx.PythonTarget.Version = $version
    $runtime = Get-PpbEmbeddedRuntime -Version $version -Architecture $ctx.Architecture -CacheDirectory $ctx.CacheDir -Config $cfg -LocalZip $ctx.RuntimeZip
    $runtimeDir = Join-Path $dist 'runtime'
    $installed = Install-PpbEmbeddedRuntime -Runtime $runtime -Destination $runtimeDir

    # 2. Application files -----------------------------------------------------
    Write-PpbLog 'Copying application files' -Level Step
    $appDir = Join-Path $dist 'app'
    Copy-PpbProjectFiles -Files $ctx.Selection.Included -Destination $appDir
    foreach ($df in $ctx.DataFiles) { Copy-PpbDataFile -DataFile $df -Destination $appDir }
    Write-PpbLog ("Copied {0} file(s) into app\" -f @($ctx.Selection.Included).Count) -Level Success

    # 3. Import paths (pythonXY._pth) -------------------------------------------
    $importPaths = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($report.importRoots)) {
        $p = if ($r -eq '.' -or -not $r) { 'app' } else { 'app\' + $r.Replace('/', '\') }
        if (-not $importPaths.Contains($p)) { $importPaths.Add($p) }
    }
    foreach ($p in $ctx.AdditionalPaths) {
        $q = 'app\' + $p.Replace('/', '\').Trim('\')
        if (-not (Test-Path -LiteralPath (Join-Path $dist $q))) { Stop-PpbWithError "Additional path '$p' does not exist in the application." 2 }
        if (-not $importPaths.Contains($q)) { $importPaths.Add($q) }
    }
    $importPaths.Add('packages')
    Set-PpbEmbeddedPathFile -PthFile $installed.PthFile -RelativePaths @($importPaths | ForEach-Object { "..\$_" })
    Write-PpbLog ("Configured {0}: {1}" -f (Split-Path -Leaf $installed.PthFile), (($importPaths | ForEach-Object { "..\$_" }) -join ', ')) -Level Success

    # 4. Dependencies ----------------------------------------------------------
    Write-PpbLog 'Installing dependencies into packages\' -Level Step
    $packagesDir = New-PpbDirectory (Join-Path $dist 'packages')
    $target = $ctx.PythonTarget
    $base = $target.BuildPython
    $envName = if ($target.CrossInstall) { "pip-host-cp$($base.majorMinor.Replace('.', ''))-$($base.architecture)" } else { "pip-cp$($target.MajorMinor.Replace('.', ''))-$($ctx.Architecture)" }
    $buildEnv = Join-Path (Join-Path $ctx.CacheDir 'buildenv') $envName
    $inventory = $null
    if ($ctx.Requirements.File) {
        $venvPy = New-PpbBuildEnvironment -BasePython ([string]$base.executable) -Path $buildEnv -OwnerRoot $ctx.CacheDir `
            -Stamp ([ordered]@{ python = [string]$base.version; executable = [string]$base.executable; arch = [string]$base.architecture; purpose = 'pip-target' }) `
            -UpgradePip:([bool]$cfg['upgradeBuildPip']) -Force:$ctx.Clean
        $crossVersion = if ($target.CrossInstall) { $version } else { $null }
        Install-PpbRequirements -PythonExe $venvPy -RequirementsFile $ctx.Requirements.File -Target $packagesDir -CrossVersion $crossVersion `
            -CrossArchitecture $ctx.Architecture -ReportFile (Join-Path $ctx.WorkDir 'pip-report.json') -TimeoutSeconds ([int]$cfg['timeouts']['pipSeconds'])
        foreach ($d in 'bin', 'Scripts') {
            $p = Join-Path $packagesDir $d
            if (Test-Path -LiteralPath $p) {
                Write-PpbLog "Removed packages\$d (console-script wrappers contain absolute build-machine paths; use run.cmd instead)." -Level Info
                Remove-PpbItem -Path $p -OwnerRoot $ctx.PackageDir
            }
        }
        $inventory = Get-PpbDependencyInventory -PythonExe $venvPy -Path $packagesDir -Version $version -Architecture $ctx.Architecture
        foreach ($d in @($inventory.distributions)) { Write-PpbLog ("  {0} {1}" -f $d.name, $d.version) -Level Info }
        Write-PpbLog ("Installed {0} distribution(s)" -f @($inventory.distributions).Count) -Level Success
    } else {
        Write-PpbLog 'No third-party dependencies to install.' -Level Info
    }

    # 5. Runtime extras: .pth processing, tkinter ------------------------------
    $pthDirs = @()
    if ($inventory -and @($inventory.pthFiles).Count) {
        $pthDirs = @('packages')
        $names = (@($inventory.pthFiles) | ForEach-Object { $_.file }) -join ', '
        Write-PpbLog "Dependencies rely on .pth processing ($names). The launcher processes packages\*.pth explicitly ('import site' stays disabled)." -Level Info
    }
    $stdlibUsed = @($report.imports.stdlib)
    $usesTk = $stdlibUsed -contains 'tkinter'
    if ($usesTk) {
        $tkSource = $base
        if ($target.CrossInstall -or -not $tkSource.hasTkinter) {
            Stop-PpbWithError 'The application uses tkinter. Install the same Python minor version (with Tcl/Tk) on the build machine so tkinter can be bundled.' 2
        }
        Copy-PpbTkinterSupport -BuildPython $tkSource -RuntimeDir $runtimeDir -RuntimeVersion $version
    }

    # 6. Launchers -------------------------------------------------------------
    Write-PpbLog 'Generating launchers' -Level Step
    $launcherDir = New-PpbDirectory (Join-Path $dist 'launcher')
    Copy-Item -LiteralPath (Get-PpbTemplatePath 'embedded\ppb_launch.py') -Destination $launcherDir -Force
    Copy-Item -LiteralPath (Get-PpbTemplatePath 'embedded\ppb_selftest.py') -Destination $launcherDir -Force
    $entry = $ctx.Entry
    $launchEntry = [ordered]@{ kind = $entry.kind }
    switch ($entry.kind) {
        'script' { $launchEntry.path = [string]$entry.path }
        'module' { $launchEntry.module = [string]$entry.module }
        'callable' { $launchEntry.module = [string]$entry.module; $launchEntry.function = [string]$entry.function }
    }
    Write-PpbJsonFile -Path (Join-Path $launcherDir 'launch.json') -Data ([ordered]@{
            name = $ctx.Name; entry = $launchEntry; pthDirectories = $pthDirs; dllDirectories = @($ctx.DllDirectories)
            workingDirectory = $ctx.WorkingDirectory; generatedBy = "PythonPortableBuilder $($ctx.ToolkitVersion)"
        })
    $pyExe = if ($ctx.Windowed) { 'pythonw.exe' } else { 'python.exe' }
    $tokens = @{ NAME = $ctx.Name; TOOLKIT_VERSION = $ctx.ToolkitVersion; PYTHON_EXE = $pyExe; WORKING_DIRECTORY = $ctx.WorkingDirectory; WINDOWED = $(if ($ctx.Windowed) { 'true' } else { 'false' }) }
    Write-PpbTextFile -Path (Join-Path $dist 'run.cmd') -Content (Expand-PpbTemplate (Get-PpbTemplatePath 'embedded\run.cmd') $tokens) -Crlf
    Write-PpbTextFile -Path (Join-Path $dist 'run.ps1') -Content (Expand-PpbTemplate (Get-PpbTemplatePath 'embedded\run.ps1') $tokens) -Crlf
    New-PpbDirectory (Join-Path $dist 'config') | Out-Null
    New-PpbDirectory (Join-Path $dist 'logs') | Out-Null
    Write-PpbTextFile -Path (Join-Path $dist 'config\README.txt') -Crlf -Content ("Place deployment-specific configuration here (never commit secrets).`n" +
        "The launcher exposes this directory to the application as the environment variable PPB_CONFIG_DIR.`n")
    Write-PpbTextFile -Path (Join-Path $dist 'logs\README.txt') -Crlf -Content "Log directory. Exposed to the application as the environment variable PPB_LOG_DIR.`n"
    Write-PpbLog 'run.cmd, run.ps1 and launcher\ generated (relative paths only)' -Level Success

    # 7. Binary checks ---------------------------------------------------------
    Write-PpbLog 'Checking native binaries and imports' -Level Step
    $native = Get-PpbNativeDependencyReport -PythonExe ([string]$base.executable) -Root $dist
    $compat = Get-PpbBinaryCompatibility -Inventory $inventory -NativeReport $native -Architecture $ctx.Architecture
    if ($compat.Incompatible.Count) { Stop-PpbWithError ("Binary-incompatible packages for Python $version ($($ctx.Architecture)):`n    " + ($compat.Incompatible -join "`n    ")) }
    if ($compat.WrongMachine.Count) { Stop-PpbWithError ("Native binaries with the wrong architecture:`n    " + ($compat.WrongMachine -join "`n    ")) }

    # 8. Import resolution with the EMBEDDED interpreter -----------------------
    $thirdParty = @(@($report.imports.thirdParty) | ForEach-Object { $_ })
    $required = @($thirdParty | Where-Object { -not $_.optional } | ForEach-Object { $_.name })
    $optional = @($thirdParty | Where-Object { $_.optional } | ForEach-Object { $_.name })
    $embeddedPy = Join-Path $runtimeDir 'python.exe'
    $missing = @(Test-PpbImportResolution -PythonExe $embeddedPy -Names ($required + $optional) -LauncherDirectory $launcherDir -EmbeddedRuntime)
    $missingRequired = @($missing | Where-Object { $required -contains $_ })
    $missingOptional = @($missing | Where-Object { $optional -contains $_ })
    foreach ($m in $missingOptional) { Write-PpbLog "Optional import '$m' (inside try/except ImportError) is not available in the package." -Level Info }
    if ($missingRequired.Count) {
        $msg = "Imports not resolvable with the embedded runtime: $($missingRequired -join ', '). Add the missing distributions to the requirements."
        if ($ctx.AllowUnresolvedImports) { Write-PpbLog $msg -Level Warn } else { Stop-PpbWithError ($msg + ' (Use -AllowUnresolvedImports to accept this deliberately.)') 2 }
    } else {
        Write-PpbLog "All $($required.Count) required third-party import(s) resolve with runtime\python.exe" -Level Success
    }

    $importNames = @(($required + $optional) | Where-Object { $missing -notcontains $_ } | Sort-Object -Unique)
    if (-not $importNames.Count -and $inventory) {
        $direct = @($ctx.Requirements.Lines | ForEach-Object { if ($_ -match '^\s*([A-Za-z0-9][A-Za-z0-9._-]*)') { ($Matches[1] -replace '[-_.]+', '-').ToLowerInvariant() } })
        $importNames = @(@($inventory.distributions) | Where-Object { $direct -contains (($_.name -replace '[-_.]+', '-').ToLowerInvariant()) } |
                ForEach-Object { @($_.importNames) } | Sort-Object -Unique)
    }
    $stdlibChecks = @($script:NativeStdlib | Where-Object { $stdlibUsed -contains $_ })

    $requiredFiles = @('runtime\python.exe', (Join-Path 'runtime' (Split-Path -Leaf $installed.PthFile)), 'launcher\ppb_launch.py', 'launcher\launch.json',
        'launcher\ppb_selftest.py', 'run.cmd', 'run.ps1', 'verify.ps1', 'README.md', 'DEPLOYMENT.md', 'app', 'packages', 'config', 'logs')
    if ($entry.kind -eq 'script') { $requiredFiles += ('app\' + ([string]$entry.path).Replace('/', '\')) }

    return @{
        Runtime         = [ordered]@{
            source = $runtime.Url; sha256 = $runtime.Sha256; checksumVerified = $runtime.ChecksumVerified; checksumAlgorithm = $runtime.ChecksumAlgorithm
            obtainedFrom = $runtime.Source; authenticode = $installed.Signature
        }
        Inventory       = $inventory
        NativeReport    = $native
        ImportNames     = $importNames
        MissingImports  = $missingRequired
        Embedded        = [ordered]@{
            pathFile = (Split-Path -Leaf $installed.PthFile); importPaths = $importPaths.ToArray(); pthProcessing = [bool]$pthDirs.Count
            tkinter = $usesTk; stdlibChecks = $stdlibChecks; launcherInterpreter = $pyExe
        }
        RequiredFiles   = $requiredFiles
        BundledResources = @()
        RunCommand      = "run.cmd [arguments]"
    }
}

function Copy-PpbDataFile {
    param([Parameter(Mandatory)]$DataFile, [Parameter(Mandatory)][string]$Destination)
    $destDir = if ($DataFile.Destination -eq '.') { $Destination } else { Join-Path $Destination $DataFile.Destination.Replace('/', '\') }
    New-PpbDirectory $destDir | Out-Null
    Copy-Item -LiteralPath $DataFile.Source -Destination $destDir -Recurse -Force
}

Export-ModuleMember -Function Invoke-PpbEmbeddedBuild, Resolve-PpbEmbeddedVersion, Copy-PpbTkinterSupport, Copy-PpbDataFile
