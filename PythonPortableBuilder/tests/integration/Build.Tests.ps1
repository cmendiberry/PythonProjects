#Requires -Version 5.1
# End-to-end tests: real builds of the fixture projects (Pester 5).
# Requires internet access (python.org embeddable runtime, PyPI) and a 64-bit CPython on the build machine.
# All output goes to a temporary directory (path with spaces and a non-ASCII character) that is removed afterwards.

BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Fixtures = Join-Path $script:Root 'tests\fixtures'
    $script:Ps = (Get-Process -Id $PID).Path
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("ppb-it-{0} dir {1}" -f [Guid]::NewGuid().ToString('N').Substring(0, 8), [char]0x00F1)
    $script:Out = Join-Path $script:Work 'Portable Builds'
    New-Item -ItemType Directory -Path $script:Out -Force | Out-Null

    function Invoke-Ppb {
        param([string]$Script, [string[]]$Arguments)
        $out = & $script:Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:Root $Script) @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    }
    function Invoke-Run {
        param([string]$Command, [string[]]$Arguments)
        $out = & $Command @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    }
    function Get-TreeHash {
        param([string]$Path)
        $items = Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
            if ($_.PSIsContainer) { "D $($_.FullName)" } else { "F $($_.FullName) $((Get-FileHash -LiteralPath $_.FullName).Hash)" }
        }
        return ($items -join "`n")
    }
    function Copy-Fixture {
        param([string]$Name)
        $dest = Join-Path $script:Work "src with spaces\$Name"
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Fixtures $Name) -Destination $dest -Recurse -Force
        return $dest
    }
    $script:FixtureHashBefore = Get-TreeHash $script:Fixtures
}

