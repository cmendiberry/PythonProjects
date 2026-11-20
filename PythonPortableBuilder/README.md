# PythonPortableBuilder

A reusable Windows toolkit that turns an existing Python script or project into a **deployable,
self-contained distribution**. You point it at the project and get either:

* an **embedded Python** package: the official CPython runtime plus your code and its dependencies, or
* a **standalone executable** built with PyInstaller (`onefile` or `onedir`).

The destination server does **not** need a Python installation, pip, internet access, PATH
changes, registry changes or administrator rights to install Python.

```powershell
.\build.ps1 -Source "D:\projects\reports" -Name "E2Reports" -Type embedded -Output "D:\PortableBuilds"
.\build.ps1 -Source "D:\descargas\dbusers" -Name "DBUserManager" -Type executable -Mode onedir -Output "D:\PortableBuilds"
```

No project-specific scripts are needed: the toolkit analyses the project, chooses the entry point and
dependency source, builds, validates and zips the result. You can reuse it for any compatible project
without changing the toolkit's source code.

---

## Contents

1. [Packaging methods](#packaging-methods)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Usage](#usage)
5. [Parameters](#parameters)
6. [What the build does](#what-the-build-does)
7. [Output layout](#output-layout)
8. [Validation](#validation)
9. [Per-project configuration (ppb.json)](#per-project-configuration-ppbjson)
10. [Database applications](#database-applications)
11. [Updating an embedded application](#updating-an-embedded-application)
12. [Troubleshooting](#troubleshooting)
13. [Security](#security)
14. [Limitations](#limitations)
15. [Repository layout](#repository-layout)
16. [Testing the toolkit](#testing-the-toolkit)
17. [License](#license)

---

## Packaging methods

| | Embedded Python (`-Type embedded`) | Executable onedir (`-Type executable -Mode onedir`) | Executable onefile (`-Mode onefile`) |
|---|---|---|---|
| Built with | Official CPython *Windows embeddable package* from python.org | PyInstaller | PyInstaller |
| You run | `run.cmd` / `run.ps1` | `<Name>.exe` | `<Name>.exe` |
| Contents | `runtime\`, `packages\`, `app\` (your sources as files) | `<Name>.exe` + `_internal\` | one `.exe` |
| Startup | Fast | Fast | Slower: extracts itself to `%TEMP%\_MEI*` on every start |
| Update the code only | Replace files in `app\` | Rebuild | Rebuild |
| Source visible | Yes (plain `.py`) | Bytecode inside the bundle | Bytecode inside the exe |
| What must be allowed to run | `runtime\python.exe` | `<Name>.exe` | `<Name>.exe`, plus extraction to TEMP |
| tkinter | Copied from a matching local Python | Bundled by PyInstaller | Bundled by PyInstaller |

**Choosing a method**

* **Embedded** suits scripts and tools that you update often (copy new `.py` files), and environments
  where security teams want to see the official, signed `python.exe`.
* **onedir** is a good default for executables: fast startup and easy to inspect.
* **onefile** gives you a single file to copy around. Antivirus products and restricted TEMP folders
  affect it most.

> The embedded option still needs permission to execute the official `python.exe`. It does **not**
> bypass application-control policies such as AppLocker or WDAC.

---

## Requirements

### Build machine

| Requirement | Notes |
|---|---|
| Windows 10/11 or Windows Server 2016+ | The toolkit builds Windows packages only. |
| Windows PowerShell 5.1 or PowerShell 7+ | Uses only built-in cmdlets and .NET. |
| CPython 3.8+ (64-bit for `amd64` packages) | From python.org or the Microsoft Store. Analysis needs any Python 3.8+. **Executables** need exactly the Python version they should contain. **Embedded** builds should have the same minor version (e.g. 3.11.x) for dependency installation; see [cross-installation](#python-version-selection). |
| Internet access to `www.python.org` and your package index (PyPI or a mirror configured in `pip.ini`) | Embeddable runtimes are cached. For offline builds use `-RuntimeZip`. PyInstaller is installed from your index into an isolated environment. |
| git (optional) | Records the source commit in the manifest. |

You don't need to install anything globally: build environments are virtual environments inside the output directory.

### Destination server

* Windows with a version supported by the packaged Python release (for example, Python 3.9 and newer
  do not support Windows 7). Test on your target OS: **no Windows version is guaranteed**.
* The same architecture as the package (`amd64` by default).
* Permission to run `runtime\python.exe` (embedded) or `<Name>.exe` (executable).
* External prerequisites reported in `DEPLOYMENT.md` / `build-manifest.json`, such as ODBC drivers,
  database client libraries, CA certificates, credentials, DNS/network access to database ports,
  and an interactive desktop for GUI apps.

---

## Installation

```powershell
git clone <your-repository-url> C:\Tools\PythonPortableBuilder
cd C:\Tools\PythonPortableBuilder
Get-Help .\build.ps1 -Detailed
```

The toolkit resolves every internal path relative to its own location (`$PSScriptRoot`), so you can
clone it anywhere, including paths with spaces, and run it from any working directory.

If script execution is restricted:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned      # one-time, or:
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Source ... -Type embedded
# Files downloaded as a ZIP may be blocked: Get-ChildItem -Recurse | Unblock-File
```

**Default output location**: `..\PortableBuilds`, next to the repository and never inside it. To change it:

* pass `-Output D:\PortableBuilds`, or
* set the environment variable `PPB_OUTPUT_ROOT`, or
* create `config\local.json` (git-ignored) with `{ "outputRoot": "D:\\PortableBuilds" }`.

---

## Usage

### A simple script

```powershell
.\build.ps1 -Source D:\scripts\cleanup.py -Type embedded
D:\PortableBuilds\cleanup\distribution\run.cmd --dry-run
```

### A multi-module project

```powershell
.\build.ps1 -Source D:\projects\reports -Name E2Reports -Type embedded -Output D:\PortableBuilds
```

### An embedded package

```powershell
.\build.ps1 -Source .\examples\multi-module-app -Type embedded
```

### A onefile executable

```powershell
.\build.ps1 -Source .\examples\simple-script\hello.py -Name Hello -Type executable -Mode onefile
```

### A onedir executable

```powershell
.\build.ps1 -Source D:\descargas\dbusers -Name DBUserManager -Type executable -Mode onedir -Output D:\PortableBuilds
```

### An explicit Python version

```powershell
.\build.ps1 -Source D:\projects\reports -Type embedded -PythonVersion 3.11        # newest 3.11.x with an embeddable ZIP
.\build.ps1 -Source D:\projects\reports -Type embedded -PythonVersion 3.11.9      # exactly 3.11.9
```

### An explicit entry point

```powershell
.\build.ps1 -Source D:\src\tool -Type embedded -EntryPoint tools\run_report.py    # script
.\build.ps1 -Source D:\src\tool -Type embedded -EntryPoint tool.cli               # module (python -m tool.cli)
.\build.ps1 -Source D:\src\tool -Type embedded -EntryPoint tool.cli:main          # callable
.\build.ps1 -Source D:\src\tool -Type embedded -EntryPoint tool-report            # a declared console script name
```

### A custom output directory

```powershell
.\build.ps1 -Source D:\src\tool -Type executable -Output "E:\Release Builds"
```

### Rebuilding an existing distribution

```powershell
.\rebuild.ps1 -Path D:\PortableBuilds\E2Reports                 # same parameters as the original build
.\rebuild.ps1 -Path D:\PortableBuilds\E2Reports -Clean          # also recreate build environments
.\rebuild.ps1 -Path D:\PortableBuilds\E2Reports -Override @{ PythonVersion = '3.12'; Source = 'E:\moved\reports' }
```

### Verifying an existing package

```powershell
.\verify.ps1 -Path D:\PortableBuilds\E2Reports                          # package directory
.\verify.ps1 -Path D:\PortableBuilds\DBUserManager-executable-onedir.zip  # ZIP (checksum + contents)
# On the destination server, without the toolkit:
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Apps\E2Reports\verify.ps1
```

### Cleaning temporary build files

```powershell
.\clean.ps1 -Path D:\PortableBuilds\E2Reports                   # removes <package>\.build only
.\clean.ps1 -OutputRoot D:\PortableBuilds -IncludeCache -WhatIf # preview cleaning every package + runtime cache
```

---

## Parameters

`build.ps1` (run `Get-Help .\build.ps1 -Full` for details):

| Parameter | Description |
|---|---|
| `-Source` (required) | Python script (`.py`) or project directory. |
| `-Type` (required) | `embedded` or `executable`. |
| `-Name` | Distribution name. Defaults to the project name (`pyproject.toml`, `setup.cfg`, `setup.py`) or the source name. |
| `-Mode` | `onedir` (default) or `onefile`. Applies to executables only. |
| `-Output` | Output root. See [Installation](#installation) for the default. |
| `-EntryPoint` | Script, module, `module:function` or declared script name. Detected automatically. |
| `-PythonVersion` | `X.Y` or `X.Y.Z`. Defaults to `.python-version`, `requires-python` or the default local interpreter. |
| `-Requirements` | Explicit requirements file. Takes priority over every detected declaration. |
| `-Clean` | Recreate the build environments and remove previous work files. |
| `-CreateZip` / `-NoZip` | Create the ZIP (default `$true`). Use `-NoZip` when calling through `powershell -File` or cmd. |
| `-Verify` / `-SkipVerify` | Validate the distribution (default `$true`). |
| `-Verbose` | PowerShell's common parameter: shows tool output and debug details. `build.log` always contains everything. |
| `-Help` | Shows usage and examples (`Get-Help` works as well). |
| `-Architecture` | `amd64` (default), `win32`, `arm64`. |
| `-Windowed` | GUI application: no console (PyInstaller windowed, `pythonw.exe`). |
| `-Icon` | `.ico` file for executables. |
| `-HiddenImport` | Extra modules PyInstaller cannot detect. |
| `-DataFile` | Extra data, given as `'source;destination'` (destination relative to the application root). |
| `-AdditionalPath` | Extra import directories, relative to the project root. |
| `-CollectPackage` | Packages whose submodules should all be bundled (plugin systems). |
| `-Include` / `-Exclude` | Glob patterns (`data/*.csv`, `**/*.log`, `secrets.*`). `-Include` overrides default exclusions and the secret scan. |
| `-SpecFile` | Use your own PyInstaller `.spec`. |
| `-SafeTestArgs` | Arguments that run the application harmlessly during validation (e.g. `--version`). `none` disables the run. |
| `-WorkingDirectory` | Working directory for the embedded launcher: `app` (default) or `caller`. |
| `-BuildPython` | Explicit build interpreter instead of automatic discovery. |
| `-RuntimeZip` | Pre-downloaded official `python-X.Y.Z-embed-amd64.zip` for offline builds. |
| `-InferRequirements` | When nothing is declared, accept pip names inferred from imports (well-known mappings only). |
| `-AllowUnresolvedImports` | Continue although some imports cannot be resolved. |

**Exit codes:** `0` success, `1` build error, `2` invalid input or an ambiguous project, `3` validation failed.

---

## What the build does

1. **Static analysis** (`python/ppb_analyzer.py`). The analyzer parses every `.py` file with `ast`. It
   **never imports or executes project code**, and never runs `setup.py`. It detects:
   entry points (declared scripts, `__main__.py`, `if __name__ == "__main__"`), layout (`flat`, `src`,
   single file), local modules, relative and dynamic imports, third-party imports (and whether they are
   guarded by `try/except ImportError`), Python requirements, dependency declarations, environment
   variables, cwd-relative file access, hardcoded absolute paths, CLI frameworks, GUI/database/
   reporting/web libraries, `subprocess` commands, ports, and ODBC driver names. The report is
   saved as `<package>\analysis.json`.
2. **Entry point.** If several candidates are equally plausible, the build stops, lists them, and asks
   you to choose with `-EntryPoint`. It never guesses.
3. **Files.** The toolkit copies the project, keeping relative paths. It always excludes `.git`,
   virtual environments, caches and build/dist output. It withholds credential files and private keys,
   and **stops** if a configuration file seems to contain a secret (see [Security](#security)).
4. **Python version.** It chooses the Python version and a build interpreter of the same version and architecture.
5. **Dependencies.** The source is chosen in this order: `-Requirements` > `Pipfile.lock` >
   pinned/lock requirements files > `requirements.txt` > `pyproject.toml` (`[project]` or Poetry) >
   `setup.cfg` > `setup.py` (read with `ast`, never executed). Packages are installed with pip into an isolated target
   (embedded: `packages\` via `pip install --target`; executable: a dedicated virtual environment).
   The toolkit **does not** install whatever happens to be on the build machine. If pip fails, the build
   stops. If the project imports third-party modules but declares nothing, the build stops and suggests
   package names, because import names often differ from pip names (`yaml` -> `PyYAML`).
6. **Backend build** (details below).
7. **Native checks.** Wheel tags must match the target Python/ABI/platform. Every `.pyd`/`.dll`/`.exe`
   is scanned: architecture must match, and imported DLLs that are neither bundled nor Windows
   system DLLs are reported as external prerequisites (for example, the Visual C++ runtime or `libpq`).
8. **Documentation and manifest.** `README.md`, `DEPLOYMENT.md`, `build-manifest.json` and `SHA256SUMS` are written.
9. **Validation** ([details](#validation)), then **ZIP** + `.sha256`. No ZIP is created if validation fails.

### Embedded backend

* Downloads `python-X.Y.Z-embed-<arch>.zip` **only from `https://www.python.org/ftp/python/`** (or uses
  `-RuntimeZip`), then:
  * verifies the checksum against the python.org release API (SHA-256, or MD5 for older releases) and the file size;
  * tests archive integrity;
  * verifies the **Authenticode signature** of `python.exe` and `pythonXY.dll` (Python Software Foundation);
  * confirms the interpreter's version and architecture by starting it.
* Some releases (security-only releases) have no embeddable package. If you asked for `X.Y`, the newest
  `X.Y.Z` that has one is used. If you asked for an exact version that has none, the build stops.
* `pythonXY._pth` keeps its original entries. The toolkit adds `..\app` (or `..\app\src`), any
  additional paths and `..\packages`. `import site` stays **disabled**.
* Packages that rely on `.pth` files (for example pywin32) are detected; the launcher processes
  `packages\*.pth` explicitly with `site.addsitedir`.
* `tkinter` is not part of the embeddable package. If the application uses it, the toolkit copies it
  from the local Python of the same minor version.
* `run.cmd` / `run.ps1` resolve everything relative to their own location. They forward arguments,
  return the application's exit code, and set the working directory (`app\` by default). They also
  expose `PPB_APP_ROOT`, `PPB_CONFIG_DIR`, `PPB_LOG_DIR` and `PPB_CALLER_CWD`.
* Imports are checked with the **embedded** `python.exe`, not the build machine's interpreter.

### Executable backend

* Stages a filtered copy of the project, so the source is never touched.
* Creates `<package>\.build\venv` with the project dependencies and PyInstaller (`pyinstallerRequirement`
  in `config/defaults.json`). The environment is reused only while the Python version and requirements stay the same.
* Generates `<package>\pyinstaller\<Name>.spec` (kept for review or customisation) with:
  * resources (`--add-data` equivalent), placed relative to the import root so `__file__`-relative lookups keep working;
  * all local modules as hidden imports, plus literal `importlib.import_module` targets and `-HiddenImport`;
  * package metadata (`copy_metadata`) for the installed requirements;
  * `pathex` for `src` layouts and additional paths; console/windowed; icon.
* Module and callable entry points use a small generated bootstrap script.
* PyInstaller warnings are saved to `pyinstaller\warn-<Name>.txt`. Missing modules imported at top level
  by **your** code are reported as warnings.

### Python version selection

| Situation | Result |
|---|---|
| `-PythonVersion 3.11.9` | Embedded: exactly 3.11.9. Executable: needs a local 3.11, and the exe contains that interpreter's version. |
| `-PythonVersion 3.11` | Uses a local 3.11.x (its patch release for embedded, if an embeddable ZIP exists). |
| `.python-version` / `runtime.txt` | Used like `-PythonVersion`. |
| `requires-python` | The highest local interpreter that satisfies it. |
| Nothing declared | The default `python.exe` on PATH. |
| Embedded, no local interpreter of that minor version | **Cross-installation**: pip runs with `--python-version/--platform/--only-binary=:all:`. Only binary wheels can be used; install the matching Python to allow source builds. |

---

## Output layout

```text
D:\PortableBuilds\
├── E2Reports\                       <- package directory (marked with .ppb-owned.json)
│   ├── distribution\                <- what you deploy (also inside the ZIP, under E2Reports\)
│   ├── build-manifest.json          <- final manifest incl. ZIP checksum and validation results
│   ├── build.log                    <- complete log
│   ├── build-config.json            <- parameters for rebuild.ps1
│   ├── analysis.json                <- static analysis report
│   ├── pyinstaller\                 <- (executable) .spec, warnings, PyInstaller output log
│   └── .build\                      <- temporary: virtual environment, staging (removed by clean.ps1)
├── E2Reports-embedded.zip  (+ .sha256)
├── DBUserManager-executable-onedir.zip  (+ .sha256)
└── .ppb-cache\                      <- downloaded runtimes, shared pip environments
```

Embedded distribution:

```text
E2Reports\
├── runtime\         python.exe, python3.dll, python3XX.dll, python3XX.zip, python3XX._pth, ...
├── packages\        third-party dependencies
├── app\             your project (unchanged)
├── launcher\        ppb_launch.py, launch.json, ppb_selftest.py
├── config\  logs\
├── run.cmd  run.ps1  verify.ps1
├── README.md  DEPLOYMENT.md  build-manifest.json  SHA256SUMS
```

Executable distribution: `<Name>.exe` (+ `_internal\` for onedir), `verify.ps1`, `README.md`,
`DEPLOYMENT.md`, `build-manifest.json`, `SHA256SUMS`.

**Overwrite rules.** Each build replaces `<package>\distribution\` and its own ZIP. A package directory
or ZIP that the toolkit did not create (no ownership marker) is **never** overwritten or deleted: the
build stops instead. Deletion is guarded: it refuses drive roots, the toolkit repository, the source
project, user-profile and system folders, and anything outside a marked directory.

### build-manifest.json

It records: package name/type/mode/architecture; entry point; Python version and architecture; runtime
source URL, SHA-256, checksum verification and Authenticode signer; build interpreter; dependency
source and requirement lines (URL credentials redacted); every installed distribution with version,
license and wheel tags; build timestamp (UTC); toolkit version; source git commit and dirty flag; files,
size and checksums of the artifacts; validation results; external prerequisites; known limitations;
environment variable **names** (never values).

---

## Validation

Validation runs automatically (`-Verify`, the default), from `verify.ps1` in the toolkit, and from the
`verify.ps1` shipped in every distribution (no toolkit or Python needed on the server).

| Check | Embedded | Executable |
|---|---|---|
| Structure / required files | ✔ | ✔ |
| SHA256SUMS (application files changed → warning; anything else → failure) | ✔ | ✔ |
| Python starts, version and architecture | ✔ (bundled `python.exe`) | PE architecture and subsystem |
| Import paths inside the distribution, no external site-packages | ✔ | n/a |
| Third-party imports (each in its own process) | ✔ | Resolved at build time |
| Entry-point resolution (static: located and parsed, not executed) | ✔ | n/a |
| Resource files present | ✔ (copied as files) | ✔ (`_internal\` or the onefile archive table) |
| Launcher argument forwarding and exit codes (`run.cmd`, `run.ps1`) | ✔ (probe mode, app not started) | Bootloader (via the app run) |
| No build-machine paths in launchers/config | ✔ | ✔ |
| Runs from a different directory (temporary copy) | ✔ | ✔ |
| Application smoke run | Only with a **safe option the app already has** | Same |

**Safe application runs.** The toolkit never invents flags. It runs the application only when:

* the entry point uses `argparse` (with help enabled), `click` or `typer`, so `--help` exists; or
* you give `-SafeTestArgs` or `safeTestArgs` in `ppb.json` (for example `--version` or a documented `--dry-run`).

For that run, environment variables that look like credentials (`AWS_*`, `*PASSWORD*`, `*TOKEN*`,
`DATABASE_URL`, `PG*`, …) are removed, AWS shared config/credential files are redirected to a
non-existent location, the EC2 metadata service is disabled, `PPB_VALIDATION_RUN=1` is set, and a
timeout applies. GUI applications are never started. If no safe option exists, the report says that
**application execution was not verified**.

Note that `--help` runs any code your application executes *before* parsing arguments. If that code
connects to a database or does other work, pass `-SafeTestArgs none`.

---

## Per-project configuration (ppb.json)

Optional file in the project root (never copied into the distribution). Command-line parameters take precedence.

```json
{
    "name": "E2Reports",
    "entryPoint": "e2reports.cli:main",
    "pythonVersion": "3.11",
    "requirements": "requirements-prod.txt",
    "include": ["templates/**/*.xlsx"],
    "exclude": ["notes/*", "samples/large/*"],
    "hiddenImports": ["e2reports.plugins.sales"],
    "dataFiles": ["certs/global-bundle.pem;certs"],
    "additionalPaths": ["lib"],
    "safeTestArgs": ["--version"],
    "workingDirectory": "app",
    "windowed": false,
    "externalPrerequisites": ["Microsoft ODBC Driver 18 for SQL Server", "Read access to \\\\fileserver\\reports"]
}
```

See [examples/multi-module-app/ppb.json](examples/multi-module-app/ppb.json).

---

## Database applications

The analyzer recognises common database stacks (psycopg, psycopg2, PyMySQL, mysql-connector-python,
pyodbc, SQLAlchemy, cx_Oracle/oracledb, pymssql, boto3 …) and reports, **separately from Python
dependencies**:

* ODBC drivers named in connection strings (`DRIVER={ODBC Driver 18 for SQL Server}`); drivers are never bundled;
* native client libraries (libpq for psycopg without `[binary]`, Oracle Instant Client …) and missing DLLs found in binaries;
* TLS settings and certificate files (ship public CA bundles such as the RDS `global-bundle.pem` with
  `-DataFile`; never private keys);
* AWS credentials and IAM database authentication (`generate_db_auth_token`);
* environment variables, default ports (5432, 3306, 1433 …), port literals and DNS/network needs.

Only the dependencies your project declares are installed. The toolkit never connects to a database,
never runs SQL, and never changes database or TLS settings. Validation never needs a database: with
the default `--help` probe, the application exits before connecting (as long as it parses its
arguments first).

---

## Updating an embedded application

You can replace the `.py` files under `app\` without rebuilding, provided that:

* the requirements and their versions stay compatible,
* the required Python version does not change,
* the entry point and application structure stay valid,
* native dependencies do not change.

Afterwards run `verify.ps1`: changed application files appear as **warnings**, while changes anywhere else are failures.
Rebuild (`rebuild.ps1`) whenever requirements, the Python version, the entry point or native libraries change.

---

## Troubleshooting

| Problem | What to do |
|---|---|
| **Missing imports** (`ModuleNotFoundError` at runtime) | Check `analysis.json` → `imports.thirdParty` and `undeclaredImports`. Add the distribution to your requirements. For dynamic/plugin imports use `-HiddenImport`/`-CollectPackage` (executable); in embedded builds all local files are present anyway. |
| **"declares no dependencies"** | Create a `requirements.txt` (`pip freeze` from a *clean* project venv, not your global environment) or use `-InferRequirements` for well-known names. |
| **Missing native DLLs** (`ImportError: DLL load failed`) | See `externalPrerequisites` in the manifest: the build lists DLLs that are neither bundled nor Windows system DLLs. Install the named component (e.g. the Visual C++ 2015-2022 Redistributable) on the server. |
| **Missing ODBC drivers** (`IM002 Data source name not found`) | Install the exact driver named in `DEPLOYMENT.md`, in the same bitness as the package (64-bit for `amd64`). ODBC drivers can never be bundled. |
| **Python version mismatch** | Use `-PythonVersion`, or install the required Python on the build machine. Executables always contain the build interpreter's version. Check `requires-python`. |
| **Incorrect entry point** | The build lists candidates when ambiguous; pass `-EntryPoint`. Check `entryPoint.selection` in the manifest. |
| **Missing resource files** | Resources must be inside the project and not excluded. Check `resources` in the manifest. For executables, look files up relative to `__file__` or `sys._MEIPASS`, not the current directory. Use `-DataFile` for files outside the project. |
| **Incorrect working directory** | The embedded launcher runs in `app\` by default (`-WorkingDirectory caller` changes this; the caller's directory is in `PPB_CALLER_CWD`). Executables run in the caller's directory. Prefer paths relative to `__file__`. The analysis lists cwd-relative file access. |
| **Antivirus or application control blocks the program** | Ask for an allow rule for the installation directory or the signed `python.exe`. Code-sign PyInstaller executables. onefile is affected most (it extracts to TEMP). Prefer onedir or embedded. |
| **Restricted execution of python.exe** | The embedded package needs `runtime\python.exe` to be allowed. If that cannot be granted, use an executable build, which still has to be allowed. |
| **Unsupported destination OS** | Each Python release supports a specific range of Windows versions (for example, Python 3.9+ no longer supports Windows 7). Check the "Using Python on Windows" notes of the release and build with an older Python if needed. |
| **Dependency installation failures** | The last pip lines appear in the error; everything is in `build.log`. Typical causes: no wheel for this Python/architecture (try another Python version), a package index needing authentication (configure `pip.ini`), or no compiler for source builds (install the build tools, or use wheels). |
| **`run.ps1` cannot be loaded** | Use `run.cmd`, or `Unblock-File`, or `powershell -ExecutionPolicy Bypass -File run.ps1`. |
| **Secret detected, build stopped** | Remove the secret from the file and supply it at runtime, or exclude the file with `-Exclude`, or knowingly include it with `-Include`. |
| **Validation failed** | Read the failed checks in the console or `build-manifest.json`. No ZIP is produced; the distribution is left for inspection. |

---

## Security

* **Credentials are never packaged on purpose.** Files such as `.env`, `*.key`, `*.pfx`, `id_rsa*`,
  `.pgpass`, `credentials`, `secrets.*` and `client_secret*.json` are withheld (`.env.example` etc. are
  allowed). Configuration files (`.json`, `.yaml`, `.ini`, `.toml`, `.env`, `.pem` …) are scanned for
  private keys, AWS keys, passwords and connection strings with passwords. A hit **stops the build** until
  you exclude the file or explicitly `-Include` it. `.py` files with embedded keys produce warnings; source code is never modified.
* **Provide secrets at runtime** through environment variables, Windows Credential Manager, a secrets
  manager (AWS Secrets Manager / SSM), instance or role credentials, or a configuration file in
  `config\` protected with NTFS permissions. The launcher exposes `PPB_CONFIG_DIR`.
* **Certificates.** Ship public CA bundles if the application needs them. Never ship private keys. Keep
  TLS certificate validation enabled; the toolkit never disables it.
* **Logs and manifests** contain environment variable *names* only. URL credentials
  (`https://user:pass@…`) are redacted from logs and the manifest.
* **Runtime authenticity**: official python.org downloads only, checksum, plus Authenticode verification.
* **Validation runs** remove credential-like environment variables and never connect to production systems on purpose.
* Protect the deployed directory against modification (only administrators/deployers may write), and
  use `verify.ps1` to detect changes.

---

## Limitations

The toolkit **cannot guarantee automatically** that:

* every code path of the application works. Validation checks packaging, not business logic;
* the package runs on every Windows (Server) version or under every security policy;
* dynamic imports with computed names, plugins loaded from outside the project, or data files read via
  absolute/cwd-relative paths are found (they are reported where detectable);
* external components (ODBC drivers, database clients, COM servers, certificates, credentials,
  network/firewall rules) are present on the destination;
* the versions resolved from version ranges match a previous build. Use pinned requirements or a lock
  file for reproducibility. `poetry.lock`, `uv.lock` and `pdm.lock` are not read directly; export them
  to a requirements file;
* PyInstaller collects everything for unusual packages (use `-HiddenImport`, `-CollectPackage` or a custom `-SpecFile`);
* a successful PyInstaller run means the executable is production-ready;
* the application does nothing harmful when started with `--help` (code before argument parsing runs).

Other limitations: Windows only (the architecture separates backends, so a Linux backend can be added
later); no cross-architecture executables; no code signing; optional dependency groups (extras) of
`pyproject.toml` are not installed unless listed in a requirements file.

---

## Repository layout

```text
PythonPortableBuilder/
├── build.ps1  rebuild.ps1  verify.ps1  clean.ps1     entry points
├── modules/
│   ├── Common.psm1               logging, config, safe paths/deletion, process execution
│   ├── ProjectAnalyzer.psm1      runs the static analyzer, entry-point errors
│   ├── PythonRuntimeManager.psm1 interpreters, version selection, embeddable runtime, venvs
│   ├── DependencyManager.psm1    requirement selection, pip, inventory, native DLL checks
│   ├── ResourceManager.psm1      file selection, secret protection, copying
│   ├── EmbeddedBuilder.psm1      Option B
│   ├── ExecutableBuilder.psm1    Option A (PyInstaller)
│   ├── PackageValidator.psm1     build-side validation
│   ├── ArchiveManager.psm1       SHA256SUMS, ZIP
│   └── BuildManifest.psm1        manifest, prerequisites, deployment docs
├── python/
│   ├── ppb_analyzer.py           AST-based project analysis (never executes project code)
│   └── ppb_inspect.py            interpreter probe, inventory, PE imports, import resolution
├── templates/
│   ├── embedded/                 run.cmd, run.ps1, ppb_launch.py, ppb_selftest.py
│   ├── distribution/verify.ps1   standalone verifier shipped with every package
│   └── deployment/               README/DEPLOYMENT templates
├── config/defaults.json          defaults (override in config/local.json, git-ignored)
├── tests/                        unit + integration tests, fixtures, Run-Tests.ps1
└── examples/                     simple-script, multi-module-app
```

---

## Testing the toolkit

```powershell
.\tests\Run-Tests.ps1                 # Python + Pester unit tests (fast, offline)
.\tests\Run-Tests.ps1 -Integration    # plus real builds of all fixtures (internet, several minutes)
```

Pester **5.3+** is required. Windows ships Pester 3.4, which is incompatible:
`Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck`.
See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

**No license has been chosen yet.** The repository owner still has to make that decision. Until a
license is added, no rights are granted to others. See [LICENSE](LICENSE).

Third-party components used *at build time* and redistributed *inside generated packages* have their own licenses:

* CPython: Python Software Foundation License (the embeddable package includes its `LICENSE.txt`);
* PyInstaller: GPL 2.0 with a bootloader exception that allows distributing executables under any license;
* your project's dependencies: listed with their declared licenses in each `build-manifest.json`.
  Review them before distributing packages outside your organisation.
