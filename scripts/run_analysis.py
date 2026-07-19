"""
Loads the RavenStack CSVs into an in-memory DuckDB database, runs every .sql
file in sql/ against it, and writes each query's real output to results/.

A .sql file normally holds one query and produces one results/<stem>.csv.
A file can also be split into several named result blocks with a marker
line: `-- >>> block_name`. Each block after a marker becomes its own
results/<stem>__<block_name>.csv. This is used where one business question
needs two side-by-side tables (e.g. a funnel plus a churn correlation).

Run from the project root: .venv/bin/python scripts/run_analysis.py
"""

import re
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data" / "raw"
SQL_DIR = ROOT / "sql"
RESULTS_DIR = ROOT / "results"

TABLES = {
    "accounts": "ravenstack_accounts.csv",
    "subscriptions": "ravenstack_subscriptions.csv",
    "feature_usage": "ravenstack_feature_usage.csv",
    "support_tickets": "ravenstack_support_tickets.csv",
    "churn_events": "ravenstack_churn_events.csv",
}

BLOCK_MARKER = re.compile(r"^--\s*>>>\s*(\w+)\s*$", re.MULTILINE)


def load_tables(con: duckdb.DuckDBPyConnection) -> None:
    for table, filename in TABLES.items():
        path = DATA_DIR / filename
        con.execute(f"CREATE TABLE {table} AS SELECT * FROM read_csv_auto('{path.as_posix()}')")


def split_blocks(sql_text: str):
    """Split a .sql file into (name, query_text) pairs using >>> markers.
    If no marker is present, the whole file is one block named after the file."""
    matches = list(BLOCK_MARKER.finditer(sql_text))
    if not matches:
        return [(None, sql_text)]

    blocks = []
    for i, m in enumerate(matches):
        name = m.group(1)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(sql_text)
        blocks.append((name, sql_text[start:end]))
    return blocks


def run_file(con: duckdb.DuckDBPyConnection, sql_path: Path) -> None:
    sql_text = sql_path.read_text()
    stem = sql_path.stem
    for name, query in split_blocks(sql_text):
        query = query.strip()
        if not query:
            continue
        out_name = stem if name is None else f"{stem}__{name}"
        df = con.execute(query).fetchdf()
        out_path = RESULTS_DIR / f"{out_name}.csv"
        df.to_csv(out_path, index=False)
        print(f"  {sql_path.name} -> {out_path.relative_to(ROOT)} ({len(df)} rows)")


def main() -> None:
    RESULTS_DIR.mkdir(exist_ok=True)
    con = duckdb.connect()
    load_tables(con)

    row_counts = con.execute(
        "SELECT 'accounts', count(*) FROM accounts "
        "UNION ALL SELECT 'subscriptions', count(*) FROM subscriptions "
        "UNION ALL SELECT 'feature_usage', count(*) FROM feature_usage "
        "UNION ALL SELECT 'support_tickets', count(*) FROM support_tickets "
        "UNION ALL SELECT 'churn_events', count(*) FROM churn_events"
    ).fetchall()
    print("Loaded tables:")
    for name, count in row_counts:
        print(f"  {name}: {count} rows")

    sql_files = sorted(SQL_DIR.glob("*.sql"))
    print(f"\nRunning {len(sql_files)} SQL files:")
    for sql_path in sql_files:
        run_file(con, sql_path)

    con.close()
    print("\nDone.")


if __name__ == "__main__":
    main()
