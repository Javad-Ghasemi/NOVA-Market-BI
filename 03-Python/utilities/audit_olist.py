from __future__ import annotations

from pathlib import Path
import pandas as pd


# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------

PROJECT_ROOT = Path(r"D:\NOVA-Market-BI")
RAW_PATH = PROJECT_ROOT / "01-Data" / "raw" / "olist"

REPORT_DIR = PROJECT_ROOT / "00-Project" / "Quality"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

REPORT_PATH = REPORT_DIR / "Olist-Data-Quality-Report.md"


FILES = {
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "products": "olist_products_dataset.csv",
    "customers": "olist_customers_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "payments": "olist_order_payments_dataset.csv",
    "reviews": "olist_order_reviews_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

def load_csv(filename: str) -> pd.DataFrame:
    path = RAW_PATH / filename

    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    return pd.read_csv(path)


def duplicate_count(df: pd.DataFrame, columns: list[str]) -> int:
    return int(df.duplicated(subset=columns).sum())


def orphan_count(
    child_df: pd.DataFrame,
    child_column: str,
    parent_df: pd.DataFrame,
    parent_column: str,
) -> int:
    parent_values = set(parent_df[parent_column].dropna().astype(str))
    child_values = child_df[child_column].dropna().astype(str)

    return int((~child_values.isin(parent_values)).sum())


def payment_multiplicity(orders: pd.DataFrame, payments: pd.DataFrame) -> tuple[int, int]:
    counts = payments.groupby("order_id").size()

    multi_order_count = int((counts > 1).sum())
    max_rows = int(counts.max()) if not counts.empty else 0

    return multi_order_count, max_rows


def review_multiplicity(reviews: pd.DataFrame) -> tuple[int, int]:
    counts = reviews.groupby("order_id").size()

    multi_order_count = int((counts > 1).sum())
    max_rows = int(counts.max()) if not counts.empty else 0

    return multi_order_count, max_rows


# ---------------------------------------------------------
# Load
# ---------------------------------------------------------

data = {}

for name, filename in FILES.items():
    data[name] = load_csv(filename)


orders = data["orders"]
order_items = data["order_items"]
products = data["products"]
customers = data["customers"]
sellers = data["sellers"]
payments = data["payments"]
reviews = data["reviews"]
geolocation = data["geolocation"]
category_translation = data["category_translation"]


# ---------------------------------------------------------
# Basic statistics
# ---------------------------------------------------------

row_counts = {
    name: len(df)
    for name, df in data.items()
}

order_status_counts = (
    orders["order_status"]
    .value_counts(dropna=False)
    .to_dict()
)

delivered_orders = orders.loc[
    orders["order_status"].eq("delivered"),
    "order_id"
]

delivered_items = order_items[
    order_items["order_id"].isin(delivered_orders)
]

purchase_dates = pd.to_datetime(
    orders["order_purchase_timestamp"],
    errors="coerce"
)

purchase_min = purchase_dates.min()
purchase_max = purchase_dates.max()


# ---------------------------------------------------------
# Quality checks
# ---------------------------------------------------------

checks = {}

# Primary / business keys
checks["Duplicate order_id"] = duplicate_count(
    orders,
    ["order_id"]
)

checks["Duplicate customer_id"] = duplicate_count(
    customers,
    ["customer_id"]
)

checks["Duplicate seller_id"] = duplicate_count(
    sellers,
    ["seller_id"]
)

checks["Duplicate product_id"] = duplicate_count(
    products,
    ["product_id"]
)

checks["Duplicate order_id + order_item_id"] = duplicate_count(
    order_items,
    ["order_id", "order_item_id"]
)

# Foreign keys
checks["Orphan order_items -> orders"] = orphan_count(
    order_items,
    "order_id",
    orders,
    "order_id",
)

checks["Orphan order_items -> products"] = orphan_count(
    order_items,
    "product_id",
    products,
    "product_id",
)

checks["Orphan order_items -> sellers"] = orphan_count(
    order_items,
    "seller_id",
    sellers,
    "seller_id",
)

checks["Orphan payments -> orders"] = orphan_count(
    payments,
    "order_id",
    orders,
    "order_id",
)

checks["Orphan reviews -> orders"] = orphan_count(
    reviews,
    "order_id",
    orders,
    "order_id",
)

# Product quality
checks["Products with missing category"] = int(
    products["product_category_name"].isna().sum()
)

# Translation coverage
translated_categories = set(
    category_translation["product_category_name"]
    .dropna()
    .astype(str)
)

source_categories = set(
    products["product_category_name"]
    .dropna()
    .astype(str)
)

missing_translation_categories = sorted(
    source_categories - translated_categories
)

# Payment multiplicity
payment_multi_orders, payment_max_rows = payment_multiplicity(
    orders,
    payments,
)

# Review multiplicity
review_multi_orders, review_max_rows = review_multiplicity(
    reviews,
)

# Null counts for important fields
important_nulls = {
    "orders.order_purchase_timestamp":
        int(orders["order_purchase_timestamp"].isna().sum()),

    "orders.customer_id":
        int(orders["customer_id"].isna().sum()),

    "order_items.order_id":
        int(order_items["order_id"].isna().sum()),

    "order_items.product_id":
        int(order_items["product_id"].isna().sum()),

    "order_items.seller_id":
        int(order_items["seller_id"].isna().sum()),

    "products.product_id":
        int(products["product_id"].isna().sum()),
}


# ---------------------------------------------------------
# Payment vs item value diagnostic
# ---------------------------------------------------------

item_totals = (
    order_items
    .groupby("order_id", as_index=False)["price"]
    .sum()
    .rename(columns={"price": "item_total"})
)

payment_totals = (
    payments
    .groupby("order_id", as_index=False)["payment_value"]
    .sum()
    .rename(columns={"payment_value": "payment_total"})
)

comparison = item_totals.merge(
    payment_totals,
    on="order_id",
    how="outer",
)

comparison["item_total"] = comparison["item_total"].fillna(0)
comparison["payment_total"] = comparison["payment_total"].fillna(0)

payment_mismatch_count = int(
    (comparison["item_total"].round(2) != comparison["payment_total"].round(2)).sum()
)


# ---------------------------------------------------------
# Generate Markdown Report
# ---------------------------------------------------------

report = []

report.append("# Olist Data Quality Report\n")

report.append("## Dataset Inventory\n")

report.append("| Dataset | Rows |")
report.append("|---|---:|")

for name, count in row_counts.items():
    report.append(f"| {name} | {count:,} |")

report.append("")

report.append("## Source Time Range\n")
report.append(
    f"- Minimum order purchase timestamp: `{purchase_min}`"
)
report.append(
    f"- Maximum order purchase timestamp: `{purchase_max}`"
)
report.append("")

report.append("## Order Status Distribution\n")
report.append("| Status | Orders |")
report.append("|---|---:|")

for status, count in order_status_counts.items():
    report.append(f"| {status} | {count:,} |")

report.append("")

report.append("## Key Data Quality Checks\n")
report.append("| Check | Result |")
report.append("|---|---:|")

for check_name, result in checks.items():
    report.append(f"| {check_name} | {result:,} |")

report.append("")

report.append("## Payment Multiplicity\n")
report.append(
    f"- Orders with more than one payment row: `{payment_multi_orders:,}`"
)
report.append(
    f"- Maximum payment rows for one order: `{payment_max_rows:,}`"
)
report.append("")

report.append("## Review Multiplicity\n")
report.append(
    f"- Orders with more than one review row: `{review_multi_orders:,}`"
)
report.append(
    f"- Maximum review rows for one order: `{review_max_rows:,}`"
)
report.append("")

report.append("## Important Null Checks\n")
report.append("| Field | Null Rows |")
report.append("|---|---:|")

for field, count in important_nulls.items():
    report.append(f"| {field} | {count:,} |")

report.append("")

report.append("## Category Translation Coverage\n")
report.append(
    f"- Source categories: `{len(source_categories):,}`"
)
report.append(
    f"- Translated categories: `{len(translated_categories):,}`"
)
report.append(
    f"- Categories without English translation: `{len(missing_translation_categories):,}`"
)

if missing_translation_categories:
    report.append("")
    report.append("### Categories without Translation\n")

    for category in missing_translation_categories:
        report.append(f"- `{category}`")

report.append("")

report.append("## Payment vs Item Value Diagnostic\n")
report.append(
    f"- Orders where summed payment value differs from summed item price: "
    f"`{payment_mismatch_count:,}`"
)
report.append(
    "- This is a diagnostic only. Payment value must not be naively treated "
    "as sales value because payments can include freight and other amounts."
)
report.append("")

report.append("## Delivered Orders\n")
report.append(
    f"- Delivered orders: `{len(delivered_orders):,}`"
)
report.append(
    f"- Delivered order-item rows: `{len(delivered_items):,}`"
)
report.append("")

report.append("## Architectural Findings\n")
report.append("- Olist is the real transaction source for this project.")
report.append("- Seller is not treated as a physical branch.")
report.append("- Olist does not provide native product cost / COGS.")
report.append("- Olist source period is 2016–2018.")
report.append("- Payment and review data remain separate fact domains.")
report.append("- Product orphan records must be handled explicitly during ETL.")
report.append("- No synthetic transactions are introduced as real source data.")
report.append("")

REPORT_PATH.write_text(
    "\n".join(report),
    encoding="utf-8"
)

print("=" * 60)
print("OLIST DATA QUALITY AUDIT COMPLETED")
print("=" * 60)
print(f"Report: {REPORT_PATH}")
print()
print("Dataset row counts:")
for name, count in row_counts.items():
    print(f"  {name:22s}: {count:,}")

print()
print("Important findings:")
print(f"  Orphan order_items -> products: {checks['Orphan order_items -> products']:,}")
print(f"  Products with missing category: {checks['Products with missing category']:,}")
print(f"  Orders with multiple payments: {payment_multi_orders:,}")
print(f"  Orders with multiple reviews: {review_multi_orders:,}")
print(f"  Payment/item total mismatches: {payment_mismatch_count:,}")

print()
print(f"Report written to: {REPORT_PATH}")