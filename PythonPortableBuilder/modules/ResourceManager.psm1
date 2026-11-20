#Requires -Version 5.1
<#
    ResourceManager.psm1 - selects and copies project files.

      * Applies default and user include/exclude patterns
      * Never copies VCS metadata, virtual environments, caches, build output
      * Excludes credential files and private keys by name
      * Scans configuration files for embedded secrets and BLOCKS the build until
        the user decides (exclude the file, or explicitly -Include it)
      * Copies files preserving relative paths; the source is never modified
#>

Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

$script:SecretRules = @(
    @{ Name = 'private key'; Regex = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----' },
    @{ Name = 'AWS access key id'; Regex = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' },
    @{ Name = 'AWS secret access key'; Regex = '(?i)aws_secret_access_key\s*["'']?\s*[:=]\s*["'']?[A-Za-z0-9/+=]{30,}' },
    @{ Name = 'connection string with password'; Regex = '(?i)\b(?:postgres(?:ql)?|mysql|mariadb|mssql|sqlserver|oracle|mongodb(?:\+srv)?|redis|amqp)(?:\+\w+)?://[^:/\s"'']+:[^@/\s"'']{3,}@' },
    @{ Name = 'password/secret value'; Regex = '(?im)^\s*["'']?(?:[\w.\-]*_)?(?:password|passwd|pwd|secret|secret_key|api_?key|access_?token|auth_?token|client_?secret|token)["'']?\s*[:=]\s*["'']?(?<value>[^"''\s,;#}{\]]{4,})' }
)

$script:PlaceholderRegex = '(?i)^(?:none|null|nil|true|false|changeme|change_me|change-me|placeholder|example|xxx+|\*+|todo|tbd|your[_-].*|<.*>|\$\{.*\}|\$\(.*\)|%\(.*\)s|%[A-Z_]+%|\{\{.*\}\}|env:.*|os\.environ.*|getenv.*|""|'''')$'

<#
.SYNOPSIS
    Scans a text file for embedded secrets. Returns a list of rule names that matched.
#>
function Find-PpbSecretsInFile {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxBytes = 1048576, [switch]$PrivateKeysOnly)
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -gt $MaxBytes -or $item.Length -eq 0) { return @() }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sample = [Math]::Min($bytes.Length, 8000)
    for ($i = 0; $i -lt $sample; $i++) { if ($bytes[$i] -eq 0) { return @() } }  # binary
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $hits = @()
    foreach ($rule in $script:SecretRules) {
        if ($PrivateKeysOnly -and $rule.Name -notin 'private key', 'AWS access key id', 'AWS secret access key') { continue }
        foreach ($m in [regex]::Matches($text, $rule.Regex)) {
            if ($m.Groups['value'].Success) {
                $v = $m.Groups['value'].Value.Trim()
                if ($v -match $script:PlaceholderRegex) { continue }
            }
            $hits += $rule.Name
            break
        }
    }
    return $hits
}

function Test-PpbExcludedDirectory {
    param([string]$Name, [string]$RelativePath, [System.Collections.IDictionary]$Config, [string[]]$Include, [string[]]$Exclude)
    if ($Exclude -and (Test-PpbGlobMatch -RelativePath $RelativePath -Patterns $Exclude)) { return 'excluded by -Exclude' }
    $default = ($Config['excludeDirectories'] | Where-Object { $_ -ieq $Name }) -or
        (Test-PpbGlobMatch -RelativePath $Name -Patterns @($Config['excludeDirectoryPatterns']))
    if ($default) {
        if ($Include -and (Test-PpbGlobMatch -RelativePath $RelativePath -Patterns $Include)) { return $null }
        return 'default exclusion'
    }
    return $null
}

<#
.SYNOPSIS
    Enumerates the project and classifies every file.
.OUTPUTS
    Hashtable: Included, Excluded, Sensitive, Blocked, Warnings (lists of PSCustomObject with RelativePath/FullPath/Reason)
#>
function Get-PpbProjectFileSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [string]$SingleFile,
        [string[]]$Include,
        [string[]]$Exclude,
        [string[]]$ProtectedPaths
    )
    $included = New-Object System.Collections.Generic.List[object]
    $excluded = New-Object System.Collections.Generic.List[object]
    $sensitive = New-Object System.Collections.Generic.List[object]
    $blocked = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $scanExt = @($Config['secretScanExtensions'])
    $maxBytes = [int]$Config['secretScanMaxBytes']

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    if ($SingleFile) {
        $files.Add((Get-Item -LiteralPath $SingleFile))
        if ($Include) {
            foreach ($f in Get-ChildItem -LiteralPath $ProjectRoot -File -Force) {
                if ($f.FullName -ne (Resolve-PpbPath $SingleFile) -and (Test-PpbGlobMatch -RelativePath $f.Name -Patterns $Include)) { $files.Add($f) }
            }
        }
    } else {
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($ProjectRoot)
        while ($stack.Count) {
            $dir = $stack.Pop()
            foreach ($entry in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $rel = (Get-PpbRelativePath -Path $entry.FullName -BasePath $ProjectRoot).Replace('\', '/')
                if ($entry.PSIsContainer) {
                    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        $warnings.Add("Skipped symbolic link/junction: $rel"); continue
                    }
                    $isProtected = $false
                    foreach ($p in $ProtectedPaths) { if ($p -and (Test-PpbPathInside -Child $p -Parent $entry.FullName)) { $isProtected = $true } }
                    if ($isProtected) { $excluded.Add([pscustomobject]@{ RelativePath = "$rel/"; FullPath = $entry.FullName; Reason = 'output/toolkit directory' }); continue }
                    $reason = Test-PpbExcludedDirectory -Name $entry.Name -RelativePath $rel -Config $Config -Include $Include -Exclude $Exclude
                    if ($reason) { $excluded.Add([pscustomobject]@{ RelativePath = "$rel/"; FullPath = $entry.FullName; Reason = $reason }); continue }
                    $stack.Push($entry.FullName)
                } else {
                    $files.Add($entry)
                }
            }
        }
    }

    foreach ($f in $files) {
        $rel = (Get-PpbRelativePath -Path $f.FullName -BasePath $ProjectRoot).Replace('\', '/')
        $obj = [pscustomobject]@{ RelativePath = $rel; FullPath = $f.FullName; Reason = ''; Size = $f.Length }
        $explicitInclude = $Include -and (Test-PpbGlobMatch -RelativePath $rel -Patterns $Include)
        if ($Exclude -and (Test-PpbGlobMatch -RelativePath $rel -Patterns $Exclude)) { $obj.Reason = 'excluded by -Exclude'; $excluded.Add($obj); continue }
        if ($SingleFile -and $f.FullName -eq (Resolve-PpbPath $SingleFile)) { $included.Add($obj); continue }
        if (-not $explicitInclude -and (Test-PpbGlobMatch -RelativePath $rel -Patterns @($Config['excludeFilePatterns']))) { $obj.Reason = 'default exclusion'; $excluded.Add($obj); continue }
        $isSensitiveName = (Test-PpbGlobMatch -RelativePath $rel -Patterns @($Config['sensitiveFilePatterns'])) -and
            -not (Test-PpbGlobMatch -RelativePath $rel -Patterns @($Config['sensitiveAllowPatterns']))
        if ($isSensitiveName -and -not $explicitInclude) { $obj.Reason = 'sensitive file name (credentials/keys)'; $sensitive.Add($obj); continue }
        $ext = [System.IO.Path]::GetExtension($f.Name).ToLowerInvariant()
        $nameIsEnv = $f.Name -like '.env*'
        if ($scanExt -contains $ext -or $nameIsEnv) {
            $hits = @(Find-PpbSecretsInFile -Path $f.FullName -MaxBytes $maxBytes)
            if ($hits.Count) {
                if ($explicitInclude) {
                    $warnings.Add("Included '$rel' although it appears to contain: $($hits -join ', ') (explicit -Include).")
                } else {
                    $obj.Reason = "possible secret: $($hits -join ', ')"
                    $blocked.Add($obj); continue
                }
            }
        } elseif ($ext -in '.py', '.pyw') {
            $hits = @(Find-PpbSecretsInFile -Path $f.FullName -MaxBytes $maxBytes -PrivateKeysOnly)
            if ($hits.Count) { $warnings.Add("Source file '$rel' appears to contain: $($hits -join ', '). Source code is never modified; remove secrets from code.") }
        }
        if ($isSensitiveName) { $warnings.Add("Included sensitive-looking file '$rel' (explicit -Include).") }
        $included.Add($obj)
    }
    return @{ Included = $included.ToArray(); Excluded = $excluded.ToArray(); Sensitive = $sensitive.ToArray(); Blocked = $blocked.ToArray(); Warnings = $warnings.ToArray() }
}

<#
.SYNOPSIS
    Stops the build when files that look like they contain secrets were found.
#>
function Assert-PpbNoBlockedFiles {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Selection)
    foreach ($w in $Selection.Warnings) { Write-PpbLog $w -Level Warn }
    foreach ($s in $Selection.Sensitive) { Write-PpbLog "Excluded sensitive file: $($s.RelativePath) ($($s.Reason))" -Level Warn }
    if ($Selection.Blocked.Count) {
        $list = ($Selection.Blocked | ForEach-Object { "$($_.RelativePath)  [$($_.Reason)]" }) -join "`n    "
        Stop-PpbWithError ("These files appear to contain credentials or private keys:`n    $list`n" +
            "  Decide explicitly: keep secrets out of the package (-Exclude '<pattern>') and provide them on the destination " +
            "(environment variables, external config), or include a file knowingly with -Include '<pattern>'.") 2
    }
}

<#
.SYNOPSIS
    Copies selected files into Destination, preserving relative paths.
#>
function Copy-PpbProjectFiles {
    param([Parameter(Mandatory)][object[]]$Files, [Parameter(Mandatory)][string]$Destination)
    New-PpbDirectory $Destination | Out-Null
    foreach ($f in $Files) {
        $target = Join-Path $Destination ($f.RelativePath.Replace('/', '\'))
        $dir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::Copy($f.FullPath, $target, $true)
        $attr = [System.IO.File]::GetAttributes($target)
        if ($attr -band [IO.FileAttributes]::ReadOnly) { [System.IO.File]::SetAttributes($target, $attr -band (-bnot [IO.FileAttributes]::ReadOnly)) }
    }
}

<#
.SYNOPSIS
    Returns relative paths of non-Python resource files from a selection.
#>
function Get-PpbResourceFiles {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files)
    return @($Files | Where-Object { $_.RelativePath -notmatch '\.(py|pyw)$' } | ForEach-Object { $_.RelativePath })
}

<#
.SYNOPSIS
    Parses "-DataFile 'source;destination'" values (PyInstaller convention).
#>
function ConvertFrom-PpbDataFileSpec {
    param([Parameter(Mandatory)][string]$Spec, [Parameter(Mandatory)][string]$ProjectRoot)
    $parts = $Spec -split ';', 2
    if ($parts.Count -ne 2 -or -not $parts[0] -or -not $parts[1]) { Stop-PpbWithError "Invalid data file specification '$Spec'. Use 'source;destination' (destination is relative to the application root)." 2 }
    $src = Resolve-PpbPath $parts[0] -BasePath $ProjectRoot
    if (-not (Test-Path -LiteralPath $src)) { Stop-PpbWithError "Data file source not found: $src" 2 }
    $dest = $parts[1].Replace('\', '/').Trim('/')
    if ($dest -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($dest)) { Stop-PpbWithError "Data file destination must be relative and inside the application: '$dest'" 2 }
    return [pscustomobject]@{ Source = $src; Destination = $(if ($dest) { $dest } else { '.' }) }
}

Export-ModuleMember -Function Find-PpbSecretsInFile, Get-PpbProjectFileSelection, Assert-PpbNoBlockedFiles, Copy-PpbProjectFiles, Get-PpbResourceFiles, ConvertFrom-PpbDataFileSpec
