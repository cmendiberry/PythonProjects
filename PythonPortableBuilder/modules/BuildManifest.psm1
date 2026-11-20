#Requires -Version 5.1
<#
    BuildManifest.psm1 - build-manifest.json, prerequisites, limitations and the
    README.md / DEPLOYMENT.md shipped with every distribution.

    The manifest never contains credentials, environment variable VALUES, or absolute
    build-machine paths (only the names of the source project and files).
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'DependencyManager.psm1') -DisableNameChecking

<#
.SYNOPSIS
    Returns git revision information of the source project, when available.
#>
function Get-PpbSourceRevision {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) { return [ordered]@{ vcs = $null; revision = $null; dirty = $null; note = 'git not available' } }
    try {
        $r = Invoke-PpbProcess -FilePath $git.Source -ArgumentList @('-C', $ProjectRoot, 'rev-parse', 'HEAD') -Quiet -TimeoutSeconds 30
        if ($r.ExitCode -ne 0) { return [ordered]@{ vcs = $null; revision = $null; dirty = $null; note = 'not a git repository' } }
        $rev = $r.StdOut.Trim()
        $s = Invoke-PpbProcess -FilePath $git.Source -ArgumentList @('-C', $ProjectRoot, 'status', '--porcelain', '--', '.') -Quiet -TimeoutSeconds 60
        return [ordered]@{ vcs = 'git'; revision = $rev; dirty = [bool]($s.StdOut.Trim()); note = $null }
    } catch {
        return [ordered]@{ vcs = $null; revision = $null; dirty = $null; note = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Combines analysis findings, native DLL findings and user declarations into
    the list of external (non-Python) prerequisites.
#>
function Get-PpbExternalPrerequisites {
    param([Parameter(Mandatory)][hashtable]$Context, [hashtable]$BuildResult)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Get-PpbValue $Context.Report 'externalPrerequisites' @())) {
        $list.Add([ordered]@{ category = $p.category; name = $p.name; detail = $p.detail; evidence = @($p.evidence) })
    }
    if ($BuildResult -and $BuildResult.NativeReport) {
        foreach ($m in @($BuildResult.NativeReport.missing)) {
            $list.Add([ordered]@{ category = 'native-library'; name = $m.dll; detail = (Get-PpbDllPrerequisiteHint $m.dll); evidence = @($m.requiredBy) })
        }
    }
    foreach ($u in @($Context.UserPrerequisites)) {
        if ($u) { $list.Add([ordered]@{ category = 'declared'; name = [string]$u; detail = 'Declared in ppb.json'; evidence = @() }) }
    }
    return $list.ToArray()
}

function Get-PpbKnownLimitations {
    param([Parameter(Mandatory)][hashtable]$Context, [hashtable]$BuildResult)
    $l = New-Object System.Collections.Generic.List[string]
    $r = $Context.Report
    $l.Add('External prerequisites (ODBC drivers, database client libraries, certificates, credentials, network access) are not bundled.')
    $l.Add('Compatibility with a specific Windows (Server) version is not guaranteed; it follows the support policy of the bundled Python version and of the native packages.')
    if ($Context.Type -eq 'embedded') {
        $l.Add('Requires permission to execute runtime\python.exe; application-control policies (AppLocker, WDAC) and antivirus products are not bypassed.')
    } else {
        $l.Add('The executable was produced by PyInstaller; successful packaging does not prove that every runtime code path works.')
        if ($Context.Mode -eq 'onefile') { $l.Add('onefile executables extract their contents to a temporary directory (%TEMP%\_MEI*) at every start; restricted or monitored TEMP folders can block or slow startup.') }
        $l.Add('Antivirus products sometimes flag PyInstaller bootloaders; code-signing the executable reduces false positives.')
    }
    if (-not @($Context.SafeTestArgs).Count) { $l.Add('No safe test option is known for this application: validation did not execute the application itself.') }
    if (@(Get-PpbValue $r 'workingDirectoryAssumptions' @()).Count) { $l.Add('The application opens files relative to the current working directory; see the build analysis (analysis.json).') }
    if (@(Get-PpbValue $r 'hardcodedAbsolutePaths' @()).Count) { $l.Add('The application contains hardcoded absolute paths that were not modified.') }
    if (@(@(Get-PpbValue $r 'dynamicImports' @()) | Where-Object { -not $_.module }).Count) { $l.Add('Dynamic imports with computed module names cannot be verified statically.') }
    if ($Context.Requirements -and -not $Context.Requirements.Locked -and $Context.Requirements.Kind -ne 'none') { $l.Add('Dependencies were resolved from version ranges; the installed versions are listed in this manifest.') }
    return $l.ToArray()
}

