"""Loads the sample data that ships next to this module (located via __file__, not the working directory)."""
import csv
import json
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


def load_settings():
    with open(os.path.join(_HERE, "resources", "settings.json"), "r", encoding="utf-8") as fh:
        return json.load(fh)


def load_items():
    settings = load_settings()
    path = os.path.join(_HERE, "resources", settings["data_file"])
    with open(path, "r", encoding="utf-8", newline="") as fh:
        return [{"name": row["name"], "quantity": int(row["quantity"])} for row in csv.DictReader(fh)]
