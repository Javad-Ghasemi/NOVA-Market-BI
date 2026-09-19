from pathlib import Path
import sys

import pandas as pd
from sqlalchemy import text

from ingestion.olist_config import OLIST_TABLES
from utilities.db import get_engine


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW_DATA_DIR = PROJECT_ROOT / "01-Data" / "raw" / "olist"


def load_table(dataset_name: str) -> None:
    if dataset_name not in OLIST_TABLES:
        available = ", ".join(OLIST_TABLES.keys())
        raise ValueError(
            f"Unknown dataset: {dataset_name}. "
            f"Available datasets: {available}"
        )

    config = OLIST_TABLES[dataset_name]

    file_path = RAW_DATA_DIR / config["file_name"]
    schema = config["schema"]
    table = config["table"]
    expected_columns = config["expected_columns"]
    key_columns = config["key_columns"]

    if not file_path.exists():
        raise FileNotFoundError(
            f"Source file not found: {file_path}"
        )

    print(f"Dataset      : {dataset_name}")
    print(f"Source file  : {file_path.name}")
    print(f"Target table : {schema}.{table}")

    # Read source as text first.
    # Data type conversions are handled explicitly below.
    df = pd.read_csv(
        file_path,
        dtype=str,
    )

    # Validate source structure
    actual_columns = list(df.columns)

    if actual_columns != expected_columns:
        raise ValueError(
            "Source columns do not match expected metadata.\n"
            f"Expected: {expected_columns}\n"
            f"Actual  : {actual_columns}"
        )

    # Datetime conversions
    for column in config.get("datetime_columns", []):
        df[column] = pd.to_datetime(
            df[column],
            errors="raise",
        )

    # Date-only conversions
    for column in config.get("date_columns", []):
        df[column] = pd.to_datetime(
            df[column],
            errors="raise",
        ).dt.date

    # Integer conversions
    for column in config.get("integer_columns", []):
        df[column] = pd.to_numeric(
            df[column],
            errors="raise",
        ).astype("Int64")

    # Decimal / numeric conversions
    for column in config.get("decimal_columns", []):
        df[column] = pd.to_numeric(
            df[column],
            errors="raise",
        )

    # Validate business/source keys
    if df[key_columns].isnull().any().any():
        raise ValueError(
            f"NULL value found in key columns: {key_columns}"
        )

    duplicate_count = df.duplicated(
        subset=key_columns
    ).sum()

    if duplicate_count > 0:
        raise ValueError(
            f"Duplicate key rows found: {duplicate_count:,}"
        )

    source_rows = len(df)

    engine = get_engine()

    try:
        # TRUNCATE + LOAD run inside one transaction.
        with engine.begin() as connection:
            connection.execute(
                text(f"TRUNCATE TABLE [{schema}].[{table}]")
            )

            df.to_sql(
                name=table,
                schema=schema,
                con=connection,
                if_exists="append",
                index=False,
                chunksize=5000,
            )

        # Validate loaded row count
        with engine.connect() as connection:
            loaded_rows = connection.execute(
                text(
                    f"SELECT COUNT(*) "
                    f"FROM [{schema}].[{table}]"
                )
            ).scalar_one()

    finally:
        engine.dispose()

    print(f"Source rows  : {source_rows:,}")
    print(f"Loaded rows  : {loaded_rows:,}")

    if source_rows != loaded_rows:
        raise RuntimeError(
            "Row count mismatch after load."
        )

    print("STATUS       : LOAD PASSED")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(
            "Usage: python load_olist_table.py <dataset_name>"
        )

    load_table(sys.argv[1])