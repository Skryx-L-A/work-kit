# csvtool

Small helper that prints rows of a CSV file.

## Usage

```
python csvtool.py --input data.csv --limit 5 --format json
```

- `--input FILE`: CSV file to read (required).
- `--limit N`: maximum number of rows, default 10.
- `--format csv|json`: output format, default csv.
- `--verbose`: print the row count to stderr.
