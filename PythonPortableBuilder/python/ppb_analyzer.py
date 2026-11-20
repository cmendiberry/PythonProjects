#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PythonPortableBuilder - static project analyzer.

Inspects a Python script or project and writes a JSON report describing entry
points, modules, dependency declarations, imports, resources, environment
variables, external prerequisites and portability risks.

SAFETY: this analyzer never imports, executes or installs project code.
setup.py is parsed with ``ast`` only; it is never run.

Compatible with Python 3.8+. Uses only the standard library.
"""

import argparse
import ast
import configparser
import fnmatch
import json
import os
import re
import sys

ANALYZER_VERSION = "1"

# --------------------------------------------------------------------------------------
# Knowledge base
# --------------------------------------------------------------------------------------

# Import name -> distribution name, for imports whose names differ from the pip name.
# Used ONLY to suggest requirements; never to install silently.
KNOWN_IMPORT_TO_DIST = {
    "yaml": "PyYAML", "PIL": "Pillow", "cv2": "opencv-python", "sklearn": "scikit-learn",
    "skimage": "scikit-image", "bs4": "beautifulsoup4", "dateutil": "python-dateutil",
    "dotenv": "python-dotenv", "jwt": "PyJWT", "MySQLdb": "mysqlclient", "mysql": "mysql-connector-python",
    "win32api": "pywin32", "win32con": "pywin32", "win32com": "pywin32", "win32gui": "pywin32",
    "pythoncom": "pywin32", "pywintypes": "pywin32", "win32service": "pywin32", "win32serviceutil": "pywin32",
    "servicemanager": "pywin32", "win32crypt": "pywin32", "win32file": "pywin32", "win32event": "pywin32",
    "Crypto": "pycryptodome", "Cryptodome": "pycryptodomex", "OpenSSL": "pyOpenSSL", "magic": "python-magic",
    "docx": "python-docx", "pptx": "python-pptx", "ldap": "python-ldap", "serial": "pyserial",
    "usb": "pyusb", "attr": "attrs", "google.protobuf": "protobuf", "fitz": "PyMuPDF",
    "psycopg2": "psycopg2-binary", "pymysql": "PyMySQL", "pyodbc": "pyodbc", "sqlalchemy": "SQLAlchemy",
    "psycopg": "psycopg[binary]", "boto3": "boto3", "botocore": "botocore", "pkg_resources": "setuptools",
    "setuptools": "setuptools", "jinja2": "Jinja2", "markupsafe": "MarkupSafe", "Levenshtein": "python-Levenshtein",
    "telegram": "python-telegram-bot", "slugify": "python-slugify", "zmq": "pyzmq", "nacl": "PyNaCl",
    "git": "GitPython", "ruamel": "ruamel.yaml", "lxml": "lxml", "xlrd": "xlrd", "openpyxl": "openpyxl",
    "xlsxwriter": "XlsxWriter", "reportlab": "reportlab", "fpdf": "fpdf2", "pandas": "pandas", "numpy": "numpy",
    "requests": "requests", "click": "click", "typer": "typer", "tabulate": "tabulate", "colorama": "colorama",
    "cx_Oracle": "cx_Oracle", "oracledb": "oracledb", "pymssql": "pymssql", "redis": "redis",
    "pymongo": "pymongo", "bson": "pymongo", "kafka": "kafka-python", "paramiko": "paramiko",
    "wx": "wxPython", "PyQt5": "PyQt5", "PyQt6": "PyQt6", "PySide2": "PySide2", "PySide6": "PySide6",
    "google.cloud": "google-cloud-*", "azure": "azure-*",
}

GUI_FRAMEWORKS = {"tkinter", "PyQt5", "PyQt6", "PySide2", "PySide6", "wx", "kivy", "pygame", "customtkinter",
                  "PySimpleGUI", "dearpygui", "flet", "toga", "pyglet", "arcade"}
WEB_FRAMEWORKS = {"flask", "django", "fastapi", "uvicorn", "starlette", "bottle", "tornado", "aiohttp",
                  "cherrypy", "waitress", "gunicorn", "streamlit", "dash", "sanic", "falcon"}
REPORTING_LIBS = {"openpyxl", "xlsxwriter", "xlrd", "xlwt", "reportlab", "fpdf", "docx", "pptx", "jinja2",
                  "pandas", "matplotlib", "plotly", "tabulate", "weasyprint", "pdfkit", "pypdf", "PyPDF2"}
DB_LIBS = {"psycopg", "psycopg2", "pymysql", "mysql", "MySQLdb", "pyodbc", "sqlalchemy", "cx_Oracle",
           "oracledb", "pymssql", "sqlite3", "pymongo", "redis", "asyncpg", "aiomysql", "databases",
           "peewee", "pony", "teradatasql", "snowflake", "ibm_db", "duckdb", "boto3"}
CLI_FRAMEWORKS = {"argparse", "click", "typer", "fire", "docopt", "optparse", "getopt", "cleo", "plac"}
SERVICE_LIBS = {"win32serviceutil", "servicemanager", "win32service"}

NETWORK_LIBS = {"requests", "urllib3", "httpx", "aiohttp", "socket", "http", "urllib", "ftplib", "smtplib",
                "paramiko", "boto3", "botocore", "pika", "kafka", "grpc", "websockets", "websocket", "ldap3",
                "imaplib", "poplib", "xmlrpc", "telnetlib", "ssl"}

DEFAULT_PORTS = {"psycopg": 5432, "psycopg2": 5432, "asyncpg": 5432, "pymysql": 3306, "mysql": 3306,
                 "MySQLdb": 3306, "aiomysql": 3306, "pyodbc": 1433, "pymssql": 1433, "cx_Oracle": 1521,
                 "oracledb": 1521, "pymongo": 27017, "redis": 6379}

TEST_DIR_NAMES = {"tests", "test", "testing", "docs", "doc", "benchmarks", "bench"}
NON_ENTRY_FILES = {"setup.py", "conftest.py", "noxfile.py", "tasks.py", "fabfile.py", "dodo.py", "manage_tests.py"}

TEXT_RESOURCE_EXT = {".sql", ".yaml", ".yml", ".json", ".ini", ".toml", ".csv", ".html", ".htm", ".jinja",
                     ".jinja2", ".j2", ".txt", ".cfg", ".conf", ".xml", ".md", ".tpl", ".tmpl", ".css", ".js",
                     ".properties", ".env"}
CONFIG_EXT = {".ini", ".cfg", ".conf", ".yaml", ".yml", ".json", ".toml", ".properties", ".env", ".xml"}
CERT_EXT = {".pem", ".crt", ".cer", ".der", ".p7b"}
NATIVE_EXT = {".pyd", ".dll", ".so", ".dylib", ".exe"}

ABS_PATH_RE = re.compile(r"^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/])")
ODBC_DRIVER_RE = re.compile(r"(ODBC Driver \d+ for SQL Server|SQL Server Native Client [\d.]+|SQL Server|"
                            r"PostgreSQL (?:Unicode|ANSI)(?:\(x64\))?|MySQL ODBC [\d.]+ \w+ Driver|"
                            r"Oracle in \w+|Amazon Redshift \(x64\)|Snowflake(?:DSIIDriver)?)", re.I)
DRIVER_KV_RE = re.compile(r"DRIVER\s*=\s*\{([^}]+)\}", re.I)
FILE_LIKE_RE = re.compile(r"^[^\s<>|*?\"]+\.[A-Za-z0-9]{1,8}$|^[^\s<>|*?\"]+[\\/][^\s<>|*?\"]*$")

PATH_CALLS = {"open", "Path", "PurePath", "WindowsPath", "exists", "isfile", "isdir", "read_csv", "read_excel",
              "read_json", "load_workbook", "ExcelFile", "FileHandler", "listdir", "scandir", "fileConfig",
              "copyfile", "chdir", "getsize", "TimedRotatingFileHandler", "RotatingFileHandler",
              "FileSystemLoader", "imread"}


def is_relative_file_literal(s):
    """True for literals that look like a relative file/dir path (resolved against the CWD)."""
    if not FILE_LIKE_RE.match(s) or ABS_PATH_RE.match(s):
        return False
    if re.match(r"^[a-z][a-z0-9+.\-]*://", s, re.I) or s.startswith(("%", "{", "$", "~")):
        return False
    if re.match(r"^[A-Za-z_]\w*(\.[A-Za-z_]\w*){2,}$", s):  # dotted identifier, e.g. a.b.c
        return False
    return True


# --------------------------------------------------------------------------------------
# Minimal TOML support (tomllib on 3.11+, tomli if present, else a subset parser)
# --------------------------------------------------------------------------------------

def load_toml(path):
    with open(path, "rb") as fh:
        data = fh.read()
    try:
        import tomllib  # type: ignore
        return tomllib.loads(data.decode("utf-8"))
    except ImportError:
        pass
    try:
        import tomli  # type: ignore
        return tomli.loads(data.decode("utf-8"))
    except ImportError:
        pass
    return MiniToml(data.decode("utf-8")).parse()


class TomlError(ValueError):
    pass


class MiniToml(object):
    """Subset TOML parser sufficient for pyproject.toml metadata.

    Supports tables, dotted table headers, arrays of tables, basic/literal/multi-line
    strings, arrays (multi-line), inline tables, booleans, integers, floats.
    Raises TomlError on syntax it does not understand.
    """

    def __init__(self, text):
        self.text = text
        self.i = 0
        self.n = len(text)

    def parse(self):
        root = {}
        current = root
        while True:
            self._skip_ws_comments_newlines()
            if self.i >= self.n:
                break
            if self.text.startswith("[[", self.i):
                self.i += 2
                keys = self._parse_key_path("]]")
                self.i += 2
                parent = self._descend(root, keys[:-1])
                arr = parent.setdefault(keys[-1], [])
                if not isinstance(arr, list):
                    raise TomlError("array of tables conflicts with key %s" % keys[-1])
                current = {}
                arr.append(current)
            elif self.text[self.i] == "[":
                self.i += 1
                keys = self._parse_key_path("]")
                self.i += 1
                current = self._descend(root, keys)
            else:
                keys = self._parse_key_path("=")
                self.i += 1
                self._skip_inline_ws()
                value = self._parse_value()
                target = self._descend(current, keys[:-1])
                target[keys[-1]] = value
            self._expect_line_end()
        return root

    def _descend(self, table, keys):
        for k in keys:
            nxt = table.setdefault(k, {})
            if isinstance(nxt, list):
                nxt = nxt[-1]
            if not isinstance(nxt, dict):
                raise TomlError("key %s is not a table" % k)
            table = nxt
        return table

    def _skip_inline_ws(self):
        while self.i < self.n and self.text[self.i] in " \t":
            self.i += 1

    def _skip_ws_comments_newlines(self):
        while self.i < self.n:
            c = self.text[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif c == "#":
                while self.i < self.n and self.text[self.i] != "\n":
                    self.i += 1
            else:
                break

    def _expect_line_end(self):
        self._skip_inline_ws()
        if self.i < self.n and self.text[self.i] == "#":
            while self.i < self.n and self.text[self.i] != "\n":
                self.i += 1
        if self.i < self.n and self.text[self.i] not in "\r\n":
            raise TomlError("unexpected content at offset %d" % self.i)

    def _parse_key_path(self, terminator):
        keys = []
        while True:
            self._skip_inline_ws()
            c = self.text[self.i] if self.i < self.n else ""
            if c in "\"'":
                keys.append(self._parse_string())
            else:
                start = self.i
                while self.i < self.n and (self.text[self.i].isalnum() or self.text[self.i] in "_-"):
                    self.i += 1
                if start == self.i:
                    raise TomlError("invalid key at offset %d" % start)
                keys.append(self.text[start:self.i])
            self._skip_inline_ws()
            if self.text.startswith(terminator, self.i):
                return keys
            if self.i < self.n and self.text[self.i] == ".":
                self.i += 1
                continue
            raise TomlError("invalid key path at offset %d" % self.i)

    def _parse_value(self):
        c = self.text[self.i] if self.i < self.n else ""
        if c in "\"'":
            return self._parse_string()
        if c == "[":
            return self._parse_array()
        if c == "{":
            return self._parse_inline_table()
        m = re.compile(r"true|false|[+-]?(?:inf|nan)|[0-9+\-._:TZeExobabcdefABCDEF]+").match(self.text, self.i)
        if not m:
            raise TomlError("invalid value at offset %d" % self.i)
        tok = m.group(0)
        self.i = m.end()
        if tok == "true":
            return True
        if tok == "false":
            return False
        try:
            return int(tok.replace("_", ""), 0)
        except ValueError:
            try:
                return float(tok.replace("_", ""))
            except ValueError:
                return tok  # dates and times are returned as strings

    def _parse_string(self):
        t = self.text
        if t.startswith('"""', self.i) or t.startswith("'''", self.i):
            q = t[self.i:self.i + 3]
            end = t.find(q, self.i + 3)
            if end < 0:
                raise TomlError("unterminated multi-line string")
            raw = t[self.i + 3:end]
            self.i = end + 3
            if raw.startswith("\r\n"):
                raw = raw[2:]
            elif raw.startswith("\n"):
                raw = raw[1:]
            return self._unescape(raw) if q == '"""' else raw
        q = t[self.i]
        self.i += 1
        out = []
        while self.i < self.n:
            c = t[self.i]
            if c == q:
                self.i += 1
                s = "".join(out)
                return self._unescape(s) if q == '"' else s
            if c == "\\" and q == '"':
                out.append(t[self.i:self.i + 2])
                self.i += 2
                continue
            if c == "\n":
                raise TomlError("newline in string")
            out.append(c)
            self.i += 1
        raise TomlError("unterminated string")

    @staticmethod
    def _unescape(s):
        try:
            return json.loads('"' + s.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + '"')
        except ValueError:
            return s

    def _parse_array(self):
        self.i += 1
        items = []
        while True:
            self._skip_ws_comments_newlines()
            if self.i >= self.n:
                raise TomlError("unterminated array")
            if self.text[self.i] == "]":
                self.i += 1
                return items
            items.append(self._parse_value())
            self._skip_ws_comments_newlines()
            if self.i < self.n and self.text[self.i] == ",":
                self.i += 1

    def _parse_inline_table(self):
        self.i += 1
        table = {}
        while True:
            self._skip_inline_ws()
            if self.i < self.n and self.text[self.i] == "}":
                self.i += 1
                return table
            keys = self._parse_key_path("=")
            self.i += 1
            self._skip_inline_ws()
            value = self._parse_value()
            self._descend(table, keys[:-1])[keys[-1]] = value
            self._skip_inline_ws()
            if self.i < self.n and self.text[self.i] == ",":
                self.i += 1


