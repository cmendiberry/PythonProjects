#Requires -Version 5.1
<#
    Common.psm1 - shared infrastructure for PythonPortableBuilder.

    Responsibilities:
      * Structured logging (console + build.log)
      * Toolkit configuration loading (config/defaults.json + config/local.json + env overrides)
      * Safe path resolution and destructive-operation guards
      * Ownership markers for output directories
      * External process execution with correct Windows argument quoting,
        streaming output, environment control and timeouts
      * Small helpers (JSON I/O without BOM, hashing, wildcard matching)

    Every other module depends on this one. Keep it free of packaging logic.
#>

Set-StrictMode -Version 2.0

$script:ToolkitRoot = Split-Path -Parent $PSScriptRoot
$script:OwnershipMarkerName = '.ppb-owned.json'
$script:Log = @{
    File      = $null
    Verbose   = $false
    Warnings  = New-Object System.Collections.Generic.List[string]
    Errors    = New-Object System.Collections.Generic.List[string]
    Secrets   = New-Object System.Collections.Generic.List[string]
}

#region Errors -----------------------------------------------------------------

<#
.SYNOPSIS
    Throws a terminating error carrying a PythonPortableBuilder exit code.
.DESCRIPTION
    Exit codes: 1 = general/build failure, 2 = invalid input or ambiguous
    configuration, 3 = validation failure. Entry scripts translate the
    'PpbExitCode' data entry into the process exit code.
#>
function Stop-PpbWithError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateRange(1, 255)][int]$ExitCode = 1
    )
    $ex = New-Object System.InvalidOperationException $Message
    $ex.Data['PpbExitCode'] = $ExitCode
    throw $ex
}

function Get-PpbErrorExitCode {
    param([Parameter(Mandatory)]$ErrorRecord)
    $ex = $ErrorRecord
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ex = $ErrorRecord.Exception }
    while ($null -ne $ex) {
        if ($ex.Data -and $ex.Data.Contains('PpbExitCode')) { return [int]$ex.Data['PpbExitCode'] }
        $ex = $ex.InnerException
    }
    return 1
}

#endregion

#region Logging ----------------------------------------------------------------

function Initialize-PpbLog {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$VerboseOutput,
        [switch]$Append
    )
    $script:Log.Verbose = [bool]$VerboseOutput
    $script:Log.Warnings.Clear()
    $script:Log.Errors.Clear()
    $script:Log.File = $null
    if ($Path) {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (-not $Append -and (Test-Path -LiteralPath $Path)) { Remove-Item -LiteralPath $Path -Force }
        $script:Log.File = $Path
    }
}

<#
.SYNOPSIS
    Registers a literal string that must never appear in logs (it is replaced by ***).
#>
function Register-PpbSecret {
    param([string]$Value)
    if ($Value -and $Value.Length -ge 4 -and -not $script:Log.Secrets.Contains($Value)) { $script:Log.Secrets.Add($Value) }
}

<#
.SYNOPSIS
    Removes credentials from text: URL user-info, registered secrets.
#>
function Protect-PpbText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $result = [regex]::Replace($Text, '(?i)\b([a-z][a-z0-9+.\-]*://)[^/\s:@]+(:[^/\s@]*)?@', '$1***@')
    foreach ($s in $script:Log.Secrets) { $result = $result.Replace($s, '***') }
    return $result
}

function Write-PpbLog {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$Message = '',
        [ValidateSet('Debug', 'Info', 'Step', 'Success', 'Warn', 'Error', 'Output')][string]$Level = 'Info',
        [switch]$NoConsole
    )
    $Message = Protect-PpbText $Message
    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $tag = $Level.ToUpperInvariant().PadRight(7)
    if ($script:Log.File) {
        try {
            [System.IO.File]::AppendAllText($script:Log.File, "$stamp [$tag] $Message`r`n", (New-Object System.Text.UTF8Encoding $false))
        } catch {
            # Logging must never break a build.
        }
    }
    if ($Level -eq 'Warn') { $script:Log.Warnings.Add($Message) }
    if ($Level -eq 'Error') { $script:Log.Errors.Add($Message) }
    if ($NoConsole) { return }
    switch ($Level) {
        'Debug'   { if ($script:Log.Verbose) { Write-Host "  [debug] $Message" -ForegroundColor DarkGray } }
        'Output'  { if ($script:Log.Verbose) { Write-Host "    | $Message" -ForegroundColor DarkGray } }
        'Info'    { Write-Host "  $Message" }
        'Step'    { Write-Host ''; Write-Host "==> $Message" -ForegroundColor Cyan }
        'Success' { Write-Host "  [ok] $Message" -ForegroundColor Green }
        'Warn'    { Write-Host "  [warning] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "  [error] $Message" -ForegroundColor Red }
    }
}

