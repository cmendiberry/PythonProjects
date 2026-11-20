#Requires -Version 5.1
<#
    PythonRuntimeManager.psm1 - Python interpreters and runtimes.

      * Discovers build-machine Python interpreters (py launcher, PATH, explicit path)
      * Resolves the target Python version from parameters / project metadata
      * Downloads the official CPython Windows embeddable ZIP from python.org,
        verifies checksum (python.org release API), archive integrity,
        Authenticode signature (Python Software Foundation) and version/architecture
      * Creates isolated build virtual environments
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

$script:InspectScript = Join-Path (Get-PpbToolkitRoot) 'python\ppb_inspect.py'
$script:ProbeCache = @{}

#region Version helpers ---------------------------------------------------------

function ConvertTo-PpbVersionParts {
    param([Parameter(Mandatory)][string]$Version)
    $parts = @()
    foreach ($p in ($Version.Trim() -split '\.')) {
        if ($p -match '^(\d+)') { $parts += [int]$Matches[1] } else { break }
    }
    return , $parts
}

function Compare-PpbVersion {
    param([string]$A, [string]$B)
    $pa = ConvertTo-PpbVersionParts $A; $pb = ConvertTo-PpbVersionParts $B
    $n = [math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

<#
.SYNOPSIS
    Evaluates a PEP 440 style specifier (">=3.9,<3.13", "~=3.10", "==3.11.*") for a version.
#>
function Test-PpbVersionSpecifier {
    param([Parameter(Mandatory)][string]$Version, [AllowEmptyString()][string]$Specifier)
    if (-not $Specifier -or -not $Specifier.Trim()) { return $true }
    foreach ($raw in ($Specifier -split ',')) {
        $clause = $raw.Trim()
        if (-not $clause) { continue }
        if ($clause -notmatch '^(~=|===|==|!=|<=|>=|<|>)\s*([0-9][0-9A-Za-z.*+!-]*)$') {
            if ($clause -match '^[0-9]') { $clause = "==$clause"; [void]($clause -match '^(==)\s*(.+)$') }
            else { Stop-PpbWithError "Unsupported Python version specifier clause '$clause' in '$Specifier'." 2 }
        }
        $op = $Matches[1]; $target = $Matches[2]
        if ($target.EndsWith('.*')) {
            $prefix = ConvertTo-PpbVersionParts ($target.Substring(0, $target.Length - 2))
            $vp = ConvertTo-PpbVersionParts $Version
            $match = $true
            for ($i = 0; $i -lt $prefix.Count; $i++) {
                $v = if ($i -lt $vp.Count) { $vp[$i] } else { 0 }
                if ($v -ne $prefix[$i]) { $match = $false; break }
            }
            if ($op -eq '==' -and -not $match) { return $false }
            if ($op -eq '!=' -and $match) { return $false }
            continue
        }
        $cmp = Compare-PpbVersion $Version $target
        switch ($op) {
            '>=' { if ($cmp -lt 0) { return $false } }
            '<=' { if ($cmp -gt 0) { return $false } }
            '>' { if ($cmp -le 0) { return $false } }
            '<' { if ($cmp -ge 0) { return $false } }
            '!=' { if ($cmp -eq 0) { return $false } }
            '===' { if ($Version -ne $target) { return $false } }
            '==' {
                # '==3.10' matches 3.10.x only when the specifier is shorter than the version? PEP 440: zero padding.
                if ($cmp -ne 0) { return $false }
            }
            '~=' {
                $tp = ConvertTo-PpbVersionParts $target
                if ($cmp -lt 0) { return $false }
                $prefix = $tp[0..([math]::Max(0, $tp.Count - 2))]
                $vp = ConvertTo-PpbVersionParts $Version
                for ($i = 0; $i -lt $prefix.Count; $i++) {
                    $v = if ($i -lt $vp.Count) { $vp[$i] } else { 0 }
                    if ($v -ne $prefix[$i]) { return $false }
                }
            }
        }
    }
    return $true
}

function Get-PpbMajorMinor {
    param([Parameter(Mandatory)][string]$Version)
    $p = ConvertTo-PpbVersionParts $Version
    if ($p.Count -lt 2) { Stop-PpbWithError "Invalid Python version '$Version' (expected X.Y or X.Y.Z)." 2 }
    return "$($p[0]).$($p[1])"
}

#endregion

#region Host interpreters -------------------------------------------------------

<#
.SYNOPSIS
    Probes one interpreter. Returns $null when it cannot be executed.
#>
function Get-PpbPythonInfo {
    param([Parameter(Mandatory)][string]$PythonExe, [switch]$Isolated)
    $key = $PythonExe.ToLowerInvariant()
    if ($script:ProbeCache.ContainsKey($key)) { return $script:ProbeCache[$key] }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ppb-probe-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    try {
        $pyArgs = @()
        if ($Isolated) { $pyArgs += '-I' }
        $pyArgs += @('-B', $script:InspectScript, '--output', $tmp, 'probe')
        $r = Invoke-PpbProcess -FilePath $PythonExe -ArgumentList $pyArgs -Quiet -TimeoutSeconds 60
        if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { return $null }
        $info = Read-PpbJsonFile $tmp
        $script:ProbeCache[$key] = $info
        return $info
    } catch {
        return $null
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

<#
.SYNOPSIS
    Lists CPython interpreters available on the build machine.
#>
function Find-PpbHostPythons {
    param([string[]]$ExtraPaths)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($p in $ExtraPaths) { if ($p) { $paths.Add($p) } }
    $py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($py) {
        try {
            $r = Invoke-PpbProcess -FilePath $py.Source -ArgumentList @('-0p') -Quiet -TimeoutSeconds 30
            foreach ($line in ($r.StdOut + "`n" + $r.StdErr) -split "`r?`n") {
                if ($line -match '^\s*-\S+\s+(?:\*\s+)?(.+?\.exe)\s*$') { $paths.Add($Matches[1].Trim()) }
            }
        } catch { Write-PpbLog "py launcher query failed: $($_.Exception.Message)" -Level Debug }
    }
    foreach ($name in 'python.exe', 'python3.exe') {
        foreach ($c in @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue)) { $paths.Add($c.Source) }
    }
    $seen = @{}
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $info = Get-PpbPythonInfo -PythonExe $p -Isolated
        if (-not $info -or $info.implementation -ne 'cpython') { continue }
        $exe = [string]$info.executable
        $k = $exe.ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $info | Add-Member -NotePropertyName 'invokedAs' -NotePropertyValue $p -Force
        $result.Add($info)
    }
    return $result.ToArray()
}

function Format-PpbHostList {
    param($Hosts)
    if (-not $Hosts -or @($Hosts).Count -eq 0) { return '(no Python interpreters found)' }
    return ((@($Hosts) | ForEach-Object { "Python $($_.version) [$($_.architecture)] $($_.executable)" }) -join "`n  ")
}

<#
.SYNOPSIS
    Determines the target Python version/architecture and the build interpreter.
.OUTPUTS
    Hashtable: Version (X.Y.Z or $null), MajorMinor, Architecture, BuildPython (probe info),
    CrossInstall (bool), Reason
#>
function Resolve-PpbPythonTarget {
    [CmdletBinding()]
    param(
        [string]$RequestedVersion,
        [string]$Specifier,
        [string]$SpecifierSource,
        [Parameter(Mandatory)][ValidateSet('embedded', 'executable')][string]$Type,
        [Parameter(Mandatory)][string]$Architecture,
        [string]$BuildPython
    )
    if ($BuildPython) {
        $info = Get-PpbPythonInfo -PythonExe (Resolve-PpbPath $BuildPython) -Isolated
        if (-not $info) { Stop-PpbWithError "The build Python '$BuildPython' could not be executed." 2 }
        $info | Add-Member -NotePropertyName 'invokedAs' -NotePropertyValue (Resolve-PpbPath $BuildPython) -Force
        $hosts = @($info)
    } else {
        $hosts = @(Find-PpbHostPythons)
    }
    Write-PpbLog ("Build-machine interpreters:`n  " + (Format-PpbHostList $hosts)) -Level Debug
    $archHosts = @($hosts | Where-Object { $_.architecture -eq $Architecture })
    $reason = ''

    $requested = $RequestedVersion
    if ($requested -and $requested -notmatch '^\d+\.\d+(\.\d+)?$') {
        Stop-PpbWithError "Invalid -PythonVersion '$requested'. Use X.Y or X.Y.Z (for example 3.11 or 3.11.9)." 2
    }
    $matching = @()
    if ($requested) {
        $mm = Get-PpbMajorMinor $requested
        $matching = @($archHosts | Where-Object { $_.majorMinor -eq $mm } | Sort-Object { [version]$_.version } -Descending)
        $exact = @($matching | Where-Object { $_.version -eq $requested })
        if ($exact.Count) { $matching = @($exact + @($matching | Where-Object { $_.version -ne $requested })) }
        $reason = "requested $requested"
    } elseif ($Specifier) {
        $matching = @($archHosts | Where-Object { Test-PpbVersionSpecifier -Version $_.version -Specifier $Specifier } |
                Sort-Object { [version]$_.version } -Descending)
        $reason = "highest installed interpreter satisfying '$Specifier' ($SpecifierSource)"
        if (-not $matching.Count) {
            Stop-PpbWithError ("No $Architecture build interpreter satisfies the project's Python requirement '$Specifier' ($SpecifierSource). " +
                "Install a matching Python or pass -PythonVersion explicitly.`n  Available:`n  " + (Format-PpbHostList $hosts)) 2
        }
    } else {
        $onPath = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $preferred = $null
        if ($onPath) { $preferred = @($archHosts | Where-Object { $_.invokedAs -eq $onPath.Source }) | Select-Object -First 1 }
        if ($preferred) { $matching = @($preferred); $reason = 'default python.exe on PATH' }
        else { $matching = @($archHosts | Sort-Object { [version]$_.version } -Descending); $reason = 'highest installed interpreter' }
    }

    $build = $null
    if ($matching.Count) { $build = $matching[0] }
    $target = @{ Architecture = $Architecture; CrossInstall = $false; BuildPython = $build; Reason = $reason; Version = $null; MajorMinor = $null }

    if ($Type -eq 'executable') {
        if (-not $build) {
            Stop-PpbWithError ("PyInstaller bundles the build interpreter, so a $Architecture Python " +
                $(if ($requested) { $requested } else { '' }) + " must be installed on the build machine.`n  Available:`n  " + (Format-PpbHostList $hosts)) 2
        }
        if ($requested -and ($requested -split '\.').Count -eq 3 -and $build.version -ne $requested) {
            Write-PpbLog "Requested Python $requested but the build interpreter is $($build.version); the executable will contain $($build.version)." -Level Warn
        }
        $target.Version = [string]$build.version
        $target.MajorMinor = [string]$build.majorMinor
        return $target
    }

    # embedded
    if ($requested -and ($requested -split '\.').Count -eq 3) {
        $target.Version = $requested
    } elseif ($build) {
        $target.Version = [string]$build.version
    }
    $target.MajorMinor = if ($target.Version) { Get-PpbMajorMinor $target.Version } elseif ($requested) { Get-PpbMajorMinor $requested } else { $null }
    if (-not $target.MajorMinor) {
        Stop-PpbWithError ("No $Architecture Python interpreter found on the build machine and no -PythonVersion was given.`n  Available:`n  " + (Format-PpbHostList $hosts)) 2
    }
    if (-not $build) {
        # Cross-installation: use any interpreter's pip with --platform/--python-version (binary wheels only).
        $any = @($hosts | Where-Object { [version]$_.version -ge [version]'3.8' } | Sort-Object { [version]$_.version } -Descending)
        if (-not $any.Count) { Stop-PpbWithError "No usable Python (3.8+) found on the build machine to run pip." 2 }
        $target.BuildPython = $any[0]
        $target.CrossInstall = $true
        Write-PpbLog ("No $Architecture Python $($target.MajorMinor) is installed on the build machine. Dependencies will be " +
            "cross-installed with pip --python-version/--platform (binary wheels only) using Python $($any[0].version).") -Level Warn
    }
    return $target
}

#endregion

#region Embeddable runtime ------------------------------------------------------

function Initialize-PpbWebClient {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Invoke-PpbWebJson {
    param([Parameter(Mandatory)][string]$Uri, [int]$TimeoutSeconds = 60)
    Initialize-PpbWebClient
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try {
        $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSeconds -Headers @{ 'Accept' = 'application/json' }
        $content = $resp.Content
        if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
        return ($content | ConvertFrom-Json)
    } finally { $ProgressPreference = $old }
}

function Get-PpbEmbedFileName {
    param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$Architecture)
    return "python-$Version-embed-$Architecture.zip"
}

function Assert-PpbOfficialUrl {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $base = $Config['pythonDownload']['baseUrl']
    $u = [Uri]$Url
    if ($u.Scheme -ne 'https' -or $u.Host -ne 'www.python.org' -or -not $Url.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-PpbWithError "Refusing to download Python from a non-official location: $Url (only $base is allowed)."
    }
}

<#
.SYNOPSIS
    Looks up the official file metadata (URL, checksums, size) of an embeddable ZIP
    through the python.org release API. Returns $null when the release has no such file.
#>
function Get-PpbEmbeddedRuntimeInfo {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config
    )
    $api = $Config['pythonDownload']['apiUrl']
    $fileName = Get-PpbEmbedFileName $Version $Architecture
    $releases = @(Invoke-PpbWebJson -Uri ("{0}release/?name={1}" -f $api, [Uri]::EscapeDataString("Python $Version")))
    if (-not $releases.Count) { return $null }
    if ($releases[0].resource_uri -notmatch '/release/(\d+)/?$') { return $null }
    $files = @(Invoke-PpbWebJson -Uri ("{0}release_file/?release={1}" -f $api, $Matches[1]))
    foreach ($f in $files) {
        if ($f.url -and $f.url.EndsWith('/' + $fileName)) {
            return [pscustomobject]@{
                Url    = [string]$f.url
                Md5    = [string]$f.md5_sum
                Sha256 = [string](Get-PpbValue $f 'sha256_sum' '')
                Size   = [long](Get-PpbValue $f 'filesize' 0)
                Source = 'python.org release API'
            }
        }
    }
    return $null
}

<#
.SYNOPSIS
    Finds the newest X.Y.Z release that publishes an embeddable ZIP for the architecture.
    Security-only releases do not ship Windows binaries, so this walks back as needed.
#>
function Find-PpbLatestEmbeddableVersion {
    param(
        [Parameter(Mandatory)][string]$MajorMinor,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config
    )
    $api = $Config['pythonDownload']['apiUrl']
    $all = @(Invoke-PpbWebJson -Uri ("{0}release/?is_published=true&pre_release=false" -f $api) -TimeoutSeconds 120)
    $versions = @($all | ForEach-Object { if ($_.name -match "^Python ($([regex]::Escape($MajorMinor))\.\d+)$") { $Matches[1] } } |
            Sort-Object { [version]$_ } -Descending)
    $max = [int]$Config['pythonDownload']['maxPatchProbe']
    foreach ($v in ($versions | Select-Object -First $max)) {
        $info = Get-PpbEmbeddedRuntimeInfo -Version $v -Architecture $Architecture -Config $Config
        if ($info) { return $v }
        Write-PpbLog "Python $v has no embeddable package for $Architecture (security-only release?)" -Level Debug
    }
    return $null
}

<#
.SYNOPSIS
    Returns a verified embeddable ZIP from the cache, downloading it when needed.
.OUTPUTS
    PSCustomObject: ZipPath, Version, Architecture, Url, Sha256, ChecksumVerified, ChecksumAlgorithm, Source
#>
function Get-PpbEmbeddedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][string]$CacheDirectory,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [string]$LocalZip
    )
    $fileName = Get-PpbEmbedFileName $Version $Architecture
    $runtimeCache = New-PpbDirectory (Join-Path $CacheDirectory 'runtimes')
    $cached = Join-Path $runtimeCache $fileName
    $metaPath = "$cached.ppb.json"

    $official = $null
    try { $official = Get-PpbEmbeddedRuntimeInfo -Version $Version -Architecture $Architecture -Config $Config }
    catch { Write-PpbLog "python.org release API not reachable: $($_.Exception.Message)" -Level Warn }

    if ($LocalZip) {
        $LocalZip = Resolve-PpbPath $LocalZip
        if (-not (Test-Path -LiteralPath $LocalZip -PathType Leaf)) { Stop-PpbWithError "Runtime ZIP not found: $LocalZip" 2 }
        if ((Split-Path -Leaf $LocalZip) -ne $fileName) { Stop-PpbWithError "Runtime ZIP must be the official file '$fileName' (got '$(Split-Path -Leaf $LocalZip)')." 2 }
        $verification = Test-PpbRuntimeChecksum -Path $LocalZip -Official $official
        return [pscustomobject]@{ ZipPath = $LocalZip; Version = $Version; Architecture = $Architecture
            Url = if ($official) { $official.Url } else { "$($Config['pythonDownload']['baseUrl'])$Version/$fileName" }
            Sha256 = $verification.Sha256; ChecksumVerified = $verification.Verified; ChecksumAlgorithm = $verification.Algorithm
            Source = 'local file (-RuntimeZip)' }
    }

    if ((Test-Path -LiteralPath $cached) -and (Test-Path -LiteralPath $metaPath)) {
        $meta = Read-PpbJsonFile $metaPath
        $sha = Get-PpbFileSha256 $cached
        if ($sha -eq $meta.sha256) {
            if ($official) { $verification = Test-PpbRuntimeChecksum -Path $cached -Official $official }
            Write-PpbLog "Using cached runtime $fileName (sha256 $sha)" -Level Info
            return [pscustomobject]@{ ZipPath = $cached; Version = $Version; Architecture = $Architecture; Url = $meta.url
                Sha256 = $sha; ChecksumVerified = [bool]$meta.checksumVerified; ChecksumAlgorithm = $meta.checksumAlgorithm; Source = 'cache' }
        }
        Write-PpbLog "Cached runtime $fileName failed its integrity check; downloading again." -Level Warn
    }

    $url = if ($official) { $official.Url } else { "$($Config['pythonDownload']['baseUrl'])$Version/$fileName" }
    Assert-PpbOfficialUrl -Url $url -Config $Config
    $partial = "$cached.partial"
    Write-PpbLog "Downloading $url" -Level Info
    Initialize-PpbWebClient
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $partial -UseBasicParsing -TimeoutSec ([int]$Config['pythonDownload']['timeoutSeconds'])
    } catch {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status -eq 404) { Stop-PpbWithError "Python $Version has no official embeddable package for $Architecture ($url returned 404)." 2 }
        Stop-PpbWithError "Download of $url failed: $($_.Exception.Message)"
    } finally { $ProgressPreference = $old }

    $verification = Test-PpbRuntimeChecksum -Path $partial -Official $official
    Test-PpbZipIntegrity -Path $partial
    Move-Item -LiteralPath $partial -Destination $cached -Force
    Write-PpbJsonFile -Path $metaPath -Data ([ordered]@{
            url = $url; sha256 = $verification.Sha256; checksumVerified = $verification.Verified
            checksumAlgorithm = $verification.Algorithm; downloadedUtc = [DateTime]::UtcNow.ToString('o')
        })
    return [pscustomobject]@{ ZipPath = $cached; Version = $Version; Architecture = $Architecture; Url = $url
        Sha256 = $verification.Sha256; ChecksumVerified = $verification.Verified; ChecksumAlgorithm = $verification.Algorithm; Source = 'download' }
}