# --------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------

def stdlib_names():
    names = set(getattr(sys, "stdlib_module_names", ()))
    names.update(sys.builtin_module_names)
    if not getattr(sys, "stdlib_module_names", None):
        # Python < 3.10: approximate by inspecting the standard library directory.
        import sysconfig
        stdlib = sysconfig.get_paths().get("stdlib")
        if stdlib and os.path.isdir(stdlib):
            for entry in os.listdir(stdlib):
                base, ext = os.path.splitext(entry)
                if ext == ".py" or (os.path.isdir(os.path.join(stdlib, entry)) and entry != "site-packages"):
                    names.add(base if ext == ".py" else entry)
        dlls = os.path.join(sys.base_prefix, "DLLs")
        if os.path.isdir(dlls):
            for entry in os.listdir(dlls):
                if entry.endswith(".pyd"):
                    names.add(entry.split(".")[0])
    names.update({"__future__", "_thread", "msvcrt", "winreg", "winsound", "_winapi", "nt", "posix", "pwd",
                  "grp", "fcntl", "termios", "resource", "readline", "curses", "tty", "pty", "crypt", "spwd",
                  "syslog", "nis", "ossaudiodev", "distutils", "imp", "asynchat", "asyncore", "smtpd"})
    return names


def norm_dist(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def req_name(line):
    m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._\-]*)", line)
    return norm_dist(m.group(1)) if m else None


def rel(path, root):
    return os.path.relpath(path, root).replace("\\", "/")