<#
.SYNOPSIS
    Moves the current log (e.g. from a temporary location) to its final path and continues there.
#>
function Move-PpbLog {
    param([Parameter(Mandatory)][string]$Path)
    $old = $script:Log.File
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content = ''
    if ($old -and (Test-Path -LiteralPath $old)) { $content = [System.IO.File]::ReadAllText($old) }
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding $false))
    $script:Log.File = $Path
    if ($old -and $old -ne $Path -and (Test-Path -LiteralPath $old)) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
}

function Get-PpbLogWarnings { return $script:Log.Warnings.ToArray() }
function Get-PpbLogFile { return $script:Log.File }
function Test-PpbVerboseLogging { return [bool]$script:Log.Verbose }

#endregion

#region Configuration ----------------------------------------------------------

function Get-PpbToolkitRoot { return $script:ToolkitRoot }

function Get-PpbToolkitVersion {
    $versionFile = Join-Path $script:ToolkitRoot 'VERSION'
    if (Test-Path -LiteralPath $versionFile) { return (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim() }
    return '0.0.0'
}

<#
.SYNOPSIS
    Converts PSCustomObject trees (from ConvertFrom-Json) into ordered hashtables.
#>
function ConvertTo-PpbHashtable {
    param([AllowNull()]$InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-PpbHashtable $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-PpbHashtable $p.Value }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($i in $InputObject) { $list += , (ConvertTo-PpbHashtable $i) }
        return , $list
    }
    return $InputObject
}

function Merge-PpbHashtable {
    param([System.Collections.IDictionary]$Base, [System.Collections.IDictionary]$Override)
    $result = [ordered]@{}
    if ($Base) { foreach ($k in $Base.Keys) { $result[$k] = $Base[$k] } }
    if ($Override) {
        foreach ($k in $Override.Keys) {
            if ($result.Contains($k) -and $result[$k] -is [System.Collections.IDictionary] -and $Override[$k] -is [System.Collections.IDictionary]) {
                $result[$k] = Merge-PpbHashtable $result[$k] $Override[$k]
            } else {
                $result[$k] = $Override[$k]
            }
        }
    }
    return $result
}

function Read-PpbJsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-PpbWithError "JSON file not found: $Path" 2 }
    $text = [System.IO.File]::ReadAllText($Path)
    try {
        return ($text | ConvertFrom-Json)
    } catch {
        Stop-PpbWithError "Invalid JSON in '$Path': $($_.Exception.Message)" 2
    }
}

function Write-PpbJsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowNull()]$Data, [int]$Depth = 32)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = ConvertTo-Json -InputObject $Data -Depth $Depth
    Write-PpbTextFile -Path $Path -Content $json
}

<#
.SYNOPSIS
    Writes text as UTF-8 without BOM. Optionally normalises line endings to CRLF.
#>
function Write-PpbTextFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content, [switch]$Crlf)
    if ($Crlf) { $Content = ($Content -replace "`r`n", "`n") -replace "`n", "`r`n" }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

<#
.SYNOPSIS
    Loads toolkit configuration: defaults.json, optional local.json, PPB_* env overrides.
#>
function Get-PpbConfig {
    $defaultsPath = Join-Path $script:ToolkitRoot 'config\defaults.json'
    $config = ConvertTo-PpbHashtable (Read-PpbJsonFile $defaultsPath)
    $localPath = Join-Path $script:ToolkitRoot 'config\local.json'
    if (Test-Path -LiteralPath $localPath) {
        $config = Merge-PpbHashtable $config (ConvertTo-PpbHashtable (Read-PpbJsonFile $localPath))
    }
    if ($env:PPB_OUTPUT_ROOT) { $config['outputRoot'] = $env:PPB_OUTPUT_ROOT }
    if ($env:PPB_CACHE_DIR) { $config['cacheDirectory'] = $env:PPB_CACHE_DIR }
    return $config
}

