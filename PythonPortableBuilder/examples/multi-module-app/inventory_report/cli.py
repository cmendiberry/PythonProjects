"""Command-line interface: renders a small report from bundled sample data (read-only, harmless)."""
import argparse
import os

from . import __version__
from .data import load_items
from .render import render_table


def main(argv=None):
    parser = argparse.ArgumentParser(prog="inventory-report", description="Render the sample inventory report.")
    parser.add_argument("--version", action="version", version="%(prog)s " + __version__)
    parser.add_argument("--min-quantity", type=int, default=0, help="only show items with at least this quantity")
    parser.add_argument("--title", default=os.environ.get("REPORT_TITLE", "Inventory"), help="report title")
    args = parser.parse_args(argv)
    items = [i for i in load_items() if i["quantity"] >= args.min_quantity]
    print(render_table(args.title, items))
    return 0 if items else 4
