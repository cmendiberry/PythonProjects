# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic versioning.

## [Unreleased]

## [0.1.0] - 2026-11-20

### Added
- `build.ps1`: packages a Python script or project as an **embedded** distribution (official CPython
  embeddable runtime) or a PyInstaller **executable** (`onedir`/`onefile`).
- Static project analysis (AST only, never executes project code): entry points, `flat`/`src`/single-file
  layouts, dependency declarations (requirements files, Pipfile.lock, pyproject `[project]` and Poetry,
  setup.cfg, setup.py), imports (guarded/optional detection), dynamic imports, environment variables,
  cwd-relative and hardcoded paths, CLI/GUI/database/reporting detection, external prerequisites.
- Ambiguous entry points stop the build and list the candidates.
- Runtime download from python.org only, with release-API checksum, archive integrity and Authenticode
  verification; runtime cache.
- Isolated dependency installation (pip `--target` for embedded, dedicated venv for executables),
  cross-installation when no matching local Python exists, wheel-tag and PE architecture checks,
  detection of DLLs that are neither bundled nor Windows system DLLs.
- `.pth` processing for embedded packages that need it; tkinter support for embedded packages.
- Launchers `run.cmd`/`run.ps1` with relative paths, argument forwarding and exit-code propagation.
- Secret protection: credential files withheld, configuration files with secrets block the build.
- Validation: standalone `verify.ps1` in every distribution (checksums, self-test with the bundled
  interpreter, launcher probe, resources, safe application run with scrubbed credentials), run from a
  temporary copy at build time; build-path leak scan.
- `build-manifest.json`, `SHA256SUMS`, ZIP + `.sha256`, generated `README.md`/`DEPLOYMENT.md`.
- `rebuild.ps1`, `verify.ps1`, `clean.ps1` with ownership markers and guarded deletion.
- Unit tests (Python unittest, Pester 5) and integration tests covering both backends.
