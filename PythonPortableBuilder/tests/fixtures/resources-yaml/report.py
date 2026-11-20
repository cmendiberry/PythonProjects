"""Fixture: third-party dependency (PyYAML) plus JSON and YAML resource files."""
import argparse
import json
import os
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    argparse.ArgumentParser(description="Print settings (test fixture).").parse_args()
    with open(os.path.join(HERE, "config", "settings.yaml"), encoding="utf-8") as fh:
        settings = yaml.safe_load(fh)
    with open(os.path.join(HERE, "config", "labels.json"), encoding="utf-8") as fh:
        labels = json.load(fh)
    print("REPORT %s %s yaml=%s" % (settings["title"], labels["unit"], yaml.__version__))
    return 0


if __name__ == "__main__":
    sys.exit(main())
