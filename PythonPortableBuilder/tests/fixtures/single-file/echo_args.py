"""Fixture: single-file CLI. Prints its arguments as JSON and exits with --exit-code."""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Echo arguments (test fixture).")
    parser.add_argument("words", nargs="*")
    parser.add_argument("--exit-code", type=int, default=0)
    args = parser.parse_args()
    print("ECHO " + json.dumps({"words": args.words, "argv": sys.argv[1:]}))
    return args.exit_code


if __name__ == "__main__":
    sys.exit(main())