def dotted_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = dotted_name(node.value)
        return base + "." + node.attr if base else node.attr
    return None


def literal_str(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if sys.version_info < (3, 8) and isinstance(node, ast.Str):  # pragma: no cover
        return node.s
    return None


def convert_poetry_constraint(spec):
    """Converts a Poetry version constraint to PEP 440 (best effort)."""
    if not isinstance(spec, str):
        return None
    spec = spec.strip()
    if spec in ("*", ""):
        return ""
    parts = []
    for clause in [c.strip() for c in spec.split(",") if c.strip()]:
        m = re.match(r"^\^\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?", clause)
        if m:
            major, minor, patch = int(m.group(1)), m.group(2), m.group(3)
            lower = clause[1:].strip()
            if major > 0:
                upper = "%d.0" % (major + 1)
            elif minor is not None and int(minor) > 0:
                upper = "0.%d" % (int(minor) + 1)
            else:
                upper = "0.0.%d" % ((int(patch) if patch else 0) + 1)
            parts += [">=" + lower, "<" + upper]
            continue
        m = re.match(r"^~\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?$", clause)
        if m:
            major, minor = int(m.group(1)), m.group(2)
            lower = clause[1:].strip()
            upper = "%d.%d" % (major, int(minor) + 1) if minor is not None else "%d.0" % (major + 1)
            parts += [">=" + lower, "<" + upper]
            continue
        if re.match(r"^\d", clause):
            parts.append("==" + clause)
        else:
            parts.append(clause)
    return ",".join(parts)


def read_text(path, limit=None):
    with open(path, "rb") as fh:
        data = fh.read(limit) if limit else fh.read()
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", "replace")


# --------------------------------------------------------------------------------------
# AST visitor
# --------------------------------------------------------------------------------------

class FileVisitor(ast.NodeVisitor):
    def __init__(self, relpath):
        self.relpath = relpath
        self.imports = []          # (name, line, context)
        self.relative_imports = []
        self.dynamic_imports = []
        self.env_vars = []
        self.cwd_paths = []
        self.abs_paths = []
        self.strings = []
        self.cli = set()
        self.cli_options = set()
        self.argparse_add_help = True
        self.uses_sys_argv = False
        self.has_main_guard = False
        self.subprocess_cmds = []
        self.ports = []
        self.defined_functions = set()
        self.calls = set()
        self.uses_file_dunder = False
        self.uses_getcwd = False
        self.chdir = False
        self._ctx = []

    # context tracking --------------------------------------------------------------
    def _context(self):
        ctx = set(self._ctx)
        if not ctx:
            return "top-level"
        for c in ("type-checking", "guarded", "conditional", "deferred"):
            if c in ctx:
                return c
        return "top-level"

    def visit_Try(self, node):
        catches_import = False
        for h in node.handlers:
            names = []
            if h.type is None:
                catches_import = True
            elif isinstance(h.type, ast.Tuple):
                names = [dotted_name(e) for e in h.type.elts]
            else:
                names = [dotted_name(h.type)]
            if any(n in ("ImportError", "ModuleNotFoundError", "Exception", "BaseException") for n in names if n):
                catches_import = True
        if catches_import:
            self._ctx.append("guarded")
        for stmt in node.body:
            self.visit(stmt)
        if catches_import:
            self._ctx.pop()
        for part in (node.handlers, node.orelse, node.finalbody):
            for stmt in part:
                self.visit(stmt)

    visit_TryStar = visit_Try

    def visit_If(self, node):
        test_src = dotted_name(node.test) or ""
        is_tc = test_src.endswith("TYPE_CHECKING")
        if (isinstance(node.test, ast.Compare) and isinstance(node.test.left, ast.Name)
                and node.test.left.id == "__name__"):
            for comp in node.test.comparators:
                if literal_str(comp) == "__main__" and not self._ctx:
                    self.has_main_guard = True
        self._ctx.append("type-checking" if is_tc else "conditional")
        for stmt in node.body:
            self.visit(stmt)
        for stmt in node.orelse:
            self.visit(stmt)
        self._ctx.pop()
        self.visit(node.test)

    def _visit_function(self, node):
        if not self._ctx:
            self.defined_functions.add(node.name)
        for d in node.decorator_list:
            dn = dotted_name(d.func if isinstance(d, ast.Call) else d) or ""
            if dn.startswith("click.") or dn in ("command", "group"):
                self.cli.add("click")
            if dn.endswith(".command") or dn.endswith(".callback"):
                self.calls.add(dn)
            self.visit(d)
        self._ctx.append("deferred")
        for stmt in node.body:
            self.visit(stmt)
        self._ctx.pop()

    visit_FunctionDef = _visit_function
    visit_AsyncFunctionDef = _visit_function

    def visit_ClassDef(self, node):
        if not self._ctx:
            self.defined_functions.add(node.name)
        self.generic_visit(node)

    # imports -----------------------------------------------------------------------
    def visit_Import(self, node):
        for alias in node.names:
            self.imports.append((alias.name, node.lineno, self._context()))

    def visit_ImportFrom(self, node):
        if node.level and node.level > 0:
            self.relative_imports.append({"line": node.lineno, "level": node.level, "module": node.module or ""})
            return
        if node.module:
            self.imports.append((node.module, node.lineno, self._context()))
            for alias in node.names:
                if alias.name != "*":
                    self.imports.append((node.module + "." + alias.name, node.lineno, "submodule-candidate"))

    # expressions -------------------------------------------------------------------
    def visit_Name(self, node):
        if node.id == "__file__":
            self.uses_file_dunder = True

    def visit_Attribute(self, node):
        dn = dotted_name(node)
        if dn == "sys.argv":
            self.uses_sys_argv = True
        self.generic_visit(node)

    def visit_Subscript(self, node):
        dn = dotted_name(node.value)
        if dn in ("os.environ", "environ"):
            key = node.slice
            if hasattr(ast, "Index") and isinstance(key, getattr(ast, "Index")):  # Python 3.8
                key = key.value  # type: ignore
            name = literal_str(key)
            if name:
                self.env_vars.append((name, node.lineno, "required"))
        self.generic_visit(node)

    def visit_Constant(self, node):
        if isinstance(node.value, str) and 2 < len(node.value) < 500:
            self.strings.append((node.value, getattr(node, "lineno", 0)))

    def visit_Call(self, node):
        fn = dotted_name(node.func) or ""
        short = fn.split(".")[-1]
        self.calls.add(fn)
        first = node.args[0] if node.args else None
        first_lit = literal_str(first) if first is not None else None

        if fn in ("importlib.import_module", "import_module", "__import__", "importlib.__import__"):
            self.dynamic_imports.append({"line": node.lineno, "call": fn, "module": first_lit})
        elif fn in ("pkgutil.iter_modules", "pkgutil.walk_packages", "pkg_resources.iter_entry_points",
                    "entry_points", "importlib.metadata.entry_points", "metadata.entry_points"):
            self.dynamic_imports.append({"line": node.lineno, "call": fn, "module": None})

        if fn in ("os.getenv", "getenv", "os.environ.get", "environ.get", "os.environ.setdefault",
                  "os.environ.pop") and first_lit:
            self.env_vars.append((first_lit, node.lineno, "optional" if len(node.args) > 1 or fn.endswith("setdefault") else "read"))

        if fn in ("argparse.ArgumentParser", "ArgumentParser"):
            self.cli.add("argparse")
            for kw in node.keywords:
                if kw.arg == "add_help" and isinstance(kw.value, ast.Constant) and kw.value.value is False:
                    self.argparse_add_help = False
        if short == "add_argument":
            for a in node.args:
                s = literal_str(a)
                if s and s.startswith("-"):
                    self.cli_options.add(s)
        if fn in ("typer.Typer", "typer.run", "Typer"):
            self.cli.add("typer")
        if fn in ("fire.Fire", "Fire"):
            self.cli.add("fire")
        if fn in ("docopt", "docopt.docopt"):
            self.cli.add("docopt")
        if fn in ("optparse.OptionParser", "OptionParser"):
            self.cli.add("optparse")
        if fn in ("click.command", "click.group"):
            self.cli.add("click")

        if fn in ("os.getcwd", "getcwd", "Path.cwd", "pathlib.Path.cwd"):
            self.uses_getcwd = True
        if fn in ("os.chdir", "chdir"):
            self.chdir = True

        is_path_call = short in PATH_CALLS or fn == "sqlite3.connect"
        if is_path_call and first_lit and is_relative_file_literal(first_lit):
            self.cwd_paths.append({"line": node.lineno, "call": short, "path": first_lit})

        if fn in ("subprocess.run", "subprocess.call", "subprocess.check_call", "subprocess.check_output",
                  "subprocess.Popen", "run", "Popen", "check_output", "check_call", "os.system", "os.popen",
                  "os.startfile", "os.execv", "os.spawnv"):
            cmd = None
            if first_lit:
                cmd = first_lit.strip().split()[0] if first_lit.strip() else None
            elif isinstance(first, (ast.List, ast.Tuple)) and first.elts:
                cmd = literal_str(first.elts[0])
            if cmd and fn != "os.startfile":
                self.subprocess_cmds.append({"line": node.lineno, "command": os.path.basename(cmd.strip('"'))})

        for kw in node.keywords:
            if kw.arg == "port" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, int):
                self.ports.append(kw.value.value)
        self.generic_visit(node)