AfterAll {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Embedded backend' -Tag 'Integration' {
    It 'packages a single-file script from a path with spaces and forwards arguments and exit codes' {
        $src = Copy-Fixture 'single-file'
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $src 'echo_args.py'), '-Name', 'EchoArgs', '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $dist = Join-Path $script:Out 'EchoArgs\distribution'
        $run = Invoke-Run (Join-Path $dist 'run.cmd') @('two words', 'x', '--exit-code', '3')
        $run.ExitCode | Should -Be 3
        $run.Output | Should -Match ([regex]::Escape('"words": ["two words", "x"]'))
        $ps = Invoke-Run $script:Ps @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dist 'run.ps1'), 'alpha beta', '--exit-code', '4')
        $ps.ExitCode | Should -Be 4
        $ps.Output | Should -Match 'alpha beta'
        Test-Path (Join-Path $script:Out 'EchoArgs-embedded.zip') | Should -BeTrue
        Test-Path (Join-Path $script:Out 'EchoArgs-embedded.zip.sha256') | Should -BeTrue
        $m = Get-Content -Raw (Join-Path $script:Out 'EchoArgs\build-manifest.json') | ConvertFrom-Json
        $m.package.type | Should -Be 'embedded'
        $m.validation.status | Should -Be 'passed'
        $m.python.runtime.source | Should -Match '^https://www\.python\.org/ftp/python/'
        $m.artifacts.zip.sha256 | Should -Match '^[0-9a-f]{64}$'
        (Get-Content -Raw (Join-Path $dist 'build-manifest.json')) | Should -Not -Match ([regex]::Escape($src.Replace('\', '\\')))
    }

    It 'still runs after the distribution is moved to another directory' {
        $moved = Join-Path $script:Work "moved here\EchoArgs"
        New-Item -ItemType Directory -Path (Split-Path -Parent $moved) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Out 'EchoArgs\distribution') -Destination $moved -Recurse
        $run = Invoke-Run (Join-Path $moved 'run.cmd') @('moved')
        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match 'moved'
        # The launcher probe reports which interpreter is used: it must be the moved copy's runtime.
        $env:PPB_LAUNCHER_PROBE = '1'
        try { $probe = Invoke-Run (Join-Path $moved 'run.cmd') @('x') } finally { Remove-Item Env:PPB_LAUNCHER_PROBE }
        $probe.Output | Should -Match ([regex]::Escape('moved here'))
        $probe.Output | Should -Not -Match ([regex]::Escape('Portable Builds'))
    }

    It 'packages a multi-module package with relative imports (python -m entry point)' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'multi-module'), '-Name', 'Calc', '-Type', 'embedded', '-Output', $script:Out, '-NoZip')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $run = Invoke-Run (Join-Path $script:Out 'Calc\distribution\run.cmd') @('2', '3')
        $run.Output | Should -Match 'SUM 5'
        Test-Path (Join-Path $script:Out 'Calc-embedded.zip') | Should -BeFalse
    }

    It 'installs third-party dependencies into packages\ and ships JSON/YAML resources' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'resources-yaml'), '-Name', 'YamlReport', '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $dist = Join-Path $script:Out 'YamlReport\distribution'
        Test-Path (Join-Path $dist 'packages\yaml') | Should -BeTrue
        Test-Path (Join-Path $dist 'app\config\settings.yaml') | Should -BeTrue
        (Invoke-Run (Join-Path $dist 'run.cmd') @()).Output | Should -Match 'REPORT Quarterly EUR'
        $m = Get-Content -Raw (Join-Path $dist 'build-manifest.json') | ConvertFrom-Json
        @($m.dependencies.installed | ForEach-Object name) | Should -Contain 'PyYAML'
        ($m.validation.results | Where-Object name -eq 'dependency-imports').status | Should -Be 'passed'
    }

    It 'supports src layouts with declared console scripts' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'src-layout'), '-Type', 'embedded', '-Output', $script:Out, '-NoZip')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $dist = Join-Path $script:Out 'srcapp\distribution'
        (Get-Content (Join-Path $dist 'runtime\python*._pth')) | Should -Contain '..\app\src'
        (Invoke-Run (Join-Path $dist 'run.cmd') @('x', 'y')).Output | Should -Match 'SRCAPP x y'
    }

    It 'requires -EntryPoint for ambiguous projects and accepts an explicit one' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'ambiguous'), '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 2
        $r.Output | Should -Match 'first\.py'
        $r.Output | Should -Match 'second\.py'
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'ambiguous'), '-Type', 'embedded', '-EntryPoint', 'second.py', '-Output', $script:Out, '-NoZip')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        (Invoke-Run (Join-Path $script:Out 'ambiguous\distribution\run.cmd') @('ok')).Output | Should -Match 'SECOND ok'
    }

    It 'rebuilds, verifies and cleans an existing package' {
        $pkg = Join-Path $script:Out 'Calc'
        (Invoke-Ppb 'rebuild.ps1' @('-Path', $pkg)).ExitCode | Should -Be 0
        $v = Invoke-Ppb 'verify.ps1' @('-Path', $pkg)
        $v.ExitCode | Should -Be 0 -Because $v.Output
        $vz = Invoke-Ppb 'verify.ps1' @('-Path', (Join-Path $script:Out 'EchoArgs-embedded.zip'))
        $vz.ExitCode | Should -Be 0 -Because $vz.Output
        (Invoke-Ppb 'clean.ps1' @('-Path', $pkg)).ExitCode | Should -Be 0
        Test-Path (Join-Path $pkg '.build') | Should -BeFalse
        Test-Path (Join-Path $pkg 'distribution\run.cmd') | Should -BeTrue
    }

    It 'detects tampering with runtime files but only warns about updated application files' {
        $dist = Join-Path $script:Out 'Calc\distribution'
        Add-Content -LiteralPath (Join-Path $dist 'app\calc\ops.py') -Value '# updated application file'
        $r = Invoke-Ppb 'verify.ps1' @('-Path', $dist, '-NoTempCopy', '-SkipAppRun')
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'application file\(s\) changed'
        Add-Content -LiteralPath (Join-Path $dist 'launcher\ppb_launch.py') -Value '# tampered'
        (Invoke-Ppb 'verify.ps1' @('-Path', $dist, '-NoTempCopy', '-SkipAppRun')).ExitCode | Should -Be 3
    }
}