function Test-PpbRuntimeChecksum {
    param([Parameter(Mandatory)][string]$Path, $Official)
    $sha = Get-PpbFileSha256 $Path
    if (-not $Official) {
        Write-PpbLog "Official checksum unavailable (offline?). Integrity will rely on the Authenticode signature of python.exe." -Level Warn
        return @{ Sha256 = $sha; Verified = $false; Algorithm = $null }
    }
    if ($Official.Size -gt 0 -and (Get-Item -LiteralPath $Path).Length -ne $Official.Size) {
        Stop-PpbWithError "Runtime archive size mismatch for $Path (expected $($Official.Size) bytes)."
    }
    if ($Official.Sha256) {
        if ($sha -ne $Official.Sha256.ToLowerInvariant()) { Stop-PpbWithError "SHA-256 mismatch for $Path. Expected $($Official.Sha256), got $sha." }
        Write-PpbLog "SHA-256 verified against python.org: $sha" -Level Success
        return @{ Sha256 = $sha; Verified = $true; Algorithm = 'sha256' }
    }
    if ($Official.Md5) {
        $md5 = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant()
        if ($md5 -ne $Official.Md5.ToLowerInvariant()) { Stop-PpbWithError "MD5 mismatch for $Path. Expected $($Official.Md5), got $md5." }
        Write-PpbLog "MD5 verified against python.org release metadata (sha256 $sha)" -Level Success
        return @{ Sha256 = $sha; Verified = $true; Algorithm = 'md5' }
    }
    return @{ Sha256 = $sha; Verified = $false; Algorithm = $null }
}