# --------------------------------------------------------------------------------------
# Analyzer
# --------------------------------------------------------------------------------------

class Analyzer(object):
    def __init__(self, source, exclude_dirs, exclude_dir_patterns, entry_point=None):
        self.source = os.path.abspath(source)
        self.exclude_dirs = set(d.lower() for d in exclude_dirs)
        self.exclude_dir_patterns = exclude_dir_patterns
        self.requested_entry = entry_point
        self.stdlib = stdlib_names()
        self.warnings = []
        self.errors = []
        self.report = {}

    # ----------------------------------------------------------------------------
    def warn(self, code, message, **extra):
        item = {"code": code, "message": message}
        item.update(extra)
        self.warnings.append(item)

    def error(self, code, message, **extra):
        item = {"code": code, "message": message}
        item.update(extra)
        self.errors.append(item)

    # ----------------------------------------------------------------------------
    def run(self):
        if os.path.isfile(self.source):
            if not self.source.lower().endswith((".py", ".pyw")):
                self.error("source-not-python", "Source file is not a .py/.pyw file: %s" % self.source)
                return self.finish()
            self.kind = "file"
            self.root = os.path.dirname(self.source)
            self.py_files = [self.source]
            self.other_files = []
        elif os.path.isdir(self.source):
            self.kind = "directory"
            self.root = self.source
            self.py_files, self.other_files = self.walk()
        else:
            self.error("source-missing", "Source path does not exist: %s" % self.source)
            return self.finish()

        self.read_metadata()
        self.detect_layout()
        self.index_modules()
        self.parse_files()
        self.classify_imports()
        self.resolve_entry_point()
        self.collect_prerequisites()
        return self.finish()

    def finish(self):
        self.report["analyzerVersion"] = ANALYZER_VERSION
        self.report["analyzerPython"] = "%d.%d.%d" % sys.version_info[:3]
        self.report["warnings"] = self.warnings
        self.report["errors"] = self.errors
        return self.report

    # ----------------------------------------------------------------------------
    def excluded_dir(self, name):
        low = name.lower()
        if low in self.exclude_dirs:
            return True
        return any(fnmatch.fnmatch(low, p.lower()) for p in self.exclude_dir_patterns)

    def walk(self):
        py, other = [], []
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = sorted(d for d in dirnames if not self.excluded_dir(d)
                                 and not os.path.islink(os.path.join(dirpath, d)))
            for f in sorted(filenames):
                full = os.path.join(dirpath, f)
                if f.lower().endswith((".py", ".pyw")):
                    py.append(full)
                else:
                    other.append(full)
        return py, other

    # ----------------------------------------------------------------------------
    def read_metadata(self):
        r = self.report
        r["sourceKind"] = self.kind
        r["projectRoot"] = self.root
        r["projectName"] = None
        r["projectVersion"] = None
        r["pythonRequirement"] = None
        r["dependencySources"] = []
        r["declaredEntryPoints"] = []
        r["lockFiles"] = []
        r["metadataFiles"] = []
        r["packageDirs"] = {}
        root = self.root
        single = self.kind == "file"

        pyproject = os.path.join(root, "pyproject.toml")
        if os.path.isfile(pyproject) and not single:
            r["metadataFiles"].append("pyproject.toml")
            try:
                data = load_toml(pyproject)
            except Exception as exc:  # noqa
                self.error("invalid-pyproject", "pyproject.toml could not be parsed: %s" % exc)
                data = {}
            project = data.get("project", {}) if isinstance(data, dict) else {}
            if project:
                r["projectName"] = project.get("name")
                r["projectVersion"] = project.get("version")
                if project.get("requires-python"):
                    r["pythonRequirement"] = {"specifier": project["requires-python"], "source": "pyproject.toml"}
                deps = project.get("dependencies")
                if deps is not None:
                    if not isinstance(deps, list) or not all(isinstance(d, str) for d in deps):
                        self.error("invalid-pyproject", "[project].dependencies must be a list of strings")
                    else:
                        r["dependencySources"].append({"kind": "pyproject", "file": "pyproject.toml",
                                                       "requirements": deps})
                for group, gui in (("scripts", False), ("gui-scripts", True)):
                    for name, target in (project.get(group) or {}).items():
                        r["declaredEntryPoints"].append({"name": name, "target": target, "gui": gui,
                                                         "source": "pyproject.toml [project.%s]" % group})
            tool = data.get("tool", {}) if isinstance(data, dict) else {}
            poetry = tool.get("poetry", {}) if isinstance(tool, dict) else {}
            if poetry:
                r["projectName"] = r["projectName"] or poetry.get("name")
                r["projectVersion"] = r["projectVersion"] or poetry.get("version")
                pdeps = poetry.get("dependencies") or {}
                reqs = []
                for name, spec in pdeps.items():
                    if name.lower() == "python":
                        conv = convert_poetry_constraint(spec if isinstance(spec, str) else "")
                        if conv and not r["pythonRequirement"]:
                            r["pythonRequirement"] = {"specifier": conv, "source": "pyproject.toml [tool.poetry]"}
                        continue
                    if isinstance(spec, dict):
                        if spec.get("optional"):
                            continue
                        if "path" in spec or "git" in spec or "url" in spec:
                            self.warn("poetry-nonregistry", "Poetry dependency '%s' uses path/git/url; "
                                      "export requirements explicitly." % name)
                            continue
                        extras = spec.get("extras")
                        ver = convert_poetry_constraint(spec.get("version", "*"))
                        markers = spec.get("markers")
                        line = name + ("[%s]" % ",".join(extras) if extras else "") + (ver or "")
                        if markers:
                            line += " ; " + markers
                        reqs.append(line)
                    else:
                        reqs.append(name + (convert_poetry_constraint(spec) or ""))
                if pdeps:
                    r["dependencySources"].append({"kind": "poetry", "file": "pyproject.toml", "requirements": reqs})
                for name, target in (poetry.get("scripts") or {}).items():
                    if isinstance(target, dict):
                        target = target.get("callable") or target.get("reference")
                    if isinstance(target, str):
                        r["declaredEntryPoints"].append({"name": name, "target": target, "gui": False,
                                                         "source": "pyproject.toml [tool.poetry.scripts]"})
            setuptools_cfg = tool.get("setuptools", {}) if isinstance(tool, dict) else {}
            pkg_dir = setuptools_cfg.get("package-dir") if isinstance(setuptools_cfg, dict) else None
            if isinstance(pkg_dir, dict):
                r["packageDirs"].update(pkg_dir)
            find = ((setuptools_cfg.get("packages") or {}) if isinstance(setuptools_cfg, dict) else {})
            if isinstance(find, dict) and isinstance(find.get("find"), dict):
                where = find["find"].get("where")
                if where:
                    r["packageDirs"].setdefault("", where[0] if isinstance(where, list) else where)

        setup_cfg = os.path.join(root, "setup.cfg")
        if os.path.isfile(setup_cfg) and not single:
            r["metadataFiles"].append("setup.cfg")
            cp = configparser.ConfigParser(interpolation=None)
            try:
                cp.read(setup_cfg, encoding="utf-8")
                if cp.has_option("metadata", "name"):
                    r["projectName"] = r["projectName"] or cp.get("metadata", "name")
                if cp.has_option("options", "python_requires") and not r["pythonRequirement"]:
                    r["pythonRequirement"] = {"specifier": cp.get("options", "python_requires").strip(),
                                              "source": "setup.cfg"}
                if cp.has_option("options", "install_requires"):
                    reqs = [l.strip() for l in cp.get("options", "install_requires").splitlines() if l.strip()]
                    r["dependencySources"].append({"kind": "setup.cfg", "file": "setup.cfg", "requirements": reqs})
                if cp.has_option("options", "package_dir"):
                    for line in cp.get("options", "package_dir").splitlines():
                        if "=" in line:
                            k, v = line.split("=", 1)
                            r["packageDirs"][k.strip()] = v.strip()
                for section, gui in (("console_scripts", False), ("gui_scripts", True)):
                    if cp.has_option("options.entry_points", section):
                        for line in cp.get("options.entry_points", section).splitlines():
                            if "=" in line:
                                n, t = line.split("=", 1)
                                r["declaredEntryPoints"].append({"name": n.strip(), "target": t.strip(), "gui": gui,
                                                                 "source": "setup.cfg"})
            except configparser.Error as exc:
                self.error("invalid-setup-cfg", "setup.cfg could not be parsed: %s" % exc)

        setup_py = os.path.join(root, "setup.py")
        if os.path.isfile(setup_py) and not single:
            r["metadataFiles"].append("setup.py")
            self.read_setup_py(setup_py)

        # requirements files and lock files
        candidates = []
        for name in sorted(os.listdir(root)):
            low = name.lower()
            full = os.path.join(root, name)
            if not os.path.isfile(full):
                continue
            if low in ("pipfile.lock",):
                candidates.append(("pipfile-lock", name))
            elif low in ("poetry.lock", "uv.lock", "pdm.lock", "pylock.toml") or re.match(r"^pylock\..+\.toml$", low):
                r["lockFiles"].append(name)
            elif re.match(r"^requirements([-_.]?(lock|locked|frozen|freeze|prod|production|main|base))?\.(txt|lock|in)$", low):
                candidates.append(("requirements", name))
            elif low == "pipfile":
                candidates.append(("pipfile", name))
        for kind, name in candidates:
            full = os.path.join(root, name)
            if kind == "pipfile-lock":
                try:
                    with open(full, "r", encoding="utf-8") as fh:
                        lock = json.load(fh)
                    reqs = []
                    for pkg, info in sorted((lock.get("default") or {}).items()):
                        ver = info.get("version", "")
                        line = pkg + (("[%s]" % ",".join(info["extras"])) if info.get("extras") else "") + ver
                        if info.get("markers"):
                            line += " ; " + info["markers"]
                        reqs.append(line)
                    r["dependencySources"].append({"kind": "pipfile-lock", "file": name, "requirements": reqs,
                                                   "locked": True})
                except (ValueError, OSError) as exc:
                    self.error("invalid-lockfile", "%s could not be parsed: %s" % (name, exc))
            elif kind == "requirements":
                if name.lower().endswith(".in"):
                    continue
                lines = self.read_requirements(full)
                locked = all(("==" in l or l.startswith("-")) for l in lines) and bool(lines)
                r["dependencySources"].append({"kind": "requirements", "file": name, "requirements": lines,
                                               "locked": locked or "lock" in name.lower() or "freeze" in name.lower()
                                               or "frozen" in name.lower()})
            elif kind == "pipfile":
                r["metadataFiles"].append(name)

        pv = os.path.join(root, ".python-version")
        if os.path.isfile(pv):
            ver = read_text(pv).strip().splitlines()
            if ver:
                r["pythonVersionFile"] = ver[0].strip()
        rt = os.path.join(root, "runtime.txt")
        if os.path.isfile(rt):
            m = re.search(r"(\d+\.\d+(?:\.\d+)?)", read_text(rt))
            if m:
                r.setdefault("pythonVersionFile", m.group(1))

        if r["lockFiles"]:
            supported = [s for s in r["dependencySources"] if s.get("locked")]
            if not supported:
                self.warn("unsupported-lockfile",
                          "Lock file(s) %s are not read directly. Export pinned requirements "
                          "(e.g. 'poetry export -f requirements.txt', 'uv export --format requirements-txt', "
                          "'pdm export') and pass them with -Requirements to preserve locked versions."
                          % ", ".join(r["lockFiles"]))

    def read_requirements(self, path):
        lines = []
        for raw in read_text(path).splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if " #" in line:
                line = line.split(" #", 1)[0].strip()
            lines.append(line)
        return lines

    def read_setup_py(self, path):
        r = self.report
        try:
            tree = ast.parse(read_text(path), path)
        except SyntaxError as exc:
            self.error("invalid-setup-py", "setup.py has a syntax error: %s" % exc)
            return
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and (dotted_name(node.func) or "").split(".")[-1] == "setup":
                for kw in node.keywords:
                    try:
                        value = ast.literal_eval(kw.value)
                    except (ValueError, TypeError, SyntaxError, MemoryError, RecursionError):
                        if kw.arg in ("install_requires", "entry_points"):
                            self.warn("setup-py-dynamic", "setup.py '%s' is computed dynamically and was not "
                                      "evaluated (setup.py is never executed). Provide a requirements file or "
                                      "-EntryPoint explicitly." % kw.arg)
                        continue
                    if kw.arg == "name" and isinstance(value, str):
                        r["projectName"] = r["projectName"] or value
                    elif kw.arg == "python_requires" and isinstance(value, str) and not r["pythonRequirement"]:
                        r["pythonRequirement"] = {"specifier": value, "source": "setup.py"}
                    elif kw.arg == "install_requires" and isinstance(value, (list, tuple)):
                        r["dependencySources"].append({"kind": "setup.py", "file": "setup.py",
                                                       "requirements": [str(v) for v in value]})
                    elif kw.arg == "package_dir" and isinstance(value, dict):
                        r["packageDirs"].update(value)
                    elif kw.arg == "entry_points" and isinstance(value, dict):
                        for section, gui in (("console_scripts", False), ("gui_scripts", True)):
                            items = value.get(section) or []
                            if isinstance(items, str):
                                items = items.splitlines()
                            for item in items:
                                if "=" in item:
                                    n, t = item.split("=", 1)
                                    r["declaredEntryPoints"].append({"name": n.strip(), "target": t.strip(),
                                                                     "gui": gui, "source": "setup.py"})

    # ----------------------------------------------------------------------------
    def detect_layout(self):
        r = self.report
        roots = []
        pkg_dir_root = r["packageDirs"].get("")
        if self.kind == "file":
            layout = "single-file"
            roots = ["."]
        elif pkg_dir_root and os.path.isdir(os.path.join(self.root, pkg_dir_root)):
            layout = "src" if pkg_dir_root.strip("/\\") == "src" else "custom"
            roots = [pkg_dir_root.replace("\\", "/").strip("/")]
        else:
            src = os.path.join(self.root, "src")
            has_src_code = os.path.isdir(src) and any(
                f.endswith(".py") or os.path.isfile(os.path.join(src, f, "__init__.py"))
                for f in os.listdir(src))
            root_packages = [d for d in os.listdir(self.root)
                             if os.path.isfile(os.path.join(self.root, d, "__init__.py"))
                             and d.lower() not in TEST_DIR_NAMES and not self.excluded_dir(d)]
            if has_src_code and not root_packages:
                layout = "src"
                roots = ["src"]
            else:
                layout = "flat"
                roots = ["."]
        r["layout"] = layout
        r["importRoots"] = roots

    def module_name_for(self, path):
        """Returns the dotted module name of a file relative to the first import root containing it."""
        for root in self.report["importRoots"]:
            base = os.path.normpath(os.path.join(self.root, root))
            if os.path.normcase(path).startswith(os.path.normcase(base + os.sep)) or \
                    os.path.normcase(os.path.dirname(path)) == os.path.normcase(base):
                relp = os.path.relpath(path, base)
                parts = relp.replace("\\", "/").split("/")
                parts[-1] = os.path.splitext(parts[-1])[0]
                if parts[-1] == "__init__":
                    parts = parts[:-1]
                if all(re.match(r"^[A-Za-z_]\w*$", p) for p in parts) and parts:
                    return ".".join(parts)
                return None
        return None

    def index_modules(self):
        self.local_names = set()
        self.modules = {}
        for f in self.py_files:
            stem = os.path.splitext(os.path.basename(f))[0]
            if stem != "__init__":
                self.local_names.add(stem)
            parent = os.path.dirname(f)
            while os.path.normcase(parent) != os.path.normcase(self.root) and \
                    os.path.normcase(parent).startswith(os.path.normcase(self.root)):
                self.local_names.add(os.path.basename(parent))
                parent = os.path.dirname(parent)
            mod = self.module_name_for(f)
            if mod:
                self.modules[mod] = rel(f, self.root)
        self.report["localModules"] = sorted(self.modules.keys())
        self.report["localTopLevel"] = sorted(set(m.split(".")[0] for m in self.modules))
        packages = set()
        for f in self.py_files:
            if os.path.basename(f) == "__init__.py":
                mod = self.module_name_for(f)
                if mod:
                    packages.add(mod)
        self.report["localPackages"] = sorted(packages)

    # ----------------------------------------------------------------------------
    def parse_files(self):
        self.visitors = {}
        self.syntax_errors = []
        for f in self.py_files:
            relp = rel(f, self.root)
            try:
                text = read_text(f)
                tree = ast.parse(text, f)
            except SyntaxError as exc:
                self.syntax_errors.append({"file": relp, "line": exc.lineno, "error": exc.msg})
                continue
            except (ValueError, OSError) as exc:
                self.syntax_errors.append({"file": relp, "line": 0, "error": str(exc)})
                continue
            v = FileVisitor(relp)
            v.visit(tree)
            self.visitors[relp] = v
        if self.syntax_errors:
            self.warn("syntax-errors", "%d file(s) could not be parsed by Python %d.%d (they may need a newer "
                      "Python or contain errors)." % ((len(self.syntax_errors),) + sys.version_info[:2]),
                      files=self.syntax_errors)
        self.report["syntaxErrors"] = self.syntax_errors

    def classify_imports(self):
        third, stdlib, local = {}, set(), set()
        relative_count = 0
        dynamic = []
        env = {}
        cwd_paths, abs_paths = [], []
        cli_files = {}
        argv_files = []
        for relp, v in self.visitors.items():
            relative_count += len(v.relative_imports)
            for name, line, ctx in v.imports:
                if ctx == "submodule-candidate":
                    continue
                top = name.split(".")[0]
                if top in self.stdlib:
                    stdlib.add(top)
                elif top in self.local_names:
                    local.add(top)
                else:
                    entry = third.setdefault(top, {"name": top, "files": [], "contexts": set(), "fullNames": set()})
                    entry["files"].append("%s:%d" % (relp, line))
                    entry["contexts"].add(ctx)
                    entry["fullNames"].add(name)
            for d in v.dynamic_imports:
                item = dict(d)
                item["file"] = relp
                dynamic.append(item)
            for name, line, kind in v.env_vars:
                e = env.setdefault(name, {"name": name, "files": [], "required": False})
                e["files"].append("%s:%d" % (relp, line))
                if kind == "required":
                    e["required"] = True
            for c in v.cwd_paths:
                c = dict(c)
                c["file"] = relp
                cwd_paths.append(c)
            for s, line in v.strings:
                if ABS_PATH_RE.match(s) and len(s) < 260 and "\n" not in s:
                    abs_paths.append({"file": relp, "line": line, "path": s})
            if v.cli:
                cli_files[relp] = sorted(v.cli)
            if v.uses_sys_argv:
                argv_files.append(relp)

        third_list = []
        for top, e in sorted(third.items()):
            ctxs = e["contexts"]
            required = bool(ctxs & {"top-level", "conditional", "deferred"}) and not ctxs <= {"guarded", "type-checking"}
            if ctxs <= {"type-checking"}:
                continue
            third_list.append({
                "name": top,
                "files": e["files"][:10],
                "contexts": sorted(ctxs),
                "optional": not required,
                "suggestedDistribution": KNOWN_IMPORT_TO_DIST.get(top),
            })
        self.report["imports"] = {
            "thirdParty": third_list,
            "stdlib": sorted(stdlib),
            "local": sorted(local),
            "relativeImportCount": relative_count,
        }
        nonliteral = [d for d in dynamic if not d.get("module")]
        self.report["dynamicImports"] = dynamic
        if nonliteral:
            self.warn("dynamic-imports", "%d dynamic import(s) with non-literal module names were found; "
                      "the modules they load cannot be detected statically. All local modules are bundled; "
                      "add third-party ones with -HiddenImport if needed." % len(nonliteral),
                      locations=["%s:%d" % (d["file"], d["line"]) for d in nonliteral][:20])
        self.report["environmentVariables"] = sorted(
            [{"name": e["name"], "required": e["required"], "files": e["files"][:5]} for e in env.values()],
            key=lambda x: x["name"])
        self.report["workingDirectoryAssumptions"] = cwd_paths[:200]
        self.report["hardcodedAbsolutePaths"] = abs_paths[:200]
        self.report["cliFrameworkFiles"] = cli_files
        self.report["sysArgvFiles"] = sorted(argv_files)
        if cwd_paths:
            self.warn("cwd-relative-paths", "%d file access(es) use paths relative to the current working "
                      "directory. The embedded launcher runs the application with the app directory as the "
                      "working directory by default; executables run from the caller's directory." % len(cwd_paths),
                      locations=["%s:%d %s" % (c["file"], c["line"], c["path"]) for c in cwd_paths][:20])
        if abs_paths:
            self.warn("hardcoded-paths", "%d hardcoded absolute path(s) found. They will not be rewritten; "
                      "make them configurable for portable deployment." % len(abs_paths),
                      locations=["%s:%d %s" % (a["file"], a["line"], a["path"]) for a in abs_paths][:20])

        # application types
        all_imports = set(stdlib) | set(t["name"] for t in third_list)
        cli_all = set()
        for fw in cli_files.values():
            cli_all.update(fw)
        cli_all |= (all_imports & CLI_FRAMEWORKS)
        types = []
        gui = sorted(all_imports & GUI_FRAMEWORKS)
        if gui:
            types.append("gui")
        if all_imports & WEB_FRAMEWORKS:
            types.append("web-service")
        if all_imports & SERVICE_LIBS:
            types.append("windows-service")
        if all_imports & DB_LIBS:
            types.append("database-tool")
        if all_imports & REPORTING_LIBS:
            types.append("reporting")
        if cli_all or argv_files:
            types.append("cli")
        if not types:
            types.append("script")
        self.report["applicationTypes"] = types
        self.report["guiFrameworks"] = gui
        self.report["cliFrameworks"] = sorted(cli_all)
        self.report["databaseLibraries"] = sorted(all_imports & DB_LIBS)

        # declared vs imported
        declared = set()
        for src in self.report["dependencySources"]:
            for line in src["requirements"]:
                n = req_name(line)
                if n:
                    declared.add(n)
        self.report["declaredDistributions"] = sorted(declared)
        undeclared = []
        for t in third_list:
            cand = {norm_dist(t["name"])}
            if t["suggestedDistribution"]:
                cand.add(norm_dist(t["suggestedDistribution"].split("[")[0]))
                if t["name"] == "psycopg2":
                    cand.add("psycopg2")
                if t["name"] == "psycopg":
                    cand.add("psycopg")
            if not (cand & declared):
                undeclared.append(t["name"])
        self.report["undeclaredImports"] = undeclared

    # ----------------------------------------------------------------------------
    def entry_from_target(self, target):
        """'pkg.mod:func' -> callable entry; 'pkg.mod' -> module entry."""
        target = target.split("[")[0].strip()
        if ":" in target:
            mod, func = target.split(":", 1)
            return {"kind": "callable", "module": mod.strip(), "function": func.strip()}
        return {"kind": "module", "module": target}

    def describe(self, ep):
        if ep["kind"] == "script":
            return ep["path"]
        if ep["kind"] == "module":
            return ep["module"]
        return "%s:%s" % (ep["module"], ep["function"])

    def check_entry(self, ep):
        """Validates an entry point against the project. Returns an error string or None."""
        if ep["kind"] == "script":
            full = os.path.normpath(os.path.join(self.root, ep["path"]))
            if not os.path.isfile(full):
                return "entry script not found: %s" % ep["path"]
            return None
        mod = ep["module"]
        if mod in self.modules:
            path = self.modules[mod]
            if ep["kind"] == "module" and path.endswith("__init__.py"):
                main_mod = mod + ".__main__"
                if main_mod not in self.modules:
                    return "package '%s' has no __main__.py and cannot be run with -m" % mod
            if ep["kind"] == "callable":
                v = self.visitors.get(path)
                func = ep["function"].split(".")[0]
                if v is not None and func not in v.defined_functions:
                    imported = any(n.endswith("." + func) or n == func for n, _l, _c in v.imports) or \
                        any(func in (x or "") for x in [r.get("module") for r in v.relative_imports])
                    if not imported:
                        return "callable '%s' is not defined at module level in %s" % (func, path)
            return None
        top = mod.split(".")[0]
        if top in self.report.get("localTopLevel", []):
            return "module '%s' not found in the project" % mod
        return "module '%s' is not part of the project (third-party entry points are not supported)" % mod

    def resolve_entry_point(self):
        r = self.report
        candidates = []
        selected = None
        reason = None
        root = self.root

        if self.requested_entry:
            req = self.requested_entry.strip()
            ep = None
            declared = {d["name"]: d for d in r["declaredEntryPoints"]}
            if req in declared:
                ep = self.entry_from_target(declared[req]["target"])
                ep["gui"] = declared[req]["gui"]
                reason = "explicit (-EntryPoint matched declared script '%s')" % req
            elif req.lower().endswith((".py", ".pyw")) or "/" in req or "\\" in req:
                full = req if os.path.isabs(req) else os.path.join(root, req)
                full = os.path.normpath(full)
                if not os.path.normcase(full).startswith(os.path.normcase(root + os.sep)) and \
                        os.path.normcase(full) != os.path.normcase(root):
                    self.error("entry-outside-project", "Entry point '%s' is outside the project directory." % req)
                    r["entryPoint"] = None
                    r["entryPointCandidates"] = []
                    return
                ep = {"kind": "script", "path": rel(full, root)}
                reason = "explicit (-EntryPoint)"
            else:
                ep = self.entry_from_target(req)
                reason = "explicit (-EntryPoint)"
            err = self.check_entry(ep)
            if err:
                self.error("invalid-entry-point", "Entry point '%s' is invalid: %s" % (req, err))
                r["entryPoint"] = None
                r["entryPointCandidates"] = []
                return
            selected = ep
        elif self.kind == "file":
            selected = {"kind": "script", "path": os.path.basename(self.source)}
            reason = "single-file source"
        else:
            for d in r["declaredEntryPoints"]:
                ep = self.entry_from_target(d["target"])
                ep["gui"] = d["gui"]
                ep["declaredName"] = d["name"]
                err = self.check_entry(ep)
                if err:
                    self.warn("declared-entry-invalid", "Declared entry point '%s = %s' (%s) is not usable: %s"
                              % (d["name"], d["target"], d["source"], err))
                    continue
                ep["reason"] = "declared in %s as '%s'" % (d["source"], d["name"])
                candidates.append(ep)
            if not candidates:
                primary, secondary = [], []
                for relp, v in sorted(self.visitors.items()):
                    parts = relp.split("/")
                    if any(p.lower() in TEST_DIR_NAMES for p in parts[:-1]):
                        continue
                    base = parts[-1]
                    if base in NON_ENTRY_FILES or base.startswith("test_") or base.endswith("_test.py"):
                        continue
                    if base == "__main__.py":
                        mod = self.module_name_for(os.path.join(root, relp))
                        if mod and mod.endswith(".__main__"):
                            pkg = mod[: -len(".__main__")]
                            ep = {"kind": "module", "module": pkg, "reason": "package with __main__.py"}
                            (primary if "." not in pkg else secondary).append(ep)
                        continue
                    if v.has_main_guard:
                        ep = {"kind": "script", "path": relp, "reason": "script with if __name__ == '__main__'"}
                        in_root = len(parts) == 1 or (len(parts) == 2 and parts[0] in r["importRoots"])
                        in_package = os.path.isfile(os.path.join(root, *(parts[:-1] + ["__init__.py"]))) \
                            if len(parts) > 1 else False
                        (primary if in_root and not in_package else secondary).append(ep)
                candidates = primary or secondary
                if not candidates:
                    top_scripts = [p for p in self.visitors if "/" not in p and p not in NON_ENTRY_FILES
                                   and not p.startswith("test_")]
                    if len(top_scripts) == 1 and not r["localPackages"]:
                        candidates = [{"kind": "script", "path": top_scripts[0],
                                       "reason": "only top-level Python script"}]
            if len(candidates) == 1:
                selected = dict(candidates[0])
                reason = selected.pop("reason", "auto-detected")
            elif len(candidates) > 1:
                self.error("ambiguous-entry-point",
                           "Multiple entry-point candidates were found. Select one with -EntryPoint.",
                           candidates=[{"value": self.describe(c), "reason": c.get("reason")} for c in candidates])
            else:
                self.error("no-entry-point",
                           "No entry point could be detected (no declared scripts, no __main__.py, no script with "
                           "an if __name__ == '__main__' block). Specify one with -EntryPoint.")
        r["entryPointCandidates"] = [{"value": self.describe(c), "reason": c.get("reason")} for c in candidates]
        if selected:
            selected.pop("reason", None)
            selected["display"] = self.describe(selected)
            selected["selectionReason"] = reason
            # file backing the entry point (for CLI detection)
            if selected["kind"] == "script":
                selected["file"] = selected["path"]
            else:
                mod = selected["module"]
                f = self.modules.get(mod + ".__main__") if selected["kind"] == "module" and \
                    (self.modules.get(mod, "").endswith("__init__.py")) else self.modules.get(mod)
                selected["file"] = f
            r["entryPoint"] = selected
            self.detect_safe_probe(selected)
        else:
            r["entryPoint"] = None
            r["safeTestArgs"] = []

    def detect_safe_probe(self, ep):
        """Chooses an EXISTING safe option (--help) only when a CLI framework that provides it is used."""
        r = self.report
        files = []
        if ep.get("file"):
            files.append(ep["file"])
        # also consider modules imported by the entry file (e.g. __main__ -> cli)
        v = self.visitors.get(ep.get("file") or "")
        if v is not None:
            for name, _l, _c in v.imports:
                if name in self.modules:
                    files.append(self.modules[name])
            for ri in v.relative_imports:
                pkg_dir = os.path.dirname(ep["file"])
                cand = os.path.join(pkg_dir, (ri["module"] or "").replace(".", "/") + ".py").replace("\\", "/")
                if cand in self.visitors:
                    files.append(cand)
        frameworks = set()
        add_help = True
        options = set()
        for f in files:
            fv = self.visitors.get(f)
            if fv is None:
                continue
            frameworks |= fv.cli
            options |= fv.cli_options
            if "argparse" in fv.cli and not fv.argparse_add_help:
                add_help = False
        args = []
        gui = bool(self.report.get("guiFrameworks")) and not frameworks
        if not gui:
            if frameworks & {"click", "typer"}:
                args = ["--help"]
            elif "argparse" in frameworks and add_help:
                args = ["--help"]
            elif "-h" in options or "--help" in options:
                args = ["--help"] if "--help" in options else ["-h"]
        r["safeTestArgs"] = args
        r["safeTestReason"] = ("'%s' is provided by %s" % (" ".join(args), ", ".join(sorted(frameworks)))) if args \
            else "no CLI framework with a built-in help option was detected for the entry point; the application " \
                 "will not be executed during validation"

    # ----------------------------------------------------------------------------
    def collect_prerequisites(self):
        r = self.report
        prereq = []
        third = set(t["name"] for t in r["imports"]["thirdParty"])
        stdlib = set(r["imports"]["stdlib"])
        allmods = third | stdlib
        declared = set(r.get("declaredDistributions", []))
        strings = []
        for relp, v in self.visitors.items():
            for s, line in v.strings:
                strings.append((s, relp, line))

        def add(category, name, detail, evidence=None):
            for p in prereq:
                if p["category"] == category and p["name"] == name:
                    if evidence and evidence not in p["evidence"]:
                        p["evidence"].append(evidence)
                    return
            prereq.append({"category": category, "name": name, "detail": detail,
                           "evidence": [evidence] if evidence else []})

        if "pyodbc" in allmods:
            drivers = set()
            for s, f, l in strings:
                for m in DRIVER_KV_RE.finditer(s):
                    drivers.add(m.group(1).strip())
                for m in ODBC_DRIVER_RE.finditer(s):
                    if "driver" in s.lower() or s.strip() == m.group(1):
                        drivers.add(m.group(1))
            if drivers:
                for d in sorted(drivers):
                    add("odbc-driver", d, "ODBC driver referenced by the application. It is NOT bundled; install it "
                        "on the destination server (64-bit driver for 64-bit packages).", "pyodbc")
            else:
                add("odbc-driver", "ODBC driver (unspecified)", "pyodbc requires an ODBC driver installed on the "
                    "destination (e.g. Microsoft ODBC Driver 18 for SQL Server). Drivers are never bundled.", "pyodbc")
        if "psycopg" in allmods and not ({"psycopg-binary"} & declared) and not any(
                "psycopg[binary" in l or "psycopg[c" in l for s in r["dependencySources"] for l in s["requirements"]):
            add("native-library", "libpq", "psycopg (v3) without the [binary] extra requires the PostgreSQL client "
                "library (libpq.dll) on the destination. Prefer 'psycopg[binary]'.", "psycopg")
        if "cx_Oracle" in allmods:
            add("native-library", "Oracle Instant Client", "cx_Oracle requires Oracle Instant Client on the "
                "destination.", "cx_Oracle")
        if "oracledb" in allmods and any("init_oracle_client" in c for v in self.visitors.values() for c in v.calls):
            add("native-library", "Oracle Instant Client", "python-oracledb thick mode (init_oracle_client) "
                "requires Oracle Instant Client.", "oracledb")
        if "ibm_db" in allmods:
            add("native-library", "IBM Db2 CLI driver", "ibm_db may require the IBM CLI driver.", "ibm_db")
        if third & {"boto3", "botocore", "aiobotocore", "awswrangler"}:
            add("credentials", "AWS credentials", "AWS SDK usage: provide credentials on the destination through an "
                "instance/role profile, AWS_PROFILE or the standard credential chain. Credentials are never packaged.",
                "boto3")
            add("network", "AWS service endpoints", "Outbound HTTPS (443) and DNS resolution for AWS endpoints.",
                "boto3")
        if any("generate_db_auth_token" in c for v in self.visitors.values() for c in v.calls):
            add("credentials", "IAM database authentication", "RDS/Aurora IAM authentication tokens are generated at "
                "runtime; the destination identity needs rds-db:connect permission and TLS to the database.",
                "generate_db_auth_token")
        tls_hits = [(f, l) for s, f, l in strings if re.search(r"\bssl(mode|rootcert|_ca|_cert|_key)\b|\bsslrootcert\b|"
                                                             r"\.pem$|\.crt$|global-bundle|rds-ca", s, re.I)]
        if tls_hits or ("ssl" in stdlib and r["databaseLibraries"]):
            add("certificate", "TLS CA certificates", "The application uses TLS settings or certificate files. Ship "
                "only public CA bundles (never private keys) and keep certificate validation enabled.",
                "%s:%d" % tls_hits[0] if tls_hits else "ssl")
        for lib in sorted(set(r["databaseLibraries"]) & set(DEFAULT_PORTS)):
            add("network", "TCP %d (%s)" % (DEFAULT_PORTS[lib], lib), "Default port for %s; confirm firewall and "
                "security-group rules from the destination server to the database." % lib, lib)
        ports = set()
        for v in self.visitors.values():
            ports.update(v.ports)
        for p in sorted(ports):
            add("network", "TCP %d" % p, "Port literal found in source code.", "port=%d" % p)
        if third & NETWORK_LIBS or stdlib & {"socket", "http", "urllib", "smtplib", "ftplib"} or r["databaseLibraries"]:
            add("network", "DNS resolution / outbound connectivity", "The application uses network libraries.",
                ",".join(sorted((third | stdlib) & (NETWORK_LIBS | set(r["databaseLibraries"])))[:5]))
        if third & {"win32com", "pythoncom", "comtypes"}:
            add("os-component", "COM servers", "COM automation is used (e.g. Microsoft Office). Required COM servers "
                "must be installed on the destination.", "win32com")
        if third & SERVICE_LIBS:
            add("os-component", "Windows service registration", "Service install/registration requires "
                "administrative rights on the destination.", "win32serviceutil")
        if "tkinter" in stdlib:
            add("runtime-component", "Tcl/Tk", "tkinter is used. The CPython embeddable package does not contain "
                "tkinter; the embedded builder copies it from the matching build Python. PyInstaller bundles it.",
                "tkinter")
        if r["guiFrameworks"]:
            add("os-component", "Interactive desktop session", "GUI framework(s) %s detected; the application needs "
                "an interactive desktop session (Server Core is not supported by most GUI toolkits)."
                % ", ".join(r["guiFrameworks"]), r["guiFrameworks"][0])
        for v in self.visitors.values():
            for c in v.subprocess_cmds:
                cmd = c["command"]
                if cmd.lower() in ("python", "python.exe", "py", "sys.executable", "cmd", "cmd.exe", "powershell",
                                   "powershell.exe", "pwsh"):
                    continue
                add("external-program", cmd, "Executed via subprocess/os.system; must exist on the destination PATH "
                    "or be referenced by absolute path.", "%s:%d" % (v.relpath, c["line"]))
        native = [rel(f, self.root) for f in self.other_files if os.path.splitext(f)[1].lower() in NATIVE_EXT]
        r["nativeFilesInSource"] = native
        for n in native:
            if n.lower().endswith((".so", ".dylib")):
                self.warn("non-windows-binary", "Non-Windows native library in source: %s" % n)
        configs = [rel(f, self.root) for f in self.other_files if os.path.splitext(f)[1].lower() in CONFIG_EXT
                   or os.path.basename(f).lower().startswith(".env")]
        r["configFiles"] = configs[:500]
        certs = [rel(f, self.root) for f in self.other_files if os.path.splitext(f)[1].lower() in CERT_EXT]
        r["certificateFiles"] = certs
        for e in r["environmentVariables"]:
            if e["required"]:
                add("environment-variable", e["name"], "Read with os.environ[...] (required at runtime). Configure it "
                    "on the destination; values are never packaged.", e["files"][0] if e["files"] else None)
        r["externalPrerequisites"] = prereq
        if "multiprocessing" in stdlib:
            self.warn("multiprocessing", "multiprocessing is used. Frozen executables require "
                      "multiprocessing.freeze_support() in the entry point on Windows.")


def main(argv=None):
    ap = argparse.ArgumentParser(description="PythonPortableBuilder static project analyzer")
    ap.add_argument("--source", required=True)
    ap.add_argument("--entry-point")
    ap.add_argument("--exclude-dir", action="append", default=[])
    ap.add_argument("--exclude-dir-pattern", action="append", default=[])
    ap.add_argument("--output", required=True)
    args = ap.parse_args(argv)
    analyzer = Analyzer(args.source, args.exclude_dir, args.exclude_dir_pattern, args.entry_point)
    try:
        report = analyzer.run()
    except Exception as exc:  # noqa - must always produce a report
        import traceback
        report = analyzer.finish()
        report["errors"].append({"code": "analyzer-crash", "message": "%s: %s" % (type(exc).__name__, exc),
                                 "traceback": traceback.format_exc()})
    with open(args.output, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=False, default=lambda o: sorted(o) if isinstance(o, set) else str(o))
    return 0


if __name__ == "__main__":
    sys.exit(main())
