"""Print rows of a CSV file."""
import argparse
import csv
import json
import sys


def main(argv=None):
    ap = argparse.ArgumentParser(description="Print rows of a CSV file.")
    ap.add_argument("--input", required=True, help="CSV file to read")
    ap.add_argument("--limit", type=int, default=10, help="maximum number of rows (default 10)")
    ap.add_argument("--format", choices=["csv", "json"], default="csv", help="output format")
    ap.add_argument("--verbose", action="store_true", help="print the row count to stderr")
    args = ap.parse_args(argv)
    with open(args.input, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))[: args.limit]
    if args.format == "json":
        print(json.dumps(rows, indent=2))
    else:
        w = csv.DictWriter(sys.stdout, fieldnames=rows[0].keys() if rows else [])
        w.writeheader()
        w.writerows(rows)
    if args.verbose:
        print(f"{len(rows)} rows", file=sys.stderr)


if __name__ == "__main__":
    main()
