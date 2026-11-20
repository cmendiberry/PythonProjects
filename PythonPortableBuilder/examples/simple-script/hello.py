"""Minimal example for PythonPortableBuilder: a harmless single-file command-line script.

    python hello.py --name World --repeat 2
    python hello.py --exit-code 3      # demonstrates exit-code propagation
"""
import argparse
import platform
import sys


def main(argv=None):
    parser = argparse.ArgumentParser(description="Say hello (PythonPortableBuilder example).")
    parser.add_argument("--name", default="World", help="who to greet")
    parser.add_argument("--repeat", type=int, default=1, help="how many times")
    parser.add_argument("--exit-code", type=int, default=0, help="exit with this code")
    args = parser.parse_args(argv)
    for _ in range(args.repeat):
        print("Hello, %s! (Python %s, %s)" % (args.name, platform.python_version(), sys.executable))
    return args.exit_code


if __name__ == "__main__":
    sys.exit(main())