function Test-PpbZipIntegrity {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] 65536
            foreach ($e in $zip.Entries) {
                $s = $e.Open()
                try { while ($s.Read($buffer, 0, $buffer.Length) -gt 0) { } } finally { $s.Dispose() }
            }
        } finally { $zip.Dispose() }
    } catch {
        Stop-PpbWithError "Archive '$Path' is corrupt: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Extracts the embeddable runtime and verifies signature, version and architecture.
.OUTPUTS
    Hashtable with PthFile, Probe (interpreter info), Signature
#>
function Install-PpbEmbeddedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Runtime,
        [Parameter(Mandatory)][string]$Destination
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-PpbDirectory $Destination | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Runtime.ZipPath, $Destination)

    $pythonExe = Join-Path $Destination 'python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) { Stop-PpbWithError "python.exe missing from the embeddable runtime." }
    $mm = (Get-PpbMajorMinor $Runtime.Version).Replace('.', '')
    $pth = Join-Path $Destination "python$mm._pth"
    if (-not (Test-Path -LiteralPath $pth)) {
        $found = @(Get-ChildItem -LiteralPath $Destination -Filter 'python*._pth')
        Stop-PpbWithError "Expected version-specific path file python$mm._pth not found (found: $(($found | ForEach-Object Name) -join ', '))."
    }

    $signature = @{}
    foreach ($f in @('python.exe', "python$mm.dll")) {
        $sig = Get-AuthenticodeSignature -LiteralPath (Join-Path $Destination $f)
        $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '' }
        if ($sig.Status -ne 'Valid' -or $subject -notmatch 'Python Software Foundation') {
            Stop-PpbWithError "Authenticode verification failed for $f (status: $($sig.Status), signer: '$subject'). The runtime is not an authentic python.org build."
        }
        $signature[$f] = @{ status = [string]$sig.Status; signer = $subject }
    }
    Write-PpbLog "Authenticode signature verified (Python Software Foundation)" -Level Success

    $probe = Get-PpbPythonInfo -PythonExe $pythonExe
    if (-not $probe) { Stop-PpbWithError "The embedded python.exe could not be started on the build machine." }
    if ($probe.version -ne $Runtime.Version) { Stop-PpbWithError "Embedded runtime reports version $($probe.version), expected $($Runtime.Version)." }
    if ($probe.architecture -ne $Runtime.Architecture) { Stop-PpbWithError "Embedded runtime architecture $($probe.architecture) does not match $($Runtime.Architecture)." }
    Write-PpbLog "Embedded runtime Python $($probe.version) [$($probe.architecture)] starts correctly" -Level Success
    return @{ PthFile = $pth; Probe = $probe; Signature = $signature }
}

