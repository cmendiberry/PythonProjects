"""Unit tests for python/ppb_analyzer.py and python/ppb_inspect.py (standard library unittest).

Run:  python -m unittest discover -s tests/unit -p "test_*.py"
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python"))

import ppb_analyzer  # noqa: E402
import ppb_inspect  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures")
EXCLUDES = [".git", ".venv", "venv", "__pycache__", "build", "dist"]


def analyze(source, entry=None):
    return ppb_analyzer.Analyzer(source, EXCLUDES, ["*.egg-info"], entry).run()


class TempProject(object):
    def __init__(self, files):
        self.files = files

    def __enter__(self):
        self.root = tempfile.mkdtemp(prefix="ppb-ut-")
        for rel, content in self.files.items():
            path = os.path.join(self.root, *rel.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(textwrap.dedent(content))
        return self.root

    def __exit__(self, *exc):
        shutil.rmtree(self.root, ignore_errors=True)


class EntryPointTests(unittest.TestCase):
    def test_single_file(self):
        r = analyze(os.path.join(FIXTURES, "single-file", "echo_args.py"))
        self.assertEqual(r["errors"], [])
        self.assertEqual(r["entryPoint"]["kind"], "script")
        self.assertEqual(r["entryPoint"]["path"], "echo_args.py")
        self.assertEqual(r["safeTestArgs"], ["--help"])

    def test_package_main(self):
        r = analyze(os.path.join(FIXTURES, "multi-module"))
        self.assertEqual(r["errors"], [])
        self.assertEqual(r["entryPoint"]["kind"], "module")
        self.assertEqual(r["entryPoint"]["module"], "calc")
        self.assertGreaterEqual(r["imports"]["relativeImportCount"], 2)

    def test_src_layout_declared_script(self):
        r = analyze(os.path.join(FIXTURES, "src-layout"))
        self.assertEqual(r["errors"], [])
        self.assertEqual(r["layout"], "src")
        self.assertEqual(r["importRoots"], ["src"])
        self.assertEqual(r["entryPoint"]["kind"], "callable")
        self.assertEqual(r["entryPoint"]["module"], "srcapp.main")
        self.assertEqual(r["entryPoint"]["function"], "cli")

    def test_ambiguous_requires_selection(self):
        r = analyze(os.path.join(FIXTURES, "ambiguous"))
        codes = [e["code"] for e in r["errors"]]
        self.assertIn("ambiguous-entry-point", codes)
        cands = [c["value"] for e in r["errors"] for c in e.get("candidates", [])]
        self.assertEqual(sorted(cands), ["first.py", "second.py"])

    def test_explicit_entry_point(self):
        r = analyze(os.path.join(FIXTURES, "ambiguous"), entry="second.py")
        self.assertEqual(r["errors"], [])
        self.assertEqual(r["entryPoint"]["path"], "second.py")

    def test_invalid_explicit_entry_point(self):
        r = analyze(os.path.join(FIXTURES, "ambiguous"), entry="missing.py")
        self.assertIn("invalid-entry-point", [e["code"] for e in r["errors"]])

    def test_entry_outside_project_rejected(self):
        r = analyze(os.path.join(FIXTURES, "ambiguous"), entry="../single-file/echo_args.py")
        self.assertIn("entry-outside-project", [e["code"] for e in r["errors"]])

    def test_no_entry_point(self):
        with TempProject({"lib/__init__.py": "", "lib/util.py": "X = 1\n"}) as root:
            r = analyze(root)
            self.assertIn("no-entry-point", [e["code"] for e in r["errors"]])

    def test_tests_directory_ignored_for_entry_detection(self):
        with TempProject({"main.py": "if __name__ == '__main__':\n    pass\n",
                          "tests/test_x.py": "if __name__ == '__main__':\n    pass\n"}) as root:
            r = analyze(root)
            self.assertEqual(r["errors"], [])
            self.assertEqual(r["entryPoint"]["path"], "main.py")


class MetadataTests(unittest.TestCase):
    def test_invalid_pyproject(self):
        r = analyze(os.path.join(FIXTURES, "invalid-metadata"))
        self.assertIn("invalid-pyproject", [e["code"] for e in r["errors"]])

    def test_requirements_and_third_party(self):
        r = analyze(os.path.join(FIXTURES, "resources-yaml"))
        self.assertEqual(r["errors"], [])
        kinds = [s["kind"] for s in r["dependencySources"]]
        self.assertIn("requirements", kinds)
        names = [t["name"] for t in r["imports"]["thirdParty"]]
        self.assertEqual(names, ["yaml"])
        self.assertEqual(r["undeclaredImports"], [])
        self.assertEqual(r["imports"]["thirdParty"][0]["suggestedDistribution"], "PyYAML")

    def test_undeclared_import(self):
        r = analyze(os.path.join(FIXTURES, "undeclared-import"))
        self.assertEqual(r["undeclaredImports"], ["yaml"])
        self.assertEqual(r["dependencySources"], [])

    def test_guarded_import_is_optional(self):
        with TempProject({"app.py": """
            try:
                import ujson as json
            except ImportError:
                import json
            if __name__ == '__main__':
                print(json.dumps({}))
            """}) as root:
            r = analyze(root)
            tp = {t["name"]: t for t in r["imports"]["thirdParty"]}
            self.assertTrue(tp["ujson"]["optional"])

    def test_setup_py_not_executed(self):
        with TempProject({"setup.py": """
            import sys
            raise SystemExit('setup.py must never be executed by the analyzer')
            from setuptools import setup
            setup(name='demo', install_requires=['requests>=2'], python_requires='>=3.9',
                  entry_points={'console_scripts': ['demo=demo.cli:main']})
            """, "demo/__init__.py": "", "demo/cli.py": "def main():\n    return 0\n"}) as root:
            r = analyze(root)
            self.assertEqual(r["projectName"], "demo")
            self.assertEqual(r["pythonRequirement"]["specifier"], ">=3.9")
            self.assertEqual(r["entryPoint"]["module"], "demo.cli")

    def test_poetry_constraints(self):
        c = ppb_analyzer.convert_poetry_constraint
        self.assertEqual(c("^1.2.3"), ">=1.2.3,<2.0")
        self.assertEqual(c("^0.4"), ">=0.4,<0.5")
        self.assertEqual(c("~1.4"), ">=1.4,<1.5")
        self.assertEqual(c("2.0"), "==2.0")
        self.assertEqual(c("*"), "")

    def test_pipfile_lock_preferred_and_locked(self):
        lock = {"default": {"requests": {"version": "==2.31.0"}}, "develop": {"pytest": {"version": "==8.0.0"}}}
        with TempProject({"app.py": "import requests\nif __name__ == '__main__':\n    pass\n",
                          "Pipfile.lock": json.dumps(lock)}) as root:
            r = analyze(root)
            src = [s for s in r["dependencySources"] if s["kind"] == "pipfile-lock"][0]
            self.assertEqual(src["requirements"], ["requests==2.31.0"])
            self.assertTrue(src["locked"])

    def test_mini_toml_parser(self):
        doc = ppb_analyzer.MiniToml(textwrap.dedent('''
            # comment
            [project]
            name = "x"  # trailing
            dependencies = [
                "a>=1",  # c
                'b',
            ]
            [project.scripts]
            tool = "x.cli:main"
            [tool.setuptools.packages.find]
            where = ["src"]
            [[tool.other]]
            k = 1
            ''')).parse()
        self.assertEqual(doc["project"]["dependencies"], ["a>=1", "b"])
        self.assertEqual(doc["project"]["scripts"]["tool"], "x.cli:main")
        self.assertEqual(doc["tool"]["setuptools"]["packages"]["find"]["where"], ["src"])
        self.assertEqual(doc["tool"]["other"], [{"k": 1}])
        with self.assertRaises(ppb_analyzer.TomlError):
            ppb_analyzer.MiniToml("[project\nname = 'x'\n").parse()


class FindingsTests(unittest.TestCase):
    def test_database_prerequisites_and_env(self):
        with TempProject({"db.py": """
            import os, pyodbc, boto3
            CONN = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=example.invalid"
            def connect():
                token = boto3.client('rds').generate_db_auth_token('h', 5432, 'u')
                return pyodbc.connect(CONN, password=os.environ['DB_PASSWORD'], port=1433)
            if __name__ == '__main__':
                connect()
            """}) as root:
            r = analyze(root)
            names = {(p["category"], p["name"]) for p in r["externalPrerequisites"]}
            self.assertIn(("odbc-driver", "ODBC Driver 18 for SQL Server"), names)
            self.assertIn(("credentials", "AWS credentials"), names)
            self.assertIn(("credentials", "IAM database authentication"), names)
            self.assertIn(("environment-variable", "DB_PASSWORD"), names)
            self.assertIn(("network", "TCP 1433"), names)
            self.assertIn("database-tool", r["applicationTypes"])
            # Values are never captured, only names.
            self.assertNotIn("example.invalid", json.dumps(r["environmentVariables"]))

    def test_cwd_and_hardcoded_paths(self):
        with TempProject({"app.py": r"""
            data = open('data/input.csv').read()
            LOG = 'C:\\Logs\\app.log'
            if __name__ == '__main__':
                pass
            """}) as root:
            r = analyze(root)
            self.assertEqual([c["path"] for c in r["workingDirectoryAssumptions"]], ["data/input.csv"])
            self.assertEqual(len(r["hardcodedAbsolutePaths"]), 1)

    def test_gui_app_gets_no_safe_probe(self):
        with TempProject({"gui.py": "import tkinter\nif __name__ == '__main__':\n    tkinter.Tk().mainloop()\n"}) as root:
            r = analyze(root)
            self.assertIn("gui", r["applicationTypes"])
            self.assertEqual(r["safeTestArgs"], [])

    def test_argparse_without_help_gets_no_probe(self):
        with TempProject({"t.py": "import argparse\nif __name__ == '__main__':\n    argparse.ArgumentParser(add_help=False).parse_args()\n"}) as root:
            self.assertEqual(analyze(root)["safeTestArgs"], [])


class InspectTests(unittest.TestCase):
    def test_pe_info_of_python_exe(self):
        machine, subsystem, imports = ppb_inspect.pe_info(sys.executable)
        self.assertIn(machine, ("amd64", "win32", "arm64"))
        self.assertEqual(subsystem, 3)  # console
        self.assertTrue(any(i.lower().startswith("python3") for i in imports))

    def test_wheel_tag_compatibility(self):
        ok, _ = ppb_inspect._tags_compatible(["cp310-cp310-win_amd64"], "cp310", "win_amd64")
        self.assertTrue(ok)
        ok, _ = ppb_inspect._tags_compatible(["cp311-cp311-win_amd64"], "cp310", "win_amd64")
        self.assertFalse(ok)
        ok, _ = ppb_inspect._tags_compatible(["cp38-abi3-win_amd64"], "cp310", "win_amd64")
        self.assertTrue(ok)
        ok, _ = ppb_inspect._tags_compatible(["py3-none-any"], "cp310", "win_amd64")
        self.assertTrue(ok)
        ok, _ = ppb_inspect._tags_compatible(["cp310-cp310-win32"], "cp310", "win_amd64")
        self.assertFalse(ok)

    def test_analyzer_cli_writes_report(self):
        out = tempfile.mktemp(suffix=".json")
        try:
            subprocess.check_call([sys.executable, "-I", os.path.join(ROOT, "python", "ppb_analyzer.py"),
                                   "--source", os.path.join(FIXTURES, "single-file", "echo_args.py"), "--output", out])
            with open(out, encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["entryPoint"]["path"], "echo_args.py")
        finally:
            if os.path.exists(out):
                os.remove(out)


if __name__ == "__main__":
    unittest.main()
