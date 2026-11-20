"""Fixture: src layout with a declared console script."""
import sys

from srcapp.helpers import greeting


def cli():
    print(greeting(sys.argv[1:]))
    return 0
