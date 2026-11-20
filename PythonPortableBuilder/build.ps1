#Requires -Version 5.1

<#
.SYNOPSIS
    Packages a Python script or project into a portable Windows distribution.

.DESCRIPTION
    PythonPortableBuilder analyses the source project (without executing it), installs its
    dependencies into an isolated build environment and produces a deployable distribution:

      -Type embedded    Official CPython embeddable runtime + packages\ + app\ + launchers.
      -Type executable  PyInstaller executable (-Mode onedir or onefile).

    Output layout (outside the toolkit repository by default):
        <Output>\<Name>\distribution\        the deployable files
        <Output>\<Name>\build-manifest.json  versions, checksums, validation results
        <Output>\<Name>\build.log            full build log
        <Output>\<Name>-embedded.zip         or <Name>-executable-<mode>.zip (+ .sha256)

    The source project is never modified. Exit codes: 0 success, 1 build error,
    2 invalid input / ambiguous project, 3 validation failed.

.PARAMETER Source
    Path of the Python script (.py) or project directory to package.
.PARAMETER Name
    Distribution name. Inferred from project metadata or the source name when omitted.
.PARAMETER Type
    embedded or executable.
.PARAMETER Mode
    onedir (default) or onefile. Executable builds only.
.PARAMETER Output
    Output root. Default: 'outputRoot' in config\defaults.json (..\PortableBuilds relative to the toolkit),
    overridable with config\local.json or the PPB_OUTPUT_ROOT environment variable.
.PARAMETER EntryPoint
    Script path relative to the project (tools\run.py), module (package.cli), callable
    (package.cli:main) or the name of a declared console script. Detected automatically
    when omitted; ambiguous projects require it.
.PARAMETER PythonVersion
    Target Python version, X.Y or X.Y.Z. Default: project metadata (.python-version,
    requires-python) or the build machine's default interpreter.
.PARAMETER Requirements
    Explicit requirements file (relative to the project or absolute). Takes precedence over
    all detected dependency declarations.
.PARAMETER Clean
    Recreate build environments and remove previous build output of this package first.
.PARAMETER CreateZip
    Create the ZIP distribution (default $true). Use -CreateZip:$false to skip.
.PARAMETER Verify
    Validate the distribution (default $true). Use -Verify:$false to skip.
.PARAMETER NoZip
    Same as -CreateZip:$false; also works with 'powershell -File' and cmd.exe, where [bool] values cannot be passed.
.PARAMETER SkipVerify
    Same as -Verify:$false (works with 'powershell -File').
.PARAMETER Architecture
    amd64 (default), win32 or arm64.
.PARAMETER Windowed
    GUI application: no console window (PyInstaller windowed / pythonw.exe).
.PARAMETER Icon
    Icon file (*.ico) for executables.
.PARAMETER HiddenImport
    Additional modules PyInstaller cannot detect.
.PARAMETER DataFile
    Additional data, 'source;destination' (destination relative to the application root).
.PARAMETER AdditionalPath
    Additional import directories, relative to the project root.
.PARAMETER CollectPackage
    Packages whose submodules are all collected (PyInstaller collect_submodules).
.PARAMETER Include
    Glob patterns forced into the package (also overrides default exclusions and the secret scan).
.PARAMETER Exclude
    Glob patterns excluded from the package.
.PARAMETER SpecFile
    Custom PyInstaller .spec file (executable builds).
.PARAMETER SafeTestArgs
    Arguments that run the application safely (e.g. '--version') during validation.
    'none' disables the application run. Default: '--help' when the application uses
    argparse, click or typer; otherwise the application is not executed.
.PARAMETER WorkingDirectory
    Embedded launcher working directory: app (default, the app\ folder) or caller.
.PARAMETER BuildPython
    Explicit build interpreter (python.exe) instead of automatic discovery.
.PARAMETER RuntimeZip
    Pre-downloaded official python-X.Y.Z-embed-<arch>.zip (offline builds).
.PARAMETER InferRequirements
    When the project declares no dependencies, accept requirement names inferred from imports.
.PARAMETER AllowUnresolvedImports
    Continue although some required imports cannot be resolved.
.PARAMETER Help
    Shows this help.

.EXAMPLE
    .\build.ps1 -Source "D:\projects\reports" -Name "MonthlyReports" -Type embedded -Output "D:\PortableBuilds"
.EXAMPLE
    .\build.ps1 -Source "D:\descargas\custom_tool" -Name "Tool_Name" -Type executable -Mode onedir -Output "D:\PortableBuilds"