<#
.SYNOPSIS
    Rewrites pythonXY._pth: keeps the original entries, adds relative paths.
    'import site' stays disabled unless it was enabled in the original file.
#>
function Set-PpbEmbeddedPathFile {
    param([Parameter(Mandatory)][string]$PthFile, [Parameter(Mandatory)][string[]]$RelativePaths)
    $original = [System.IO.File]::ReadAllLines($PthFile)
    $out = New-Object System.Collections.Generic.List[string]
    $inserted = $false
    foreach ($line in $original) {
        $t = $line.Trim()
        if (-not $inserted -and ($t -eq '' -or $t.StartsWith('#') -or $t -match '^import\s')) {
            $out.Add('# Added by PythonPortableBuilder (paths are relative to this file):')
            foreach ($p in $RelativePaths) { if ($out -notcontains $p) { $out.Add($p) } }
            $inserted = $true
        }
        if ($RelativePaths -contains $t) { continue }
        $out.Add($line)
    }
    if (-not $inserted) { foreach ($p in $RelativePaths) { $out.Add($p) } }
    Write-PpbTextFile -Path $PthFile -Content (($out -join "`r`n") + "`r`n")
}

#endregion

#region Build environments ------------------------------------------------------

function Get-PpbIsolatedPipEnvironment {
    return @{
        PIP_DISABLE_PIP_VERSION_CHECK = '1'; PIP_NO_INPUT = '1'; PYTHONNOUSERSITE = '1'; PYTHONUTF8 = '1'
        PYTHONIOENCODING = 'utf-8'; PIP_REQUIRE_VIRTUALENV = $null; PIP_TARGET = $null; PIP_PREFIX = $null
        PIP_USER = $null; PYTHONPATH = $null; PYTHONHOME = $null; PYTHONSTARTUP = $null; VIRTUAL_ENV = $null
    }
}

