# Examples

Harmless sample projects to try the toolkit. They do not access networks, databases or files outside themselves.

| Example | Shows |
|---|---|
| [simple-script](simple-script/hello.py) | Single-file argparse script, argument forwarding, exit codes (`--exit-code 3`). |
| [multi-module-app](multi-module-app/) | Package with relative imports, `__main__.py`, a console script declared in `pyproject.toml`, CSV/JSON resources located via `__file__`, an environment variable (`REPORT_TITLE`), and a `ppb.json` with `safeTestArgs`. |

```powershell
# from the repository root
.\build.ps1 -Source .\examples\simple-script\hello.py -Type embedded
.\build.ps1 -Source .\examples\simple-script\hello.py -Name Hello -Type executable -Mode onefile
.\build.ps1 -Source .\examples\multi-module-app -Type embedded
.\build.ps1 -Source .\examples\multi-module-app -Name InventoryExe -Type executable -Mode onedir

# run them (default output root: ..\PortableBuilds next to the repository)
..\PortableBuilds\hello\distribution\run.cmd --name Team --exit-code 3; $LASTEXITCODE
..\PortableBuilds\InventoryReport\distribution\run.cmd --min-quantity 1
```
