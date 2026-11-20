# CLAUDE.md — PythonPortableBuilder

Development conventions and maintenance notes for AI assistants and maintainers.
`ProjectSpec.md` is the original requirements document: **never modify it**.

## What this is

A Windows PowerShell toolkit that packages any Python script/project as:
- **embedded**: official CPython embeddable ZIP + `packages\` (pip `--target`) + `app\` + launchers, or
- **executable**: PyInstaller `onedir`/`onefile`.

Entry points: `build.ps1` (orchestrator), `rebuild.ps1`, `verify.ps1`, `clean.ps1`.

## Architecture (where to change what)

| Concern | File |
|---|---|
| Logging, config, path safety, deletion guards, ownership markers, process execution, templates | `modules/Common.psm1` |
| Static analysis (AST, never executes project code) | `python/ppb_analyzer.py` + `modules/ProjectAnalyzer.psm1` |
| Interpreter discovery, version selection, embeddable download/verification, venvs, `._pth` | `modules/PythonRuntimeManager.psm1` |
| Requirement source selection, pip, inventory, native DLL/wheel checks | `modules/DependencyManager.psm1`, `python/ppb_inspect.py` |
| File selection, secret scanning, copying | `modules/ResourceManager.psm1` |
| Embedded backend | `modules/EmbeddedBuilder.psm1`, `templates/embedded/*` |
| PyInstaller backend (spec generation) | `modules/ExecutableBuilder.psm1` |
| Validation | `templates/distribution/verify.ps1` (standalone, shipped in every package) + `modules/PackageValidator.psm1` (build-side: path leaks, temp-copy run) |
| Manifest, prerequisites, limitations, README/DEPLOYMENT rendering | `modules/BuildManifest.psm1`, `templates/deployment/*` |
| ZIP, SHA256SUMS | `modules/ArchiveManager.psm1` |
| Defaults | `config/defaults.json` (user overrides: git-ignored `config/local.json`, env `PPB_OUTPUT_ROOT`, `PPB_CACHE_DIR`) |

Build flow: analysis → package dir + ownership marker → file selection → Python target → requirements →
backend build → docs/manifest/SHA256SUMS → validation (temp copy) → manifest update → ZIP → build-config.json.
Builders receive one context hashtable (`$ctx` in `build.ps1`) and return a result hashtable with:
`Runtime, Inventory, NativeReport, ImportNames, MissingImports, RequiredFiles, BundledResources, RunCommand`
(+ `Embedded` or `PyInstaller`). A new backend must return the same shape.

## Hard rules (requirements from ProjectSpec.md)

- Never hardcode absolute paths, drive letters, user names or the repo location. Use `$PSScriptRoot` / `Get-PpbToolkitRoot`.
- Never modify the source project. The executable backend builds from a staged copy.
- Output goes outside the repository and outside the source. Never overwrite or delete anything without the
  `.ppb-owned.json` ownership marker. Delete only through `Remove-PpbItem -OwnerRoot ...`.
- Download Python only from `https://www.python.org/ftp/python/`. Always verify the checksum (release API), archive and Authenticode.
- Never execute project code during analysis. Never run `setup.py`. Validation may run the app only with an
  existing safe option (`--help` from argparse/click/typer, or user-supplied `-SafeTestArgs`), with credential env vars scrubbed.
- Never invent application flags. Never connect to databases. Never disable TLS validation.
- Never package credentials; never write env var values or URL credentials into logs or manifests (`Protect-PpbText`).
- Don't silently skip failed or missing dependencies; stop the build with an actionable message.
- If the entry point is ambiguous, stop and list the candidates (exit 2). Never guess.
- Do not choose a license and do not push/publish without explicit authorization from the owner.

## PowerShell conventions and known pitfalls

- Must run on **Windows PowerShell 5.1**: no `??`, ternary, `-AsHashtable`, `ProcessStartInfo.ArgumentList`.
- `Set-StrictMode -Version 2.0`; `$ErrorActionPreference = 'Stop'`. Use `Get-PpbValue $obj 'prop' $default` for optional JSON properties.
- Errors: `Stop-PpbWithError "<message>" <exitCode>` — 1 build error, 2 invalid input/ambiguity, 3 validation failed.
- **List-returning functions emit items normally; callers wrap with `@(...)`.** `return , $list` + `@()` double-wraps (this bug happened).
- **Variables are case-insensitive**: a local `$requirements` overwrites the `[string]$Requirements` parameter (this bug happened). Use distinct names.
- `[bool]` parameters cannot receive `$false` through `powershell -File`; that is why `-NoZip`/`-SkipVerify` exist next to `-CreateZip`/`-Verify`.
- `Test-Path -LiteralPath` does not expand wildcards; use `Get-ChildItem -Filter`.
- Run processes only through `Invoke-PpbProcess` (MSVCRT quoting, streaming, env control, timeout).
- Files: `Write-PpbTextFile` / `Write-PpbJsonFile` (UTF-8 without BOM). `run.cmd` must be ASCII + CRLF (`-Crlf`).
- Templates use `{{TOKEN}}`; unknown tokens throw. When adding tokens, update the token list in `tests/unit/Modules.Tests.ps1`.
- When editing files with backslash-heavy content, avoid shell heredocs into Python string literals (`\a` became a BEL character once); prefer the editor tool.

## Python helper conventions

- Standard library only, Python 3.8-compatible syntax (they run on whatever interpreter the build machine has,
  and `ppb_launch.py`/`ppb_selftest.py` run on the embedded runtime).
- Run with `-I -B` (isolated, no bytecode) when invoked by the toolkit on a host interpreter.

## Testing

```powershell
.\tests\Run-Tests.ps1                    # unit: python unittest (tests/unit/test_*.py) + Pester (tests/unit/*.Tests.ps1)
.\tests\Run-Tests.ps1 -Integration       # + real builds (tests/integration), needs internet, ~5-10 min
.\tests\Run-Tests.ps1 -PesterPath <dir>  # if Pester 5 is not installed (Windows ships 3.4, which is incompatible)
```

Fixtures in `tests/fixtures/` cover: single file, multi-module (`python -m`), JSON/YAML resources + PyYAML,
src layout, ambiguous entry points, missing dependency, invalid metadata, undeclared import, secret in config.
Integration tests also cover paths with spaces/non-ASCII, moved distributions, rebuild/verify/clean, tamper
detection, ownership protection, and an unchanged source tree. Add a fixture and test for every new scenario or bug.

Quick manual check:
```powershell
.\build.ps1 -Source .\examples\simple-script\hello.py -Type embedded -Output $env:TEMP\ppb-out
.\build.ps1 -Source .\examples\multi-module-app -Type executable -Mode onedir -Output $env:TEMP\ppb-out
```

## Maintenance

- Bump `VERSION` and update `CHANGELOG.md` for user-visible changes.
- PyInstaller version range: `pyinstallerRequirement` in `config/defaults.json`. After raising it, run the
  integration tests (the spec template in `New-PpbPyInstallerSpec` and the onefile archive (CArchive) reader in
  `templates/distribution/verify.ps1` depend on PyInstaller internals).
- python.org API endpoints: `pythonDownload.apiUrl` in `config/defaults.json`.
- The import→pip-name map (`KNOWN_IMPORT_TO_DIST`) and database knowledge are in `python/ppb_analyzer.py`.
- Keep README.md (user documentation), CONTRIBUTING.md and this file consistent with behaviour changes.
- Git: work on a branch, commit only when the owner asks, and never commit build output or `config/local.json`.
