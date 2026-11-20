#Requires -Version 5.1
# Unit tests for the PowerShell modules (Pester 5). No network access, no builds.

BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($m in 'Common', 'PythonRuntimeManager', 'DependencyManager', 'ResourceManager', 'ExecutableBuilder', 'ArchiveManager', 'PackageValidator') {
        Import-Module (Join-Path $script:Root "modules\$m.psm1") -Force -DisableNameChecking
    }
    Initialize-PpbLog
    $script:Config = Get-PpbConfig
    function New-TestDir {
        $d = New-PpbTempDirectory -Prefix 'ppb-ut'
        return $d
    }
}

Describe 'Command-line quoting' {
    It 'quotes <In> as <Out>' -TestCases @(
        @{ In = 'simple'; Out = 'simple' }
        @{ In = 'with space'; Out = '"with space"' }
        @{ In = ''; Out = '""' }
        @{ In = 'say "hi"'; Out = '"say \"hi\""' }
        @{ In = 'C:\dir with space\'; Out = '"C:\dir with space\\"' }
    ) {
        ConvertTo-PpbCommandLineArgument $In | Should -Be $Out
    }
    It 'round-trips arguments through a real process' {
        $args = @('a b', 'quote"inside', 'trailing\', 'x')
        $r = Invoke-PpbProcess -FilePath (Get-Command python.exe).Source -ArgumentList (@('-c', 'import sys,json; print(json.dumps(sys.argv[1:]))') + $args) -Quiet
        ($r.StdOut | ConvertFrom-Json) | Should -Be $args
    }
    It 'returns the exit code and honours timeouts' {
        $py = (Get-Command python.exe).Source
        (Invoke-PpbProcess -FilePath $py -ArgumentList @('-c', 'raise SystemExit(7)') -Quiet).ExitCode | Should -Be 7
        $r = Invoke-PpbProcess -FilePath $py -ArgumentList @('-c', 'import time; time.sleep(30)') -Quiet -TimeoutSeconds 2
        $r.TimedOut | Should -BeTrue
    }
    It 'scrubs credential-like environment variables' {
        $env:PPB_TEST_DB_PASSWORD = 'secret-value'
        try {
            $r = Invoke-PpbProcess -FilePath (Get-Command python.exe).Source -ArgumentList @('-c', 'import os; print(os.environ.get("PPB_TEST_DB_PASSWORD", "absent"))') -Quiet -ScrubSensitiveEnvironment
            $r.StdOut.Trim() | Should -Be 'absent'
        } finally { Remove-Item Env:PPB_TEST_DB_PASSWORD }
    }
}

Describe 'Glob matching' {
    It '<Path> matches <Pattern> = <Expected>' -TestCases @(
        @{ Path = 'a/b/secrets.json'; Pattern = 'secrets.*'; Expected = $true }
        @{ Path = 'data/x.csv'; Pattern = 'data/*.csv'; Expected = $true }
        @{ Path = 'data/sub/x.csv'; Pattern = 'data/*.csv'; Expected = $false }
        @{ Path = 'data/sub/x.csv'; Pattern = 'data/**/*.csv'; Expected = $true }
        @{ Path = 'x.csv'; Pattern = '**/*.csv'; Expected = $true }
        @{ Path = '.env.example'; Pattern = '.env.*'; Expected = $true }
        @{ Path = 'notes/a.txt'; Pattern = 'notes/*'; Expected = $true }
    ) {
        Test-PpbGlobMatch -RelativePath $Path -Patterns @($Pattern) | Should -Be $Expected
    }
}

Describe 'Path helpers and deletion guards' {
    It 'detects containment case-insensitively and without prefix confusion' {
        Test-PpbPathInside 'C:\Out\Pkg\x' 'c:\out' | Should -BeTrue
        Test-PpbPathInside 'C:\Output2' 'C:\Out' | Should -BeFalse
    }
    It 'refuses to delete a drive root' {
        { Assert-PpbSafeToRemove -Path 'C:\' -OwnerRoot 'C:\' } | Should -Throw '*drive root*'
    }
    It 'refuses to delete the toolkit repository or a path containing it' {
        { Assert-PpbSafeToRemove -Path $script:Root -OwnerRoot (Split-Path -Parent $script:Root) } | Should -Throw '*protected*'
    }
    It 'refuses to delete inside a directory without an ownership marker' {
        $d = New-TestDir
        try {
            New-Item -ItemType Directory -Path (Join-Path $d 'pkg\.build') -Force | Out-Null
            { Remove-PpbItem -Path (Join-Path $d 'pkg\.build') -OwnerRoot (Join-Path $d 'pkg') } | Should -Throw '*not marked*'
            Test-Path (Join-Path $d 'pkg\.build') | Should -BeTrue
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
    It 'refuses to delete outside the owned directory' {
        $d = New-TestDir
        try {
            $pkg = New-PpbDirectory (Join-Path $d 'pkg')
            Write-PpbOwnershipMarker -Directory $pkg -PackageName 'pkg'
            $other = New-PpbDirectory (Join-Path $d 'other')
            { Remove-PpbItem -Path $other -OwnerRoot $pkg } | Should -Throw '*outside*'
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
    It 'refuses to delete a protected path passed by the caller (e.g. the source project)' {
        $d = New-TestDir
        try {
            $pkg = New-PpbDirectory (Join-Path $d 'pkg'); Write-PpbOwnershipMarker -Directory $pkg -PackageName 'pkg'
            $src = New-PpbDirectory (Join-Path $pkg 'work\src')
            { Remove-PpbItem -Path (Join-Path $pkg 'work') -OwnerRoot $pkg -ProtectedPaths @($src) } | Should -Throw '*protected*'
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
    It 'deletes inside a marked directory' {
        $d = New-TestDir
        try {
            $pkg = New-PpbDirectory (Join-Path $d 'pkg'); Write-PpbOwnershipMarker -Directory $pkg -PackageName 'pkg'
            $w = New-PpbDirectory (Join-Path $pkg '.build\deep')
            Set-Content -LiteralPath (Join-Path $w 'f.txt') -Value 'x'
            Remove-PpbItem -Path (Join-Path $pkg '.build') -OwnerRoot $pkg
            Test-Path (Join-Path $pkg '.build') | Should -BeFalse
            Test-Path (Join-Path $pkg '.ppb-owned.json') | Should -BeTrue
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
}

Describe 'Secret redaction' {
    It 'removes URL credentials' {
        Protect-PpbText 'pip --index-url https://user:p4ss@example.invalid/simple' | Should -Be 'pip --index-url https://***@example.invalid/simple'
    }
}

Describe 'Python version specifiers' {
    It '<Version> satisfies "<Spec>" = <Expected>' -TestCases @(
        @{ Version = '3.10.4'; Spec = '>=3.8'; Expected = $true }
        @{ Version = '3.10.4'; Spec = '>=3.8,<3.10'; Expected = $false }
        @{ Version = '3.11.2'; Spec = '~=3.10'; Expected = $true }
        @{ Version = '4.0.0'; Spec = '~=3.10'; Expected = $false }
        @{ Version = '3.10.9'; Spec = '~=3.10.2'; Expected = $true }
        @{ Version = '3.11.0'; Spec = '~=3.10.2'; Expected = $false }
        @{ Version = '3.12.1'; Spec = '==3.12.*'; Expected = $true }
        @{ Version = '3.13.0'; Spec = '==3.12.*'; Expected = $false }
        @{ Version = '3.9.1'; Spec = '!=3.9.1'; Expected = $false }
        @{ Version = '3.9.1'; Spec = ''; Expected = $true }
    ) {
        Test-PpbVersionSpecifier -Version $Version -Specifier $Spec | Should -Be $Expected
    }
    It 'compares versions numerically' {
        Compare-PpbVersion '3.10.0' '3.9.13' | Should -Be 1
        Compare-PpbVersion '3.10' '3.10.0' | Should -Be 0
    }
}

Describe 'Embedded path file' {
    It 'keeps the original entries and adds relative paths before the comments' {
        $d = New-TestDir
        try {
            $pth = Join-Path $d 'python310._pth'
            Set-Content -LiteralPath $pth -Value @('python310.zip', '.', '', '# Uncomment to run site.main() automatically', '#import site')
            Set-PpbEmbeddedPathFile -PthFile $pth -RelativePaths @('..\app', '..\packages')
            $lines = @(Get-Content -LiteralPath $pth)
            $lines[0] | Should -Be 'python310.zip'
            $lines[1] | Should -Be '.'
            $lines | Should -Contain '..\app'
            $lines | Should -Contain '..\packages'
            $lines | Should -Contain '#import site'
            $lines | Should -Not -Contain 'import site'
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
}

Describe 'Requirements selection' {
    It 'prefers explicit files and filters self-installs' {
        Test-PpbSelfInstallLine '-e .' | Should -BeTrue
        Test-PpbSelfInstallLine '.' | Should -BeTrue
        Test-PpbSelfInstallLine 'requests==2.0' | Should -BeFalse
    }
    It 'fails when imports exist but no dependencies are declared' {
        $report = [pscustomobject]@{ dependencySources = @(); imports = [pscustomobject]@{ thirdParty = @([pscustomobject]@{ name = 'yaml'; optional = $false; suggestedDistribution = 'PyYAML' }) } }
        { Resolve-PpbRequirements -Report $report -ProjectRoot $env:TEMP -WorkDirectory $env:TEMP } | Should -Throw '*declares no dependencies*'
    }
    It 'infers known names only with -InferRequirements' {
        $d = New-TestDir
        try {
            $report = [pscustomobject]@{ dependencySources = @(); imports = [pscustomobject]@{ thirdParty = @([pscustomobject]@{ name = 'yaml'; optional = $false; suggestedDistribution = 'PyYAML' }) } }
            $r = Resolve-PpbRequirements -Report $report -ProjectRoot $d -WorkDirectory $d -InferRequirements
            $r.Lines | Should -Be @('PyYAML')
            Get-Content -LiteralPath $r.File | Should -Contain 'PyYAML'
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
    It 'ranks a pinned requirements file above pyproject ranges' {
        $report = [pscustomobject]@{ dependencySources = @(
                [pscustomobject]@{ kind = 'pyproject'; file = 'pyproject.toml'; requirements = @('requests>=2'); locked = $false },
                [pscustomobject]@{ kind = 'requirements'; file = 'requirements.lock'; requirements = @('requests==2.31.0'); locked = $true }
            ); imports = [pscustomobject]@{ thirdParty = @() } }
        $d = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $d 'requirements.lock') -Value 'requests==2.31.0'
            $r = Resolve-PpbRequirements -Report $report -ProjectRoot $d -WorkDirectory $d
            $r.Kind | Should -Be 'requirements'
            $r.Locked | Should -BeTrue
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
}

Describe 'File selection and secret protection' {
    BeforeAll {
        $script:Proj = New-TestDir
        $files = @{
            'main.py' = 'print(1)'; 'data/input.csv' = 'a,b'; '.env' = 'DB_PASSWORD=real'; '.env.example' = 'DB_PASSWORD=changeme'
            'keys/server.key' = 'x'; '.git/config' = 'x'; '.venv/pyvenv.cfg' = 'x'; 'pkg/__pycache__/m.pyc' = 'x'
            'config/app.json' = '{"password": "${DB_PASSWORD}", "user": "report"}'; 'config/prod.yaml' = "db:`n  password: Hunter2Hunter2`n"
            'certs/ca.pem' = "-----BEGIN CERTIFICATE-----`nMIIB`n-----END CERTIFICATE-----"; 'certs/client.pem' = "-----BEGIN RSA PRIVATE KEY-----`nabc`n-----END RSA PRIVATE KEY-----"
            'notes/todo.txt' = 'x'
        }
        foreach ($k in $files.Keys) {
            $p = Join-Path $script:Proj $k
            New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
            [IO.File]::WriteAllText($p, $files[$k])
        }
    }
    AfterAll { Remove-PpbItem -Path $script:Proj -AllowTempOwned }

    It 'includes code and resources, excludes VCS, venvs and caches' {
        $sel = Get-PpbProjectFileSelection -ProjectRoot $script:Proj -Config $script:Config
        $inc = @($sel.Included | ForEach-Object RelativePath)
        $inc | Should -Contain 'main.py'
        $inc | Should -Contain 'data/input.csv'
        $inc | Should -Contain '.env.example'
        $inc | Should -Contain 'config/app.json'
        $inc | Should -Contain 'certs/ca.pem'
        ($inc | Where-Object { $_ -like '.git/*' -or $_ -like '.venv/*' -or $_ -like '*__pycache__*' }) | Should -BeNullOrEmpty
    }
    It 'withholds credential files and blocks files containing secrets' {
        $sel = Get-PpbProjectFileSelection -ProjectRoot $script:Proj -Config $script:Config
        @($sel.Sensitive | ForEach-Object RelativePath) | Should -Contain '.env'
        @($sel.Sensitive | ForEach-Object RelativePath) | Should -Contain 'keys/server.key'
        $blocked = @($sel.Blocked | ForEach-Object RelativePath)
        $blocked | Should -Contain 'config/prod.yaml'
        $blocked | Should -Contain 'certs/client.pem'
        { Assert-PpbNoBlockedFiles -Selection $sel } | Should -Throw '*credentials or private keys*'
    }
    It 'honours -Exclude and explicit -Include decisions' {
        $sel = Get-PpbProjectFileSelection -ProjectRoot $script:Proj -Config $script:Config -Exclude @('config/prod.yaml', 'certs/client.pem', 'notes/*') -Include @()
        $sel.Blocked.Count | Should -Be 0
        @($sel.Included | ForEach-Object RelativePath) | Should -Not -Contain 'notes/todo.txt'
        $sel2 = Get-PpbProjectFileSelection -ProjectRoot $script:Proj -Config $script:Config -Include @('config/prod.yaml') -Exclude @('certs/client.pem')
        @($sel2.Included | ForEach-Object RelativePath) | Should -Contain 'config/prod.yaml'
        $sel2.Warnings.Count | Should -BeGreaterThan 0
    }
    It 'parses data file specifications and rejects escaping destinations' {
        $df = ConvertFrom-PpbDataFileSpec -Spec 'data/input.csv;resources' -ProjectRoot $script:Proj
        $df.Destination | Should -Be 'resources'
        { ConvertFrom-PpbDataFileSpec -Spec 'data/input.csv;../outside' -ProjectRoot $script:Proj } | Should -Throw '*relative*'
    }
}

Describe 'PyInstaller helpers' {
    It 'maps resources relative to the import root' {
        $map = @(Get-PpbBundleDataMap -Resources @('src/pkg/res/a.json', 'config/b.yaml', 'top.txt') -ImportRoots @('src'))
        ($map | Where-Object Source -eq 'src/pkg/res/a.json').DestinationDir | Should -Be 'pkg/res'
        ($map | Where-Object Source -eq 'config/b.yaml').DestinationDir | Should -Be 'config'
        ($map | Where-Object Source -eq 'top.txt').DestinationDir | Should -Be '.'
    }
    It 'computes relative paths between directories' {
        Get-PpbRelativePathAny -Path 'C:\Out\Pkg\.build\stage\app' -BasePath 'C:\Out\Pkg\pyinstaller' | Should -Be '..\.build\stage\app'
    }
    It 'escapes Python string literals' {
        ConvertTo-PpbPyLiteral "C:\it's" | Should -Be "'C:\\it\'s'"
    }
}

Describe 'Archives and checksums' {
    It 'creates a verified ZIP with a single root folder and refuses foreign files' {
        $d = New-TestDir
        try {
            $pkg = New-PpbDirectory (Join-Path $d 'Demo'); Write-PpbOwnershipMarker -Directory $pkg -PackageName 'Demo'
            $dist = New-PpbDirectory (Join-Path $pkg 'distribution')
            New-PpbDirectory (Join-Path $dist 'app') | Out-Null
            Set-Content -LiteralPath (Join-Path $dist 'app\x.py') -Value 'print(1)'
            Set-Content -LiteralPath (Join-Path $dist 'verify.ps1') -Value '#'
            (New-PpbChecksumFile -Root $dist) | Should -Be 2
            $zip = Join-Path $d (Get-PpbZipFileName -Name 'Demo' -Type 'executable' -Mode 'onedir')
            $info = New-PpbDistributionZip -DistributionPath $dist -ZipPath $zip -RootFolderName 'Demo' -PackageDirectory $pkg
            $info.files | Should -Be 3
            Split-Path -Leaf $zip | Should -Be 'Demo-executable-onedir.zip'
            Test-Path "$zip.sha256" | Should -BeTrue
            # Rebuilding replaces our own ZIP ...
            { New-PpbDistributionZip -DistributionPath $dist -ZipPath $zip -RootFolderName 'Demo' -PackageDirectory $pkg } | Should -Not -Throw
            # ... but never a file the toolkit did not create.
            $foreign = Join-Path $d 'Demo-embedded.zip'
            Set-Content -LiteralPath $foreign -Value 'not ours'
            { New-PpbDistributionZip -DistributionPath $dist -ZipPath $foreign -RootFolderName 'Demo' -PackageDirectory $pkg } | Should -Throw '*not created*'
            Get-Content -LiteralPath $foreign | Should -Be 'not ours'
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
    It 'finds build-machine paths in launch files' {
        $d = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $d 'run.cmd') -Value '"C:\BuildBox\src\python.exe" %*'
            Set-Content -LiteralPath (Join-Path $d 'README.md') -Value 'built from c:/buildbox/src'
            $hits = @(Find-PpbBuildPathReferences -Root $d -Needles @('C:\BuildBox\src'))
            ($hits | Where-Object RelativePath -eq 'run.cmd').Critical | Should -BeTrue
            ($hits | Where-Object RelativePath -eq 'README.md').Critical | Should -BeFalse
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
}

Describe 'Templates' {
    It 'renders tokens and rejects unknown tokens' {
        $d = New-TestDir
        try {
            $t = Join-Path $d 't.txt'
            Set-Content -LiteralPath $t -Value 'Hello {{NAME}}'
            (Expand-PpbTemplate $t @{ NAME = 'World' }).Trim() | Should -Be 'Hello World'
            Set-Content -LiteralPath $t -Value 'Hello {{OTHER}}'
            { Expand-PpbTemplate $t @{ NAME = 'World' } } | Should -Throw '*unknown token*'
        } finally { Remove-PpbItem -Path $d -AllowTempOwned }
    }
    It 'uses only tokens supplied by the builders' {
        foreach ($f in 'embedded\run.cmd', 'embedded\run.ps1', 'deployment\README.template.md', 'deployment\DEPLOYMENT.template.md') {
            $text = Get-Content -Raw -LiteralPath (Join-Path $script:Root "templates\$f")
            $tokens = [regex]::Matches($text, '\{\{([A-Z_]+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
            $known = 'NAME', 'TOOLKIT_VERSION', 'PYTHON_EXE', 'WORKING_DIRECTORY', 'WINDOWED', 'BUILD_TIME', 'TYPE_DESCRIPTION', 'PYTHON_VERSION', 'ARCH',
                'ENTRY', 'RUN_COMMAND', 'LAYOUT', 'PREREQUISITES', 'ENV_VARS', 'UPDATE_SECTION', 'LIMITATIONS', 'ZIP_NAME', 'EXECUTION_REQUIREMENT'
            foreach ($t in $tokens) { $known | Should -Contain $t }
        }
    }
    It 'keeps run.cmd ASCII-only' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $script:Root 'templates\embedded\run.cmd'))
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Repository portability' {
    It 'contains no absolute paths of this machine in toolkit sources' {
        $needles = @($script:Root, $env:USERPROFILE) | Where-Object { $_ }
        $files = Get-ChildItem -LiteralPath $script:Root -Recurse -File -Include *.ps1, *.psm1, *.py, *.json, *.cmd, *.md |
            Where-Object { $_.FullName -notmatch '\\(\.git|tests\\fixtures)\\' -and $_.Name -ne 'ProjectSpec.md' }
        foreach ($f in $files) {
            $text = [IO.File]::ReadAllText($f.FullName)
            foreach ($n in $needles) { $text.IndexOf($n, [StringComparison]::OrdinalIgnoreCase) | Should -Be -1 -Because $f.FullName }
        }
    }
}