#endregion

#region Paths ------------------------------------------------------------------

<#
.SYNOPSIS
    Resolves a path (absolute or relative to -BasePath / current location) to a
    normalised absolute path. The path does not need to exist.
#>
function Resolve-PpbPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$BasePath
    )
    $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        if (-not $BasePath) { $BasePath = (Get-Location -PSProvider FileSystem).ProviderPath }
        $p = Join-Path $BasePath $p
    }
    $full = [System.IO.Path]::GetFullPath($p)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\', '/') }
    return $full
}

function Test-PpbPathEqual {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    return [string]::Equals((Resolve-PpbPath $A), (Resolve-PpbPath $B), [StringComparison]::OrdinalIgnoreCase)
}

<#
.SYNOPSIS
    True when $Child equals $Parent or is located below it.
#>
function Test-PpbPathInside {
    param([string]$Child, [string]$Parent)
    if (-not $Child -or -not $Parent) { return $false }
    $c = (Resolve-PpbPath $Child).TrimEnd('\') + '\'
    $p = (Resolve-PpbPath $Parent).TrimEnd('\') + '\'
    return $c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
}

function Get-PpbRelativePath {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$BasePath)
    $base = (Resolve-PpbPath $BasePath).TrimEnd('\') + '\'
    $full = Resolve-PpbPath $Path
    if (-not ($full + '\').StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-PpbWithError "Path '$full' is not inside '$base'."
    }
    if ($full.Length + 1 -eq $base.Length) { return '.' }
    return $full.Substring($base.Length)
}

function New-PpbDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return $Path
}

<#
.SYNOPSIS
    Returns a list of directories that must never be deleted by the toolkit.
#>
function Get-PpbProtectedPaths {
    param([string[]]$Additional)
    $list = New-Object System.Collections.Generic.List[string]
    $candidates = @($script:ToolkitRoot, $env:USERPROFILE, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, $env:PUBLIC, [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'), [System.IO.Path]::GetTempPath())
    if ($Additional) { $candidates += $Additional }
    foreach ($c in $candidates) { if ($c) { $list.Add((Resolve-PpbPath $c)) } }
    return $list.ToArray()
}

<#
.SYNOPSIS
    Guard executed before every recursive delete performed by the toolkit.
.DESCRIPTION
    A path may only be removed when ALL of the following hold:
      * it is absolute and not a drive root;
      * it is not, and does not contain, a protected path (toolkit repository,
        user profile, Windows, Program Files, temp root, the source project ...);
      * it lies inside -OwnerRoot, and -OwnerRoot carries a valid ownership marker
        (or the path itself is inside a temp directory created by the toolkit
        and -AllowTempOwned is set).
#>
function Assert-PpbSafeToRemove {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$OwnerRoot,
        [string[]]$ProtectedPaths,
        [switch]$AllowTempOwned
    )
    $full = Resolve-PpbPath $Path
    $root = [System.IO.Path]::GetPathRoot($full)
    if (-not $root -or $full.TrimEnd('\') -eq $root.TrimEnd('\')) { Stop-PpbWithError "Refusing to remove drive root '$full'." }
    if ($full.Split('\').Where({ $_ }).Count -lt 2) { Stop-PpbWithError "Refusing to remove top-level directory '$full'." }
    foreach ($p in (Get-PpbProtectedPaths -Additional $ProtectedPaths)) {
        if (Test-PpbPathInside -Child $p -Parent $full) {
            Stop-PpbWithError "Refusing to remove '$full': it is or contains protected path '$p'."
        }
    }
    if ($AllowTempOwned) {
        $leaf = Split-Path -Leaf $full
        if ((Test-PpbPathInside -Child $full -Parent ([System.IO.Path]::GetTempPath())) -and $leaf -like 'ppb-*') { return }
        $parentLeaf = Split-Path -Leaf (Split-Path -Parent $full)
        if ((Test-PpbPathInside -Child $full -Parent ([System.IO.Path]::GetTempPath())) -and $parentLeaf -like 'ppb-*') { return }
    }
    if (-not $OwnerRoot) { Stop-PpbWithError "Refusing to remove '$full': no owning output directory was specified." }
    if (-not (Test-PpbPathInside -Child $full -Parent $OwnerRoot)) {
        Stop-PpbWithError "Refusing to remove '$full': it is outside the owned directory '$OwnerRoot'."
    }
    if (-not (Test-PpbOwnershipMarker -Directory $OwnerRoot)) {
        Stop-PpbWithError "Refusing to remove '$full': '$OwnerRoot' is not marked as created by PythonPortableBuilder ($script:OwnershipMarkerName missing or invalid)."
    }
}

<#
.SYNOPSIS
    Recursively removes a directory or file after passing Assert-PpbSafeToRemove.
#>
function Remove-PpbItem {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$OwnerRoot,
        [string[]]$ProtectedPaths,
        [switch]$AllowTempOwned
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Assert-PpbSafeToRemove -Path $Path -OwnerRoot $OwnerRoot -ProtectedPaths $ProtectedPaths -AllowTempOwned:$AllowTempOwned
    $full = Resolve-PpbPath $Path
    Write-PpbLog "Removing $full" -Level Debug
    # Long-path / read-only safe removal with retries (antivirus scanners briefly lock new files).
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            if (Test-Path -LiteralPath $full -PathType Container) {
                Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReadOnly } |
                    ForEach-Object { $_.Attributes = $_.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) }
                [System.IO.Directory]::Delete($full, $true)
            } else {
                [System.IO.File]::Delete($full)
            }
            return
        } catch {
            if ($attempt -eq 5) { Stop-PpbWithError "Could not remove '$full': $($_.Exception.Message)" }
            Start-Sleep -Milliseconds (300 * $attempt)
        }
    }
}

function New-PpbTempDirectory {
    param([string]$Prefix = 'ppb')
    $name = '{0}-{1}' -f $Prefix, ([Guid]::NewGuid().ToString('N').Substring(0, 12))
    if ($name -notlike 'ppb-*') { $name = "ppb-$name" }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) $name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return (Resolve-PpbPath $path)
}

#endregion

#region Ownership markers ------------------------------------------------------

function Get-PpbOwnershipMarkerPath { param([string]$Directory) return (Join-Path $Directory $script:OwnershipMarkerName) }

function Test-PpbOwnershipMarker {
    param([Parameter(Mandatory)][string]$Directory)
    $marker = Get-PpbOwnershipMarkerPath $Directory
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $false }
    try {
        $data = [System.IO.File]::ReadAllText($marker) | ConvertFrom-Json
        return ($data.tool -eq 'PythonPortableBuilder')
    } catch { return $false }
}

function Read-PpbOwnershipMarker {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-PpbOwnershipMarker $Directory)) { return $null }
    return ConvertTo-PpbHashtable (Read-PpbJsonFile (Get-PpbOwnershipMarkerPath $Directory))
}