.EXAMPLE
    .\build.ps1 -Source .\examples\simple-script\hello.py -Type executable -Mode onefile
.EXAMPLE
    .\build.ps1 -Source D:\src\tool -Type embedded -PythonVersion 3.11 -EntryPoint "tool.cli:main"
#>
[CmdletBinding(DefaultParameterSetName = 'Help')]
param(
    [Parameter(ParameterSetName = 'Build', Mandatory, Position = 0)][string]$Source,
    [Parameter(ParameterSetName = 'Build')][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Name,
    [Parameter(ParameterSetName = 'Build', Mandatory)][ValidateSet('embedded', 'executable')][string]$Type,
    [Parameter(ParameterSetName = 'Build')][ValidateSet('onefile', 'onedir')][string]$Mode,
    [Parameter(ParameterSetName = 'Build')][string]$Output,
    [Parameter(ParameterSetName = 'Build')][string]$EntryPoint,
    [Parameter(ParameterSetName = 'Build')][ValidatePattern('^\d+\.\d+(\.\d+)?$')][string]$PythonVersion,
    [Parameter(ParameterSetName = 'Build')][string]$Requirements,
    [Parameter(ParameterSetName = 'Build')][switch]$Clean,
    [Parameter(ParameterSetName = 'Build')][bool]$CreateZip = $true,
    [Parameter(ParameterSetName = 'Build')][bool]$Verify = $true,
    [Parameter(ParameterSetName = 'Build')][switch]$NoZip,
    [Parameter(ParameterSetName = 'Build')][switch]$SkipVerify,
    [Parameter(ParameterSetName = 'Build')][ValidateSet('amd64', 'win32', 'arm64')][string]$Architecture,
    [Parameter(ParameterSetName = 'Build')][switch]$Windowed,
    [Parameter(ParameterSetName = 'Build')][string]$Icon,
    [Parameter(ParameterSetName = 'Build')][string[]]$HiddenImport,
    [Parameter(ParameterSetName = 'Build')][string[]]$DataFile,
    [Parameter(ParameterSetName = 'Build')][string[]]$AdditionalPath,
    [Parameter(ParameterSetName = 'Build')][string[]]$CollectPackage,
    [Parameter(ParameterSetName = 'Build')][string[]]$Include,
    [Parameter(ParameterSetName = 'Build')][string[]]$Exclude,
    [Parameter(ParameterSetName = 'Build')][string]$SpecFile,
    [Parameter(ParameterSetName = 'Build')][string[]]$SafeTestArgs,
    [Parameter(ParameterSetName = 'Build')][ValidateSet('app', 'caller')][string]$WorkingDirectory,
    [Parameter(ParameterSetName = 'Build')][string]$BuildPython,
    [Parameter(ParameterSetName = 'Build')][string]$RuntimeZip,
    [Parameter(ParameterSetName = 'Build')][switch]$InferRequirements,
    [Parameter(ParameterSetName = 'Build')][switch]$AllowUnresolvedImports,
    [Parameter(ParameterSetName = 'Help')][switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Help') {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

foreach ($m in 'Common', 'ProjectAnalyzer', 'PythonRuntimeManager', 'DependencyManager', 'ResourceManager', 'EmbeddedBuilder',
    'ExecutableBuilder', 'PackageValidator', 'ArchiveManager', 'BuildManifest') {
    Import-Module (Join-Path $PSScriptRoot "modules\$m.psm1") -Force -DisableNameChecking
}

function Get-Effective {
    <# CLI parameter > ppb.json > default #>
    param([string]$ParamName, [string]$ProjectKey, $Default)
    if ($script:Bound.ContainsKey($ParamName)) { return $script:Bound[$ParamName] }
    if ($ProjectKey -and $script:ProjectConfig.Contains($ProjectKey) -and $null -ne $script:ProjectConfig[$ProjectKey]) { return $script:ProjectConfig[$ProjectKey] }
    return $Default
}

$script:Bound = @{} + $PSBoundParameters
if ($NoZip) { $CreateZip = $false }
if ($SkipVerify) { $Verify = $false }
$startTime = Get-Date
$tempLog = Join-Path ([System.IO.Path]::GetTempPath()) ("ppb-build-{0}.log" -f [Guid]::NewGuid().ToString('N'))
Initialize-PpbLog -Path $tempLog -VerboseOutput:($VerbosePreference -eq 'Continue')
$exitCode = 0

try {
    $toolkitRoot = Get-PpbToolkitRoot
    $version = Get-PpbToolkitVersion
    Write-PpbLog "PythonPortableBuilder $version" -Level Step
    $config = Get-PpbConfig

    # --- Source -----------------------------------------------------------------
    $sourcePath = Resolve-PpbPath $Source
    if (-not (Test-Path -LiteralPath $sourcePath)) { Stop-PpbWithError "Source not found: $sourcePath" 2 }
    $isFile = Test-Path -LiteralPath $sourcePath -PathType Leaf
    $projectRoot = if ($isFile) { Split-Path -Parent $sourcePath } else { $sourcePath }
    if (Test-PpbPathInside -Child $toolkitRoot -Parent $projectRoot) { Stop-PpbWithError "The source '$projectRoot' contains the toolkit itself; the toolkit cannot package itself." 2 }
    $script:ProjectConfig = if ($isFile) { [ordered]@{} } else { Get-PpbProjectConfig -ProjectRoot $projectRoot }
    Write-PpbLog "Source: $sourcePath ($(if ($isFile) { 'single file' } else { 'project directory' }))"

    if ($script:Bound.ContainsKey('Mode') -and $Type -eq 'embedded') { Write-PpbLog '-Mode applies to executable builds only and is ignored.' -Level Warn }
    $modeValue = Get-Effective 'Mode' 'mode' 'onedir'
    $arch = Get-Effective 'Architecture' 'architecture' $config['architecture']
    if ($arch -notin 'amd64', 'win32', 'arm64') { Stop-PpbWithError "Invalid architecture '$arch'." 2 }
    $entryArg = Get-Effective 'EntryPoint' 'entryPoint' $null
    $includes = @(Get-Effective 'Include' 'include' @())
    $excludes = @(Get-Effective 'Exclude' 'exclude' @())

    # --- Output location ----------------------------------------------------------
    $outputRoot = if ($Output) { Resolve-PpbPath $Output } else { Resolve-PpbPath ([string]$config['outputRoot']) -BasePath $toolkitRoot }
    if (Test-PpbPathInside -Child $outputRoot -Parent $toolkitRoot) { Stop-PpbWithError "Output '$outputRoot' is inside the toolkit repository. Choose a directory outside it." 2 }
    if (Test-PpbPathInside -Child $outputRoot -Parent $projectRoot) { Stop-PpbWithError "Output '$outputRoot' is inside the source project. Choose a directory outside it." 2 }
    $cacheDir = if ($config['cacheDirectory']) { Resolve-PpbPath ([string]$config['cacheDirectory']) -BasePath $toolkitRoot } else { Join-Path $outputRoot '.ppb-cache' }
    New-PpbDirectory $cacheDir | Out-Null
    if (-not (Test-PpbOwnershipMarker $cacheDir)) { Write-PpbOwnershipMarker -Directory $cacheDir -PackageName '.ppb-cache' }

    # --- Analysis -----------------------------------------------------------------
    Write-PpbLog 'Analysing the project (static analysis, no code is executed)' -Level Step
    $analysisPython = if ($BuildPython) { Resolve-PpbPath $BuildPython } else {
        $hosts = @(Find-PpbHostPythons)
        if (-not $hosts.Count) { Stop-PpbWithError 'No Python interpreter found on the build machine. Install Python 3.8+ (python.org) or pass -BuildPython.' 2 }
        [string](@($hosts | Sort-Object { [version]$_.version } -Descending)[0].executable)
    }
    $analysisTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ppb-analysis-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    $report = Invoke-PpbProjectAnalysis -Source $sourcePath -PythonExe $analysisPython -Config $config -ReportPath $analysisTmp -EntryPoint $entryArg -Include $includes
    Assert-PpbAnalysisUsable -Report $report
    $pkgName = Resolve-PpbPackageName -Name (Get-Effective 'Name' 'name' $null) -Report $report -Source $sourcePath

    # --- Package directory (ownership-checked) ---------------------------------------
    $packageDir = Join-Path $outputRoot $pkgName
    if (Test-PpbPathInside -Child $projectRoot -Parent $packageDir) { Stop-PpbWithError "The package directory '$packageDir' would contain the source project." 2 }
    if (Test-Path -LiteralPath $packageDir) {
        $hasContent = @(Get-ChildItem -LiteralPath $packageDir -Force | Select-Object -First 1).Count -gt 0
        if ($hasContent -and -not (Test-PpbOwnershipMarker $packageDir)) {
            Stop-PpbWithError "'$packageDir' exists and was not created by PythonPortableBuilder. Choose another -Name or -Output; nothing was changed." 2
        }
    }
    New-PpbDirectory $packageDir | Out-Null
    Write-PpbOwnershipMarker -Directory $packageDir -PackageName $pkgName
    Move-PpbLog -Path (Join-Path $packageDir 'build.log')
    Copy-Item -LiteralPath $analysisTmp -Destination (Join-Path $packageDir 'analysis.json') -Force
    Remove-Item -LiteralPath $analysisTmp -Force

    $distDir = Join-Path $packageDir 'distribution'
    $workDir = Join-Path $packageDir '.build'
    if ($Clean) {
        Write-PpbLog 'Clean build: removing previous build output of this package' -Level Info
        foreach ($p in $workDir, (Join-Path $packageDir 'pyinstaller')) { Remove-PpbItem -Path $p -OwnerRoot $packageDir }
    }
    Remove-PpbItem -Path $distDir -OwnerRoot $packageDir
    foreach ($f in 'build-manifest.json', 'build-config.json') { $p = Join-Path $packageDir $f; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
    New-PpbDirectory $distDir | Out-Null
    New-PpbDirectory $workDir | Out-Null

    Write-PpbLog "Package: $pkgName ($Type$(if ($Type -eq 'executable') { ", $modeValue" }), $arch) -> $packageDir"
    Write-PpbAnalysisSummary -Report $report

    # --- Files ---------------------------------------------------------------------
    Write-PpbLog 'Selecting project files' -Level Step
    $selection = Get-PpbProjectFileSelection -ProjectRoot $projectRoot -Config $config -SingleFile $(if ($isFile) { $sourcePath } else { $null }) `
        -Include $includes -Exclude $excludes -ProtectedPaths @($outputRoot, $toolkitRoot)
    Assert-PpbNoBlockedFiles -Selection $selection
    if ($report.entryPoint.kind -eq 'script') {
        $entryRel = ([string]$report.entryPoint.path).Replace('\', '/')
        if (-not (@($selection.Included) | Where-Object { $_.RelativePath -eq $entryRel })) { Stop-PpbWithError "The entry script '$entryRel' is excluded by the include/exclude rules." 2 }
    }
    $resources = @(Get-PpbResourceFiles -Files $selection.Included)
    Write-PpbLog ("{0} file(s) selected ({1} resource file(s)); {2} excluded; {3} sensitive file(s) withheld" -f @($selection.Included).Count, $resources.Count, @($selection.Excluded).Count, @($selection.Sensitive).Count) -Level Success

    # --- Python target -----------------------------------------------------------------
    Write-PpbLog 'Resolving the Python version' -Level Step
    $requestedPy = Get-Effective 'PythonVersion' 'pythonVersion' $null
    if (-not $requestedPy) { $requestedPy = Get-PpbValue $report 'pythonVersionFile' $null }
    if ($requestedPy -and $requestedPy -notmatch '^\d+\.\d+(\.\d+)?$') { Stop-PpbWithError "Unsupported Python version '$requestedPy' (from .python-version/runtime.txt/ppb.json). Use -PythonVersion X.Y[.Z]." 2 }
    $spec = Get-PpbValue $report 'pythonRequirement' $null
    $target = Resolve-PpbPythonTarget -RequestedVersion $requestedPy -Specifier $(if ($spec) { $spec.specifier }) -SpecifierSource $(if ($spec) { $spec.source }) `
        -Type $Type -Architecture $arch -BuildPython $BuildPython
    if ($spec -and $target.Version -and -not (Test-PpbVersionSpecifier -Version $target.Version -Specifier $spec.specifier)) {
        Stop-PpbWithError "Python $($target.Version) does not satisfy the project's requirement '$($spec.specifier)' ($($spec.source))." 2
    }
    Write-PpbLog ("Target Python {0} [{1}] ({2}); build interpreter {3}" -f $(if ($target.Version) { $target.Version } else { "$($target.MajorMinor).x" }), $arch, $target.Reason, $target.BuildPython.version) -Level Success

    # --- Requirements ---------------------------------------------------------------------
    $reqInfo = Resolve-PpbRequirements -Report $report -ProjectRoot $projectRoot -WorkDirectory $workDir `
        -Requirements (Get-Effective 'Requirements' 'requirements' $null) -InferRequirements:$InferRequirements
    if ($reqInfo.File) { Write-PpbLog ("Dependencies: {0} requirement(s) from {1}" -f @($reqInfo.Lines).Count, $reqInfo.Kind) -Level Success }

    # --- Context ---------------------------------------------------------------------------
    $dataFiles = @(@(Get-Effective 'DataFile' 'dataFiles' @()) | ForEach-Object { ConvertFrom-PpbDataFileSpec -Spec $_ -ProjectRoot $projectRoot })
    $safe = @(Get-Effective 'SafeTestArgs' 'safeTestArgs' @($report.safeTestArgs))
    $safeReason = if ($script:Bound.ContainsKey('SafeTestArgs') -or $script:ProjectConfig.Contains('safeTestArgs')) { 'specified by the user' } else { [string](Get-PpbValue $report 'safeTestReason' '') }
    if ($safe.Count -eq 1 -and $safe[0] -eq 'none') { $safe = @(); $safeReason = 'disabled by the user' }
    $ctx = @{
        Name = $pkgName; Type = $Type; Mode = $modeValue; Architecture = $arch
        Windowed = [bool](Get-Effective 'Windowed' 'windowed' $false)
        WorkingDirectory = Get-Effective 'WorkingDirectory' 'workingDirectory' $config['workingDirectory']
        SourcePath = $sourcePath; ProjectRoot = $projectRoot; OutputRoot = $outputRoot; PackageDir = $packageDir
        DistDir = $distDir; WorkDir = $workDir; CacheDir = $cacheDir; Config = $config; Report = $report; Entry = $report.entryPoint
        Selection = $selection; Resources = $resources; Requirements = $reqInfo; PythonTarget = $target
        RequestedPythonVersion = $requestedPy; RuntimeZip = $RuntimeZip; Clean = [bool]$Clean
        HiddenImports = @(Get-Effective 'HiddenImport' 'hiddenImports' @()); DataFiles = $dataFiles
        AdditionalPaths = @(Get-Effective 'AdditionalPath' 'additionalPaths' @()); CollectPackages = @(Get-Effective 'CollectPackage' 'collectPackages' @())
        Icon = Get-Effective 'Icon' 'icon' $null; SpecFile = Get-Effective 'SpecFile' 'specFile' $null
        SafeTestArgs = $safe; SafeTestReason = $safeReason; DllDirectories = @()
        AllowUnresolvedImports = [bool]$AllowUnresolvedImports; CreateZip = $CreateZip
        UserPrerequisites = @(Get-PpbValue $script:ProjectConfig 'externalPrerequisites' @())
        ToolkitVersion = $version; StartTime = $startTime
        SourceRevision = (Get-PpbSourceRevision -ProjectRoot $projectRoot)
    }
    if ($ctx.Type -eq 'executable' -and $ctx.WorkingDirectory -ne $config['workingDirectory'] -and $script:Bound.ContainsKey('WorkingDirectory')) {
        Write-PpbLog '-WorkingDirectory applies to embedded launchers only; executables start in the caller''s directory.' -Level Warn
    }

    # --- Build -------------------------------------------------------------------------------
    $result = if ($Type -eq 'embedded') { Invoke-PpbEmbeddedBuild -Context $ctx } else { Invoke-PpbExecutableBuild -Context $ctx }

    # --- Documentation, manifest, checksums ---------------------------------------------------
    Write-PpbLog 'Writing documentation, manifest and checksums' -Level Step
    Copy-Item -LiteralPath (Get-PpbTemplatePath 'distribution\verify.ps1') -Destination (Join-Path $distDir 'verify.ps1') -Force
    $manifest = New-PpbBuildManifest -Context $ctx -BuildResult $result
    New-PpbDeploymentDocuments -Context $ctx -Manifest $manifest
    Write-PpbJsonFile -Path (Join-Path $distDir 'build-manifest.json') -Data $manifest
    $sums = New-PpbChecksumFile -Root $distDir
    Write-PpbLog "SHA256SUMS written for $sums file(s)" -Level Success
    foreach ($p in $manifest.externalPrerequisites) { Write-PpbLog ("External prerequisite: {0} ({1}) - {2}" -f $p.name, $p.category, $p.detail) -Level Info }

    # --- Validation --------------------------------------------------------------------------
    $validation = $null
    if ($Verify) {
        Write-PpbLog 'Validating the distribution' -Level Step
        $buildPaths = @($projectRoot, $packageDir, $toolkitRoot, [string]$target.BuildPython.basePrefix, [string]$target.BuildPython.prefix) | Where-Object { $_ }
        $validation = Invoke-PpbDistributionValidation -DistributionPath $distDir -BuildPaths $buildPaths -InTempCopy:([bool]$config['verifyInTempCopy']) `
            -TimeoutSeconds ([int]$config['timeouts']['appProbeSeconds'])
        Write-PpbValidationSummary -Validation $validation
    } else {
        Write-PpbLog 'Validation skipped (-Verify:$false).' -Level Warn
    }
    $manifest = New-PpbBuildManifest -Context $ctx -BuildResult $result -Validation $validation
    $stats = Get-PpbDirectoryStatistics -Path $distDir
    $manifest.artifacts['distribution'] = $stats
    if ($Type -eq 'executable') {
        $exe = Join-Path $distDir "$pkgName.exe"
        $manifest.artifacts['executable'] = [ordered]@{ name = "$pkgName.exe"; sha256 = (Get-PpbFileSha256 $exe); sizeBytes = (Get-Item -LiteralPath $exe).Length }
    }
    Write-PpbJsonFile -Path (Join-Path $distDir 'build-manifest.json') -Data $manifest

    $failed = $validation -and $validation.Status -eq 'failed'
    if (-not $failed -and $CreateZip) {
        Write-PpbLog 'Creating the ZIP distribution' -Level Step
        $zipPath = Join-Path $outputRoot (Get-PpbZipFileName -Name $pkgName -Type $Type -Mode $modeValue)
        $zipInfo = New-PpbDistributionZip -DistributionPath $distDir -ZipPath $zipPath -RootFolderName $pkgName -PackageDirectory $packageDir
        $manifest.artifacts['zip'] = $zipInfo
        Write-PpbLog ("{0} ({1:N1} MB, sha256 {2})" -f $zipPath, ($zipInfo.sizeBytes / 1MB), $zipInfo.sha256) -Level Success
    } elseif ($failed -and $CreateZip) {
        Write-PpbLog 'ZIP not created because validation failed.' -Level Warn
    }
    Write-PpbJsonFile -Path (Join-Path $packageDir 'build-manifest.json') -Data $manifest

    # Reusable configuration for rebuild.ps1 (explicit parameters only; ppb.json is re-read).
    $saved = [ordered]@{ toolkitVersion = $version; savedUtc = [DateTime]::UtcNow.ToString('o'); parameters = [ordered]@{} }
    foreach ($k in ($script:Bound.Keys | Sort-Object)) {
        if ($k -in 'Output', 'Clean', 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'InformationVariable') { continue }
        $v = $script:Bound[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { $v = [bool]$v }
        $saved.parameters[$k] = $v
    }
    $saved.parameters['Source'] = $sourcePath
    $saved.parameters['Name'] = $pkgName
    Write-PpbJsonFile -Path (Join-Path $packageDir 'build-config.json') -Data $saved
    Write-PpbOwnershipMarker -Directory $packageDir -PackageName $pkgName

    Write-PpbLog 'Summary' -Level Step
    Write-PpbLog "Distribution : $distDir"
    if ($manifest.artifacts.Contains('zip')) { Write-PpbLog "ZIP          : $(Join-Path $outputRoot $manifest.artifacts.zip.name)" }
    Write-PpbLog "Manifest     : $(Join-Path $packageDir 'build-manifest.json')"
    Write-PpbLog "Build log    : $(Join-Path $packageDir 'build.log')"
    Write-PpbLog "Run          : $($result.RunCommand)"
    $warnCount = @(Get-PpbLogWarnings).Count
    if ($failed) {
        Write-PpbLog "BUILD COMPLETED BUT VALIDATION FAILED - review the failed checks above ($warnCount warning(s))." -Level Error
        $exitCode = 3
    } else {
        Write-PpbLog ("Build succeeded in {0:N0} s with {1} warning(s)." -f ((Get-Date) - $startTime).TotalSeconds, $warnCount) -Level Success
    }
} catch {
    $exitCode = Get-PpbErrorExitCode $_
    Write-PpbLog $_.Exception.Message -Level Error
    if ($exitCode -eq 1 -and (Test-PpbVerboseLogging)) { Write-PpbLog $_.ScriptStackTrace -Level Debug }
    $logFile = Get-PpbLogFile
    if ($logFile) { Write-Host "  See the build log: $logFile" -ForegroundColor DarkGray }
}
exit $exitCode