<#
.SYNOPSIS
    Builds the manifest object (ordered hashtable).
#>
function New-PpbBuildManifest {
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][hashtable]$BuildResult, $Validation)
    $ctx = $Context
    $inv = $BuildResult.Inventory
    $deps = @()
    if ($inv) {
        foreach ($d in @($inv.distributions)) {
            $deps += [ordered]@{ name = $d.name; version = $d.version; license = $d.license; native = [bool]$d.hasNative; wheelTags = @($d.wheelTags) }
        }
    }
    $entry = $ctx.Entry
    $entryOut = [ordered]@{ kind = $entry.kind; display = $entry.display; selection = $entry.selectionReason }
    foreach ($k in 'path', 'module', 'function') { $v = Get-PpbValue $entry $k; if ($v) { $entryOut[$k] = $v } }
    $req = $ctx.Requirements
    $m = [ordered]@{
        schemaVersion = 1
        toolkit       = [ordered]@{ name = 'PythonPortableBuilder'; version = $ctx.ToolkitVersion }
        package       = [ordered]@{
            name = $ctx.Name; type = $ctx.Type; mode = $(if ($ctx.Type -eq 'executable') { $ctx.Mode } else { $null })
            architecture = $ctx.Architecture; windowed = [bool]$ctx.Windowed; workingDirectory = $(if ($ctx.Type -eq 'embedded') { $ctx.WorkingDirectory } else { 'caller' })
            run = $BuildResult.RunCommand
        }
        entryPoint    = $entryOut
        python        = [ordered]@{
            version = $ctx.PythonTarget.Version; architecture = $ctx.Architecture; implementation = 'CPython'
            selection = $ctx.PythonTarget.Reason; runtime = $BuildResult.Runtime
            buildInterpreter = [ordered]@{ version = [string]$ctx.PythonTarget.BuildPython.version; architecture = [string]$ctx.PythonTarget.BuildPython.architecture; crossInstall = [bool]$ctx.PythonTarget.CrossInstall }
        }
        dependencies  = [ordered]@{
            source = [ordered]@{ kind = $req.Kind; file = $(if ($req.SourceFile) { Split-Path -Leaf $req.SourceFile } else { $null }); locked = [bool]$req.Locked }
            requirements = @($req.Lines | ForEach-Object { Protect-PpbText $_ })
            installed = $deps
            importNames = @($BuildResult.ImportNames)
            unresolvedImports = @($BuildResult.MissingImports)
        }
        build         = [ordered]@{
            timestampUtc = $ctx.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            durationSeconds = [math]::Round(((Get-Date) - $ctx.StartTime).TotalSeconds, 1)
            host = [ordered]@{ os = [Environment]::OSVersion.VersionString; powershell = $PSVersionTable.PSVersion.ToString() }
            source = [ordered]@{ name = (Split-Path -Leaf $ctx.SourcePath); kind = $ctx.Report.sourceKind; layout = $ctx.Report.layout; revision = $ctx.SourceRevision }
        }
        application   = [ordered]@{
            types = @($ctx.Report.applicationTypes); cliFrameworks = @($ctx.Report.cliFrameworks)
            environmentVariables = @(@($ctx.Report.environmentVariables) | ForEach-Object { [ordered]@{ name = $_.name; required = [bool]$_.required } })
        }
        distribution  = [ordered]@{ requiredFiles = @($BuildResult.RequiredFiles) }
        bundledResources = @($BuildResult.BundledResources)
        resources     = @($ctx.Resources)
        externalPrerequisites = @(Get-PpbExternalPrerequisites -Context $ctx -BuildResult $BuildResult)
        knownLimitations = @(Get-PpbKnownLimitations -Context $ctx -BuildResult $BuildResult)
        validation    = [ordered]@{ safeTestArgs = @($ctx.SafeTestArgs); safeTestReason = $ctx.SafeTestReason; status = 'not-run'; results = @() }
        artifacts     = [ordered]@{}
    }
    if ($BuildResult.ContainsKey('Embedded')) { $m['embedded'] = $BuildResult.Embedded }
    if ($BuildResult.ContainsKey('PyInstaller')) { $m['pyinstaller'] = $BuildResult.PyInstaller }
    if ($Validation) { $m.validation.status = $Validation.Status; $m.validation.timestampUtc = $Validation.TimestampUtc; $m.validation.results = @($Validation.Results) }
    return $m
}

function ConvertTo-PpbMarkdownList {
    param([object[]]$Items, [string]$Empty = '_None detected._')
    if (-not $Items -or @($Items).Count -eq 0) { return $Empty }
    return ((@($Items) | ForEach-Object { "* $_" }) -join "`n")
}

