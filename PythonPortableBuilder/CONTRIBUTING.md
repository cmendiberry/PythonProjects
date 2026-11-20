# Contributing to PythonPortableBuilder

## Development setup

* Windows 10/11, Windows PowerShell 5.1 (the minimum supported host) and optionally PowerShell 7.
* CPython 3.8+ 64-bit on PATH (integration tests use the default `python.exe`).
* Pester 5.3+: `Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck`
  (Windows' built-in Pester 3.4 does not work).
* Optional: PSScriptAnalyzer (`Install-Module PSScriptAnalyzer -Scope CurrentUser`).

## Running tests

```powershell
.\tests\Run-Tests.ps1                     # unit tests: Python unittest + Pester, offline, ~15 s
.\tests\Run-Tests.ps1 -Integration        # + real builds of every fixture (internet, ~5-10 min)
python -m unittest discover -s tests\unit -p "test_*.py"    # Python helpers only
```

Integration tests build into a temporary directory whose path contains spaces and a non-ASCII
character, and remove it afterwards. They need access to www.python.org and your package index.

Every change must keep all unit tests green. Run the integration tests when you touch builders,
launchers, templates, validation or dependency handling.

## Coding conventions

* **PowerShell 5.1 compatible**: no `??`, `?:`, `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`
  or .NET Core-only APIs (`ProcessStartInfo.ArgumentList`).
* `Set-StrictMode -Version 2.0` and `$ErrorActionPreference = 'Stop'` in every script and module.
* Public functions use the `Ppb` noun prefix and approved verbs. Fail with
  `Stop-PpbWithError "<actionable message>" <exitCode>` (1 build error, 2 invalid input, 3 validation).
* Functions that return lists emit their items normally. **Callers always wrap the call in `@(...)`.**
  Never use `return , $list` in functions that are called with `@()`.
* Never name a local variable like a script parameter (`$requirements` vs `-Requirements`): PowerShell
  variables are case-insensitive, and the parameter's type conversion applies.
* Run external processes only through `Invoke-PpbProcess` (correct Windows quoting, streaming to the log,
  environment control, timeouts).
* Delete only through `Remove-PpbItem` with an `-OwnerRoot` that carries an ownership marker.
* Write files with `Write-PpbTextFile`/`Write-PpbJsonFile` (UTF-8 without BOM). Batch files must be ASCII with CRLF.
* Python helpers (`python/`, `templates/embedded/*.py`): standard library only, Python 3.8 syntax, and
  they must never import or execute project code (except third-party dependency imports in the self-test).
* No machine-specific paths, user names, company names, endpoints or credentials anywhere in the repository.

## Adding things

* **A new build option**: add the parameter to `build.ps1` (with comment-based help), the `ppb.json`
  key to `Get-PpbProjectConfig`'s allow-list if it applies per project, the context field, README
  documentation and a test.
* **A new template token**: update the template, the token table in the builder or `BuildManifest.psm1`,
  and the token list in `tests/unit/Modules.Tests.ps1`. Unknown tokens fail at build time.
* **A new validation check**: implement it in `templates/distribution/verify.ps1` (it must stay
  standalone) or, for build-only checks, in `PackageValidator.psm1`.
* **A new backend (e.g. Linux)**: add a `<Name>Builder.psm1` that returns the same result hashtable as
  `Invoke-PpbEmbeddedBuild` (Runtime, Inventory, NativeReport, ImportNames, MissingImports,
  RequiredFiles, BundledResources, RunCommand), then dispatch to it in `build.ps1`.

## Commits and releases

* Update `CHANGELOG.md` (Unreleased section) with user-visible changes.
* Bump `VERSION` (semantic versioning) when releasing; it is recorded in every manifest.
* Do not commit build output, downloaded runtimes, `config/local.json` or credentials (see `.gitignore`).
