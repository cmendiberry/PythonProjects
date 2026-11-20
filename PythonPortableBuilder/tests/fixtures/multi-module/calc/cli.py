import argparse

from .ops import add


def run(argv):
    p = argparse.ArgumentParser(prog="calc")
    p.add_argument("a", type=int)
    p.add_argument("b", type=int)
    args = p.parse_args(argv)
    print("SUM %d" % add(args.a, args.b))
    return 0