<#
.SYNOPSIS
    Renders README.md and DEPLOYMENT.md into the distribution.
#>
function New-PpbDeploymentDocuments {
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest)
    $ctx = $Context
    $isEmbedded = $ctx.Type -eq 'embedded'
    $typeDesc = if ($isEmbedded) { 'Embedded Python (official CPython embeddable runtime)' } else { "Standalone executable (PyInstaller $($ctx.Mode))" }
    $layout = if ($isEmbedded) {
        "$($ctx.Name)\`n  run.cmd / run.ps1     launchers`n  runtime\              official Python runtime`n  packages\             third-party packages`n  app\                  application files`n  launcher\             launcher and self-test`n  config\  logs\`n  verify.ps1  build-manifest.json  SHA256SUMS"
    } elseif ($ctx.Mode -eq 'onedir') {
        "$($ctx.Name)\`n  $($ctx.Name).exe`n  _internal\            bundled Python runtime, packages and resources`n  verify.ps1  build-manifest.json  SHA256SUMS"
    } else {
        "$($ctx.Name)\`n  $($ctx.Name).exe       single-file executable`n  verify.ps1  build-manifest.json  SHA256SUMS"
    }
    $prereq = @($Manifest.externalPrerequisites | ForEach-Object { "**$($_.name)** ($($_.category)): $($_.detail)" })
    $envs = @($Manifest.application.environmentVariables | ForEach-Object { "``$($_.name)``" + $(if ($_.required) { ' (required)' } else { '' }) })
    $update = if ($isEmbedded) {
        "Application-only updates: replace the files under ``app\`` (keep the directory structure) and run ``verify.ps1``. " +
        "The runtime and packages do not need to be rebuilt as long as:`n`n* the dependencies and their versions stay compatible,`n* the required Python version does not change,`n" +
        "* the entry point and application structure stay valid,`n* native dependencies do not change.`n`n" +
        "Rebuild the whole package (``rebuild.ps1``) when requirements, the Python version, the entry point or native libraries change. " +
        "``verify.ps1`` reports changed application files as warnings."
    } else { 'Executables are immutable: rebuild the package with the toolkit (rebuild.ps1) and redeploy the whole directory.' }
    $zip = if ($ctx.CreateZip) { Get-PpbZipFileNameLocal $ctx } else { "$($ctx.Name).zip" }
    $run = if ($isEmbedded) { "run.cmd [arguments]" } else { "$($ctx.Name).exe [arguments]" }
    $tokens = @{
        NAME = $ctx.Name; TOOLKIT_VERSION = $ctx.ToolkitVersion; BUILD_TIME = $Manifest.build.timestampUtc; TYPE_DESCRIPTION = $typeDesc
        PYTHON_VERSION = $Manifest.python.version; ARCH = $ctx.Architecture; ENTRY = $Manifest.entryPoint.display
        WORKING_DIRECTORY = $(if ($isEmbedded -and $ctx.WorkingDirectory -eq 'app') { 'the application directory (app\)' } else { "the caller's current directory" })
        RUN_COMMAND = $run; LAYOUT = $layout; PREREQUISITES = (ConvertTo-PpbMarkdownList $prereq)
        ENV_VARS = (ConvertTo-PpbMarkdownList $envs '_None detected._'); UPDATE_SECTION = $update
        LIMITATIONS = (ConvertTo-PpbMarkdownList @($Manifest.knownLimitations)); ZIP_NAME = $zip
        EXECUTION_REQUIREMENT = $(if ($isEmbedded) { 'runtime\python.exe (and run.cmd)' } else { "$($ctx.Name).exe" })
    }
    Write-PpbTextFile -Path (Join-Path $ctx.DistDir 'README.md') -Content (Expand-PpbTemplate (Get-PpbTemplatePath 'deployment\README.template.md') $tokens)
    Write-PpbTextFile -Path (Join-Path $ctx.DistDir 'DEPLOYMENT.md') -Content (Expand-PpbTemplate (Get-PpbTemplatePath 'deployment\DEPLOYMENT.template.md') $tokens)
}

function Get-PpbZipFileNameLocal {
    param([hashtable]$Context)
    if ($Context.Type -eq 'executable') { return "$($Context.Name)-executable-$($Context.Mode).zip" }
    return "$($Context.Name)-embedded.zip"
}

Export-ModuleMember -Function Get-PpbSourceRevision, Get-PpbExternalPrerequisites, Get-PpbKnownLimitations, New-PpbBuildManifest, New-PpbDeploymentDocuments