Describe 'Executable backend' -Tag 'Integration' {
    It 'builds a onefile executable that forwards arguments and exit codes' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'single-file\echo_args.py'), '-Name', 'EchoOne', '-Type', 'executable', '-Mode', 'onefile', '-Output', $script:Out)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $exe = Join-Path $script:Out 'EchoOne\distribution\EchoOne.exe'
        $run = Invoke-Run $exe @('two words', '--exit-code', '6')
        $run.ExitCode | Should -Be 6
        $run.Output | Should -Match 'two words'
        Test-Path (Join-Path $script:Out 'EchoOne-executable-onefile.zip') | Should -BeTrue
        Test-Path (Join-Path $script:Out 'EchoOne\pyinstaller\EchoOne.spec') | Should -BeTrue
        Test-Path (Join-Path $script:Out 'EchoOne\distribution\_internal') | Should -BeFalse
    }

    It 'builds a onedir executable with third-party dependencies and resources' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'resources-yaml'), '-Name', 'YamlExe', '-Type', 'executable', '-Mode', 'onedir', '-Output', $script:Out)
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $dist = Join-Path $script:Out 'YamlExe\distribution'
        Test-Path (Join-Path $dist '_internal\config\settings.yaml') | Should -BeTrue
        $tmpRun = Invoke-Run (Join-Path $dist 'YamlExe.exe') @()
        $tmpRun.ExitCode | Should -Be 0 -Because $tmpRun.Output
        $tmpRun.Output | Should -Match 'REPORT Quarterly EUR'
        Test-Path (Join-Path $script:Out 'YamlExe-executable-onedir.zip') | Should -BeTrue
        $m = Get-Content -Raw (Join-Path $dist 'build-manifest.json') | ConvertFrom-Json
        $m.package.mode | Should -Be 'onedir'
        $m.artifacts.executable.sha256 | Should -Match '^[0-9a-f]{64}$'
    }
}

Describe 'Error handling and safety' -Tag 'Integration' {
    It 'stops when a dependency cannot be installed' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'missing-dependency'), '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'Dependency installation failed'
        Test-Path (Join-Path $script:Out 'missing-dependency-embedded.zip') | Should -BeFalse
    }
    It 'rejects invalid project metadata' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'invalid-metadata'), '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 2
        $r.Output | Should -Match 'pyproject\.toml could not be parsed'
    }
    It 'refuses undeclared third-party imports instead of guessing package names' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'undeclared-import'), '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 2
        $r.Output | Should -Match 'yaml -> PyYAML'
    }
    It 'blocks configuration files that contain secrets until the user decides' {
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'secret-config'), '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 2
        $r.Output | Should -Match 'settings\.json'
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'secret-config'), '-Type', 'embedded', '-Exclude', 'settings.json', '-Output', $script:Out, '-NoZip')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        Test-Path (Join-Path $script:Out 'secret-config\distribution\app\settings.json') | Should -BeFalse
    }
    It 'rejects an output directory inside the source project' {
        $src = Copy-Fixture 'multi-module'
        $r = Invoke-Ppb 'build.ps1' @('-Source', $src, '-Type', 'embedded', '-Output', (Join-Path $src 'out'))
        $r.ExitCode | Should -Be 2
        Test-Path (Join-Path $src 'out') | Should -BeFalse
    }
    It 'never overwrites an existing directory it did not create' {
        $foreign = Join-Path $script:Out 'Foreign'
        New-Item -ItemType Directory -Path $foreign -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $foreign 'important.txt') -Value 'keep me'
        $r = Invoke-Ppb 'build.ps1' @('-Source', (Join-Path $script:Fixtures 'multi-module'), '-Name', 'Foreign', '-Type', 'embedded', '-Output', $script:Out)
        $r.ExitCode | Should -Be 2
        Get-Content -LiteralPath (Join-Path $foreign 'important.txt') | Should -Be 'keep me'
        (Invoke-Ppb 'clean.ps1' @('-Path', $foreign)).ExitCode | Should -Be 2
        Test-Path (Join-Path $foreign 'important.txt') | Should -BeTrue
    }
    It 'shows help and returns 0' {
        $r = Invoke-Ppb 'build.ps1' @('-Help')
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'SYNOPSIS'
    }
    It 'never modified the source fixtures' {
        Get-TreeHash $script:Fixtures | Should -Be $script:FixtureHashBefore
    }
}