function Write-PpbOwnershipMarker {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$PackageName,
        [string[]]$Artifacts = @()
    )
    $existing = Read-PpbOwnershipMarker $Directory
    $all = New-Object System.Collections.Generic.List[string]
    if ($existing -and $existing['artifacts']) { foreach ($a in $existing['artifacts']) { if (-not $all.Contains($a)) { $all.Add($a) } } }
    foreach ($a in $Artifacts) { if ($a -and -not $all.Contains($a)) { $all.Add($a) } }
    $data = [ordered]@{
        tool        = 'PythonPortableBuilder'
        package     = $PackageName
        created     = if ($existing -and $existing['created']) { $existing['created'] } else { [DateTime]::UtcNow.ToString('o') }
        updated     = [DateTime]::UtcNow.ToString('o')
        artifacts   = $all.ToArray()
        note        = 'This directory is managed by PythonPortableBuilder. clean.ps1 and build.ps1 -Clean only delete directories that carry this marker.'
    }
    Write-PpbJsonFile -Path (Get-PpbOwnershipMarkerPath $Directory) -Data $data
}

#endregion

#region Process execution ------------------------------------------------------

<#
.SYNOPSIS
    Quotes one argument following the MSVCRT / CommandLineToArgvW rules.
#>
function ConvertTo-PpbCommandLineArgument {
    param([AllowEmptyString()][AllowNull()][string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') { $backslashes++; continue }
        if ($ch -eq '"') {
            [void]$sb.Append('\', $backslashes * 2 + 1)
            [void]$sb.Append('"')
        } else {
            if ($backslashes -gt 0) { [void]$sb.Append('\', $backslashes) }
            [void]$sb.Append($ch)
        }
        $backslashes = 0
    }
    if ($backslashes -gt 0) { [void]$sb.Append('\', $backslashes * 2) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Join-PpbCommandLine {
    param([string[]]$Arguments)
    if (-not $Arguments) { return '' }
    return (($Arguments | ForEach-Object { ConvertTo-PpbCommandLineArgument $_ }) -join ' ')
}

<#
.SYNOPSIS
    Patterns of environment variable names that may carry credentials. Used to
    scrub the environment of application probes and to keep values out of logs.
#>
function Get-PpbSensitiveEnvironmentPattern {
    return '(?i)(^AWS_|^AZURE_|^GOOGLE_|^GCP_|PASSWORD|PASSWD|PWD$|SECRET|TOKEN|CREDENTIAL|API_?KEY|PRIVATE_?KEY|^DATABASE_URL$|^DB_|^PG(HOST|USER|PASSWORD|DATABASE|PORT|PASSFILE|SERVICE|SERVICEFILE)$|^MYSQL_|^MSSQL|^SQLCMD|CONNECTION_?STRING|^ODBC)'
}

<#
.SYNOPSIS
    Runs an external process, streams its output to the log and returns the result.
.OUTPUTS
    PSCustomObject { ExitCode, StdOut, StdErr, TimedOut, DurationSeconds, CommandLine }
#>
function Invoke-PpbProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$RawArguments,
        [string]$WorkingDirectory,
        [hashtable]$Environment,
        [string[]]$RemoveEnvironment,
        [switch]$ScrubSensitiveEnvironment,
        [int]$TimeoutSeconds = 0,
        [switch]$Quiet,
        [string]$Description
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = if ($PSBoundParameters.ContainsKey('RawArguments')) { $RawArguments } else { Join-PpbCommandLine $ArgumentList }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.WorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { (Get-Location -PSProvider FileSystem).ProviderPath }

    if ($ScrubSensitiveEnvironment) {
        $pattern = Get-PpbSensitiveEnvironmentPattern
        $names = @($psi.EnvironmentVariables.Keys)
        foreach ($n in $names) { if ($n -match $pattern) { $psi.EnvironmentVariables.Remove($n) } }
    }
    if ($RemoveEnvironment) { foreach ($n in $RemoveEnvironment) { if ($psi.EnvironmentVariables.ContainsKey($n)) { $psi.EnvironmentVariables.Remove($n) } } }
    if ($Environment) {
        foreach ($k in $Environment.Keys) {
            if ($null -eq $Environment[$k]) {
                if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) }
            } else {
                $psi.EnvironmentVariables[$k] = [string]$Environment[$k]
            }
        }
    }

    $commandLine = "`"$FilePath`" $($psi.Arguments)"
    if ($Description) { Write-PpbLog $Description -Level Debug }
    Write-PpbLog "exec: $commandLine (cwd: $($psi.WorkingDirectory))" -Level Debug

    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        [void]$proc.Start()
    } catch {
        Stop-PpbWithError "Failed to start '$FilePath': $($_.Exception.Message)"
    }
    try { $proc.StandardInput.Close() } catch { }

    $outTask = $proc.StandardOutput.ReadLineAsync()
    $errTask = $proc.StandardError.ReadLineAsync()
    $outDone = $false; $errDone = $false; $timedOut = $false
    $level = if ($Quiet) { 'Debug' } else { 'Output' }
    while (-not ($outDone -and $errDone)) {
        $pending = @()
        if (-not $outDone) { $pending += $outTask }
        if (-not $errDone) { $pending += $errTask }
        [void][System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$pending, 250)
        if (-not $outDone -and $outTask.IsCompleted) {
            $line = $outTask.Result
            if ($null -eq $line) { $outDone = $true } else {
                [void]$stdout.AppendLine($line)
                Write-PpbLog $line -Level $level
                $outTask = $proc.StandardOutput.ReadLineAsync()
            }
        }
        if (-not $errDone -and $errTask.IsCompleted) {
            $line = $errTask.Result
            if ($null -eq $line) { $errDone = $true } else {
                [void]$stderr.AppendLine($line)
                Write-PpbLog $line -Level $level
                $errTask = $proc.StandardError.ReadLineAsync()
            }
        }
        if ($TimeoutSeconds -gt 0 -and $sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            $timedOut = $true
            Write-PpbLog "Process exceeded timeout of $TimeoutSeconds s; terminating: $FilePath" -Level Warn
            try { Stop-PpbProcessTree -ProcessId $proc.Id } catch { }
            break
        }
    }
    if (-not $timedOut) { $proc.WaitForExit() } else { [void]$proc.WaitForExit(5000) }
    $sw.Stop()
    $exit = if ($timedOut) { -1 } else { $proc.ExitCode }
    $proc.Dispose()
    return [pscustomobject]@{
        ExitCode        = $exit
        StdOut          = $stdout.ToString()
        StdErr          = $stderr.ToString()
        TimedOut        = $timedOut
        DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        CommandLine     = $commandLine
    }
}

function Stop-PpbProcessTree {
    param([int]$ProcessId)
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    foreach ($c in $children) { Stop-PpbProcessTree -ProcessId $c.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

#endregion

#region Misc helpers -----------------------------------------------------------

function Get-PpbFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

<#
.SYNOPSIS
    Converts a glob ("*.csv", "data/**/*.json", "secrets.*") into an anchored regex.
.DESCRIPTION
    Matching is done against relative paths using '/' separators. A pattern
    without '/' matches the file or directory *name* at any depth.
#>
function ConvertTo-PpbGlobRegex {
    param([Parameter(Mandatory)][string]$Pattern)
    $p = $Pattern.Replace('\', '/').Trim()
    if ($p.StartsWith('./')) { $p = $p.Substring(2) }
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $p.Length) {
        $c = $p[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $p.Length -and $p[$i + 1] -eq '*') {
                if ($i + 2 -lt $p.Length -and $p[$i + 2] -eq '/') { [void]$sb.Append('(?:.*/)?'); $i += 3; continue }
                [void]$sb.Append('.*'); $i += 2; continue
            }
            [void]$sb.Append('[^/]*')
        } elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
        } else {
            [void]$sb.Append([regex]::Escape([string]$c))
        }
        $i++
    }
    return '^' + $sb.ToString() + '$'
}

function Test-PpbGlobMatch {
    param([Parameter(Mandatory)][string]$RelativePath, [string[]]$Patterns)
    if (-not $Patterns) { return $false }
    $rel = $RelativePath.Replace('\', '/')
    $name = ($rel -split '/')[-1]
    foreach ($pat in $Patterns) {
        if (-not $pat) { continue }
        $regex = ConvertTo-PpbGlobRegex $pat
        $target = if ($pat.Replace('\', '/').Contains('/')) { $rel } else { $name }
        if ([regex]::IsMatch($target, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $true }
    }
    return $false
}

<#
.SYNOPSIS
    Safe property access for PSCustomObjects/hashtables under StrictMode.
#>
function Get-PpbValue {
    param([AllowNull()]$Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Get-PpbPowerShellExecutable {
    return (Get-Process -Id $PID).Path
}

<#
.SYNOPSIS
    Renders a template file: every {{KEY}} is replaced with Tokens[KEY].
    Unknown tokens are an error so that templates and code cannot drift apart.
#>
function Expand-PpbTemplate {
    param([Parameter(Mandatory)][string]$TemplatePath, [Parameter(Mandatory)][hashtable]$Tokens)
    $text = [System.IO.File]::ReadAllText($TemplatePath)
    $result = [regex]::Replace($text, '\{\{([A-Z_]+)\}\}', {
            param($m)
            $key = $m.Groups[1].Value
            if (-not $Tokens.ContainsKey($key)) { throw "Template '$TemplatePath' uses unknown token {{$key}}." }
            return [string]$Tokens[$key]
        })
    return $result
}

function Get-PpbTemplatePath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $p = Join-Path (Join-Path $script:ToolkitRoot 'templates') $RelativePath
    if (-not (Test-Path -LiteralPath $p)) { Stop-PpbWithError "Toolkit template missing: $p" }
    return $p
}

#endregion

Export-ModuleMember -Function *-Ppb*