<#
.SYNOPSIS
    Creates (or reuses, when its stamp matches) an isolated virtual environment.
.OUTPUTS
    Path of the venv python.exe
#>
function New-PpbBuildEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePython,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Stamp,
        [switch]$UpgradePip,
        [switch]$Force
    )
    $stampPath = Join-Path $Path '.ppb-env.json'
    $venvPython = Join-Path $Path 'Scripts\python.exe'
    $stampJson = ConvertTo-Json -InputObject $Stamp -Depth 8 -Compress
    if (-not $Force -and (Test-Path -LiteralPath $venvPython) -and (Test-Path -LiteralPath $stampPath)) {
        $existing = [System.IO.File]::ReadAllText($stampPath).Trim()
        if ($existing -eq $stampJson -and (Get-PpbPythonInfo -PythonExe $venvPython)) {
            Write-PpbLog "Reusing build environment $Path" -Level Info
            return $venvPython
        }
        Write-PpbLog "Build environment is stale; recreating it." -Level Info
    }
    if (Test-Path -LiteralPath $Path) { Remove-PpbItem -Path $Path -OwnerRoot $OwnerRoot }
    Write-PpbLog "Creating isolated build environment: $Path" -Level Info
    $r = Invoke-PpbProcess -FilePath $BasePython -ArgumentList @('-I', '-m', 'venv', $Path) -Environment (Get-PpbIsolatedPipEnvironment) -TimeoutSeconds 600
    if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $venvPython)) {
        Stop-PpbWithError "Could not create a virtual environment with '$BasePython' (exit $($r.ExitCode)). $($r.StdErr)"
    }
    if ($UpgradePip) {
        $r = Invoke-PpbProcess -FilePath $venvPython -ArgumentList @('-m', 'pip', 'install', '--upgrade', 'pip') -Environment (Get-PpbIsolatedPipEnvironment) -TimeoutSeconds 900
        if ($r.ExitCode -ne 0) { Write-PpbLog "pip upgrade failed (continuing with bundled pip): $($r.StdErr.Trim())" -Level Warn }
    }
    Write-PpbTextFile -Path $stampPath -Content $stampJson
    return $venvPython
}

#endregion

Export-ModuleMember -Function Compare-PpbVersion, Test-PpbVersionSpecifier, Get-PpbMajorMinor, Get-PpbPythonInfo, Find-PpbHostPythons,
    Format-PpbHostList, Resolve-PpbPythonTarget, Get-PpbEmbeddedRuntimeInfo, Find-PpbLatestEmbeddableVersion, Get-PpbEmbeddedRuntime,
    Test-PpbZipIntegrity, Install-PpbEmbeddedRuntime, Set-PpbEmbeddedPathFile, Get-PpbIsolatedPipEnvironment, New-PpbBuildEnvironment,
    Get-PpbEmbedFileName
