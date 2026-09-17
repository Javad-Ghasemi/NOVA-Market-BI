"""
NOVA Market BI
Olist -> SQL Server staging ingestion
Target: stg.orders
"""

from pathlib import Path
import os
import pandas as pd
from sqlalchemy import create_engine, text

PROJECT_ROOT = Path(r"D:\NOVA-Market-BI")
SOURCE_FILE = PROJECT_ROOT / "01-Data" / "raw" / "olist" / "olist_orders_dataset.csv"

SERVER = r"GHASEMI\BOURSEDW"
DATABASE = "NOVA_Market"

CONNECTION_STRING = os.getenv("NOVA_SQLALCHEMY_URL")

if not CONNECTION_STRING:
    raise RuntimeError(
        "Environment variable NOVA_SQLALCHEMY_URL is not set."
    )

EXPECTED_COLUMNS = [
    "order_id",
    "customer_id",
    "order_status",
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]

DATETIME_COLUMNS = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
]


def main():
    if not SOURCE_FILE.exists():
        raise FileNotFoundError(f"Source file not found: {SOURCE_FILE}")

    df = pd.read_csv(SOURCE_FILE)

    if list(df.columns) != EXPECTED_COLUMNS:
        raise ValueError(
            f"Unexpected columns.\nExpected: {EXPECTED_COLUMNS}\nFound: {list(df.columns)}"
        )

    for column in DATETIME_COLUMNS:
        df[column] = pd.to_datetime(df[column], errors="coerce")

    df["order_estimated_delivery_date"] = pd.to_datetime(
        df["order_estimated_delivery_date"], errors="coerce"
    ).dt.date

    if df["order_id"].isna().any():
        raise ValueError("order_id contains NULL values.")

    if df["customer_id"].isna().any():
        raise ValueError("customer_id contains NULL values.")

    if df["order_id"].duplicated().any():
        raise ValueError("Duplicate order_id values detected.")

    engine = create_engine(CONNECTION_STRING, fast_executemany=True)

    with engine.begin() as connection:
        connection.execute(text("TRUNCATE TABLE stg.orders"))
        df.to_sql(
            "orders",
            connection,
            schema="stg",
            if_exists="append",
            index=False,
            chunksize=5000,
        )

    with engine.connect() as connection:
        loaded = connection.execute(
            text("SELECT COUNT(*) FROM stg.orders")
        ).scalar_one()

    print(f"Source rows : {len(df):,}")
    print(f"Loaded rows : {loaded:,}")

    if loaded != len(df):
        raise RuntimeError("Row-count mismatch.")

    print("STATUS: LOAD PASSED")


if __name__ == "__main__":
    main()
