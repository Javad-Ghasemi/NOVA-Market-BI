# NOVA Market BI — Developer Runbook

This runbook contains the main development, execution, validation, troubleshooting, and Git commands used in the NOVA Market BI project.

---

## 1. Project Root

Move to the project root before running project commands.

```powershell
cd D:\NOVA-Market-BI
```

---

## 2. Activate the Python Virtual Environment

```powershell
.\.venv\Scripts\Activate.ps1
```

Expected terminal prefix:

```text
(.venv) PS D:\NOVA-Market-BI>
```

---

## 3. Configure PYTHONPATH

This allows Python to import modules from `03-Python`.

```powershell
$env:PYTHONPATH="$PWD\03-Python"
```

This variable applies to the current PowerShell session.

---

## 4. Configure the SQL Server Connection

The real connection string must not be hard-coded in source code.

```powershell
$env:NOVA_SQLALCHEMY_URL="<LOCAL_SQLALCHEMY_CONNECTION_STRING>"
```

Example format:

```text
mssql+pyodbc://@SERVER_NAME:PORT/NOVA_Market?trusted_connection=yes&driver=ODBC+Driver+17+for+SQL+Server
```

Never commit the real local connection string, credentials, or passwords to GitHub.

The repository contains `.env.example` only as a public template.

---

## 5. Check the Active SQL Connection Variable

```powershell
echo $env:NOVA_SQLALCHEMY_URL
```

If nothing is returned, configure the variable again before running ingestion.

---

## 6. Test Python → SQL Server Connectivity

```powershell
python -c "from utilities.db import get_engine; from sqlalchemy import text; e=get_engine(); c=e.connect(); print(c.execute(text('SELECT @@SERVERNAME, DB_NAME()')).fetchone()); c.close(); e.dispose()"
```

The result should identify the SQL Server instance and:

```text
NOVA_Market
```

---

## 7. Check Python Package Versions

```powershell
python -c "import pandas, sqlalchemy, pyodbc; print('pandas=' + pandas.__version__); print('SQLAlchemy=' + sqlalchemy.__version__); print('pyodbc=' + pyodbc.version)"
```

Current tested versions:

```text
pandas=3.0.5
SQLAlchemy=2.0.54
pyodbc=5.3.0
```

---

## 8. Install Project Dependencies

```powershell
pip install -r requirements.txt
```

---

# 9. Olist Staging Ingestion

##  Generic Loader

General syntax:

```powershell
python .\03-Python\ingestion\load_olist_table.py <dataset_name>
```

The generic loader performs:

```text
Read CSV
→ Validate Columns
→ Convert Data Types
→ Validate Keys
→ Detect Duplicates
→ TRUNCATE Target
→ Load SQL Server
→ Validate Row Count
```

---

##  Load Orders

```powershell
python .\03-Python\ingestion\load_olist_table.py orders
```

Expected:

```text
Target: stg.orders
Rows:   99,441
```
Run the orders data quality validation:

```text
02-SQL/04-DQ/001-Validate-stg-orders.sql
```

---

##  Load Order Items

```powershell
python .\03-Python\ingestion\load_olist_table.py order_items
```

Expected:

```text
Target: stg.order_items
Rows:   112,650
```

Source grain:

```text
1 row = 1 order item
```

Source key:

```text
(order_id, order_item_id)
```
Run the order_items data quality validation:

```text
02-SQL/04-DQ/002-Validate-stg-order-items.sql
```
---

##  Load Products

```powershell
python .\03-Python\ingestion\load_olist_table.py products
```

Expected:

```text
Target: stg.products
Rows:   32,951
```
Run the products data quality validation:

```text
02-SQL/04-DQ/003-Validate-stg-products.sql
```

---

##  Load Category Translation

```powershell
python .\03-Python\ingestion\load_olist_table.py category_translation
```

Expected:

```text
Target: stg.category_translation
Rows:   71
```
Run the category_translation data quality validation:

```text
02-SQL/04-DQ/004-Validate-stg-category-translation.sql
```
---

##  Load Customers

```powershell
python .\03-Python\ingestion\load_olist_table.py customers
```

Expected:

```text
Target: stg.customers
Rows:   99,441
```
Run the customers data quality validation:

```text
02-SQL/04-DQ/005-Validate-stg-customers.sql
```
---

##  Load Sellers

```powershell
python .\03-Python\ingestion\load_olist_table.py sellers
```

Expected:

```text
Target: stg.sellers
Rows:   3,095
```
Run the sellers data quality validation:

```text
02-SQL/04-DQ/006-Validate-stg-sellers.sql
```
---
## Load Payments

Run the payments staging load:

```powershell
python .\03-Python\ingestion\load_olist_table.py payments
```
Expected:

```text
Target: stg.payments
rows: 103,886
```
Run the payments data quality validation:

```text
02-SQL/04-DQ/007-Validate-stg-payments.sql
```
---

## Load Reviews

Run the reviews staging load:

```powershell
python .\03-Python\ingestion\load_olist_table.py reviews
```

Expected:

```text
Target: stg.reviews
Rows: 99,224
```

Run the reviews data quality validation:

```text
02-SQL/04-DQ/008-Validate-stg-reviews.sql
```

---

## Load Geolocation

Run the geolocation staging load:

```powershell
python .\03-Python\ingestion\load_olist_table.py geolocation
```

Expected:

```text
Target: stg.geolocation
Rows: 1,000,163
```

Run the geolocation data quality validation:

```text
02-SQL/04-DQ/009-Validate-stg-geolocation.sql
```

Important source characteristics:

- Distinct ZIP prefixes: 19,015
- Exact duplicate source rows: 261,831
- ZIP prefixes with multiple states: 8
- ZIP prefixes with multiple city labels: 8,555
- No deduplication is applied in staging
- Geolocation does not expose a reliable row-level source key

Planned DWH geography grain:

```text
1 row per ZIP prefix
```
---
## Final Staging Validation

Run the pipeline-level staging completeness validation:

```text
02-SQL/04-DQ/010-Validate-staging-completeness.sql
```

Expected result:

```text
All 9 staging datasets = PASS
STAGING VALIDATION PASSED
```

This smoke test validates the expected row counts for all Olist staging datasets. Detailed data-quality rules remain in validation scripts 001 through 009.
---
## Build DimDate

Create and populate the bilingual Gregorian / Persian date dimension:

```text
02-SQL/03-DWH/001-Create-DimDate.sql
```

The script creates:

```text
dwh.fn_GregorianToPersianDate
dwh.DimDate
```

Expected validation:

```text
Rows: 1,828
Gregorian range: 2016-01-01 to 2020-12-31
Known Nowruz conversion tests: 5 PASS
MissingSourceDatesInDimDate: 0
```

The dimension contains both Gregorian and Persian calendar attributes while all fact tables use the same Gregorian-based `DateKey`.

Important source characteristic:

Four order-item source rows across three orders contain `shipping_limit_date` values in 2020, approximately 1,052 to 1,056 days after their 2017 purchase dates. These source values are preserved and are treated as temporal data-quality anomalies rather than corrected values.
---
## Build Conformed Geography

Build the conformed ZIP-level geography layer:

```text
02-SQL/02-Conformed/002-Build-conformed-geography.sql
```

Run the geography data-quality validation:

```text
02-SQL/04-DQ/011-Validate-conformed-geography.sql
```

Expected validation:

```text
Rows: 19,177
Distinct ZIP prefixes: 19,177
Required ZIPs missing: 0

Missing from geolocation: 162
State conflicts: 8
State ambiguities: 0

City ambiguities: 20
Cities resolved by customer/seller reference data: 12

ZIPs without coordinates: 162

CONFORMED GEOGRAPHY VALIDATION PASSED
```

Design notes:

- Grain is one row per ZIP code prefix.
- All ZIPs referenced by customers or sellers are included even when absent from the geolocation source.
- Missing geolocation ZIPs use customer/seller City and State values when they are consistent.
- Latitude and longitude are never fabricated.
- Representative coordinates use the median of distinct source coordinate pairs.
- Conflicting State values are resolved using source frequency and customer/seller reference support.
- Ambiguous City values are not selected arbitrarily; unresolved City values remain NULL and are flagged.
---
## Load DimGeography

Create the DimGeography target table:

```text
02-SQL/03-DWH/002-Create-DimGeography.sql
```

The table is created empty. Population is performed by SSIS.

SSIS package:

```text
04-ETL/SSIS/NOVA_Market_ETL/01-Load-DimGeography.dtsx
```

ETL flow:

```text
conformed.Geography
        ↓
SSIS OLE DB Source
        ↓
dwh.DimGeography
```

The package first prepares the dimension by:

- truncating `dwh.DimGeography`
- inserting the Unknown member with `GeographyKey = 0`

The SSIS Data Flow then loads the 19,177 business geography rows. `GeographyKey` is generated by SQL Server as an identity surrogate key.

Expected load result:

```text
Total rows: 19,178
Business rows: 19,177
Unknown members: 1
Minimum GeographyKey: 0
Maximum GeographyKey: 19,177
```

Run the DimGeography data-quality validation:

```text
02-SQL/04-DQ/012-Validate-DimGeography.sql
```

Expected:

```text
Missing conformed ZIPs: 0
Source rows missing or different in DWH: 0
DWH rows missing or different in source: 0

DIM GEOGRAPHY VALIDATION PASSED
```
---
## Build Conformed Customer

Build the customer conformance layer:

```text
02-SQL/02-Conformed/003-Build-conformed-customer.sql
```

Grain:

```text
1 row per customer_unique_id
```

Representative customer geography is taken from the latest purchase.

If multiple orders share the same latest purchase timestamp, `order_id` is used only as a deterministic technical tie-breaker. Data-quality analysis confirmed that these timestamp ties do not contain conflicting ZIP, City, or State values.

Expected characteristics:

```text
Customers: 96,096
Returning customers: 2,997
Customers with multiple ZIPs: 250
Customers with multiple states: 39
Customers with multiple cities: 122
Latest purchase timestamp ties: 269
Latest-tie geography conflicts: 0
Customer ZIPs missing from conformed geography: 0
```

Run the conformed customer data-quality validation:

```text
02-SQL/04-DQ/013-Validate-conformed-customer.sql
```

Expected:

```text
CONFORMED CUSTOMER VALIDATION PASSED
```
---
# Metadata Validation

## 10. Inspect Dataset Metadata

General pattern:

```powershell
python -c "from ingestion.olist_config import OLIST_TABLES; c=OLIST_TABLES['<dataset_name>']; print(c)"
```

Example:

```powershell
python -c "from ingestion.olist_config import OLIST_TABLES; c=OLIST_TABLES['customers']; print(c['file_name']); print(c['schema'] + '.' + c['table']); print(c['key_columns']); print(c['expected_columns'])"
```

Metadata is stored in:

```text
03-Python\ingestion\olist_config.py
```

---

# Git Workflow

## 11. Check Git Status

```powershell
git status
```

Short version:

```powershell
git status --short
```

Common status codes:

```text
M  = Modified
?? = Untracked
D  = Deleted
```

---

## 12. Review File Changes

```powershell
git diff -- <file-path>
```

Example:

```powershell
git diff -- .\03-Python\ingestion\olist_config.py
```

---

## 13. Stage a File

```powershell
git add <file-path>
```

Example:

```powershell
git add .\03-Python\ingestion\olist_config.py
```

---

## 14. Stage All Changes

```powershell
git add -A
```

Use this only after reviewing:

```powershell
git status
```

---

## 15. Commit Changes

```powershell
git commit -m "<commit-message>"
```

Examples:

```powershell
git commit -m "feat: add customers staging pipeline and data quality checks"
```

Commit prefixes used in this project:

```text
feat:     new functionality
fix:      bug fix
refactor: structural improvement without changing intended behavior
docs:     documentation
test:     testing or data quality
chore:    dependencies or maintenance
```

---

## 16. Push to GitHub

```powershell
git push origin main
```

---

## 17. Standard Git Workflow

```powershell
git status
git add <file-path>
git commit -m "<commit-message>"
git push origin main
git status
```

Expected final state:

```text
nothing to commit, working tree clean
```

---

## 18. Check the Latest Commit

```powershell
git log -1 --oneline
```

---

## 19. Restore an Unwanted Local Change

Use only when the local change is definitely not needed.

```powershell
git restore <file-path>
```

Example:

```powershell
git restore .\02-SQL\04-DQ\002-Validate-stg-order-items.sql
```

---

# PowerShell Utilities

## 20. View Current Session History

```powershell
Get-History
```

---

## 21. Find the Persistent PowerShell History File

```powershell
(Get-PSReadLineOption).HistorySavePath
```

---

## 22. Search Across Project Files

```powershell
Get-ChildItem -Recurse -File | Select-String -Pattern "<search-text>"
```

Example:

```powershell
Get-ChildItem -Recurse -File | Select-String -Pattern "orphan" -CaseSensitive:$false
```

---

## 23. Check Whether a File Exists

```powershell
Test-Path <file-path>
```

Example:

```powershell
Test-Path .\02-SQL\04-DQ\003-Validate-stg-products.sql
```

---

# SQL Server Troubleshooting

## 24. Confirm SQL Server Instance Information

Run in SSMS:

```sql
SELECT
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('InstanceName') AS InstanceName,
    SERVERPROPERTY('IsLocalDB') AS IsLocalDB;
```

---

## 25. TCP/IP Requirement

Python / ODBC connectivity requires TCP/IP to be enabled.

Configuration path:

```text
SQL Server Configuration Manager
→ SQL Server Network Configuration
→ Protocols for BOURSEDW
→ TCP/IP
```

After changing network configuration, restart:

```text
SQL Server (BOURSEDW)
```

---

## 26. Dynamic Port Note

The current development environment uses a SQL Server TCP port.

A dynamic port may change after SQL Server configuration changes.

Therefore, always provide the real connection string through:

```text
NOVA_SQLALCHEMY_URL
```

Do not hard-code the local server or port in Python scripts.

---

# Project Architecture Rules

## 27. Staging Architecture

```text
Olist CSV
    ↓
Python Ingestion
    ↓
SQL Server / stg
    ↓
Data Quality
    ↓
SSIS / Transformation
    ↓
DWH
    ↓
Power BI
```

The staging layer should preserve source data as closely as possible.

Do not apply unsupported business corrections or synthetic values in staging.

---

## 28. Data Quality Standard

Each staging dataset should be reviewed for:

```text
Row Count
Key Uniqueness
NULL Values
Blank Values
Referential Integrity
Numeric Validity
Negative Values
Reasonable Ranges
Coverage Gaps
Known Source Issues
```

Known source issues must be documented rather than silently corrected.

---

## 29. Orders Modeling

Source:

```text
stg.orders
```

Grain:

```text
1 row = 1 order
```

Future fact:

```text
FactOrder
```

Suitable metrics include:

```text
Order Count
Order Status
Canceled Orders
Delivered Orders
Delivery Duration
On-Time Delivery
```

---

## 30. Order Items Modeling

Source:

```text
stg.order_items
```

Grain:

```text
1 row = 1 order item
```

Future fact:

```text
FactOrderItem
```

Suitable metrics include:

```text
Item Sales
Product Sales
Category Sales
Seller Sales
Freight
Item Count
```

---

## 31. Customer Modeling

Source-level key:

```text
customer_id
```

Analytical customer identity:

```text
customer_unique_id
```

Known source facts:

```text
Customer rows                 = 99,441
Distinct customer_unique_id   = 96,096
Returning customer identities = 2,997
```

Future `DimCustomer` grain:

```text
1 row = 1 customer_unique_id
```

---

## 32. Seller Modeling

Source:

```text
stg.sellers
```

Future dimension:

```text
DimSeller
```

A seller is not a physical retail branch.

Do not represent Olist sellers as branches.

---

## 33. Product Modeling

The source does not contain a reliable human-readable product name.

Do not create synthetic product names.

Product analysis should use:

```text
product_id
product category
seller
category translation
```

Future dimension:

```text
DimProduct
```

---

## 34. Product Category Localization

The source category labels are Portuguese.

Staging preserves the original Portuguese values.

Future localization model:

```text
CategoryNameSourcePT
CategoryNameEN
CategoryNameFA
TranslationStatus
```

English source:

```text
product_category_name_translation.csv
```

Known coverage:

```text
Non-null product categories = 73
Source English translations = 71
Missing translations        = 2
```

Missing categories:

```text
pc_gamer
portateis_cozinha_e_preparadores_de_alimentos
```

Affected products:

```text
pc_gamer                                      = 3
portateis_cozinha_e_preparadores_de_alimentos = 10
Total                                         = 13
```

Curated translations must be added later in the DWH/localization layer, not in staging.

---

## 35. Known Product Quality Issue

Four products have:

```text
product_weight_g = 0
```

The source values are preserved.

Do not invent replacement weights.

A DWH data-quality flag may be added later.

---

## 36. Geography Modeling

The Olist geolocation dataset contains more than one million rows.

Do not directly join it to facts using only ZIP prefix without first controlling the grain.

Future target grain:

```text
1 row = 1 zip_code_prefix
```

Future dimension:

```text
DimGeography
```

Latitude and longitude will require controlled aggregation or representative coordinates.

---

## 37. Fact Architecture

Planned fact tables:

```text
FactOrder
FactOrderItem
FactPayment
FactReview
```

Grains:

```text
FactOrder      = 1 row per order
FactOrderItem  = 1 row per order item
FactPayment    = 1 row per payment record
FactReview     = 1 row per review record
```

---

## 38. Fan-Out Prevention

Known source facts:

```text
Orders with multiple payment rows = 2,961
Orders with multiple review rows  = 547
```

Do not directly combine:

```text
OrderItems
JOIN Payments
JOIN Reviews
```

into one sales fact.

This can multiply sales values.

---

## 39. Financial KPI Rule

Olist does not provide reliable product cost / COGS.

Do not create unsupported KPIs such as:

```text
Gross Profit
Net Profit
Profit Margin
COGS
```

Source-supported measures include:

```text
Item Price
Freight Value
Payment Value
Order Count
Item Count
Average Order Value
Category Sales
Seller Sales
Delivery Metrics
```

---

## 40. Sales Definition

In Olist:

```text
price
```

represents the item price.

```text
freight_value
```

represents shipping/freight.

Current analytical definition:

```text
ItemSalesAmount = price
```

Freight should be analyzed separately.

---

## 41. Raw Data Git Rule

Raw and generated data must not be committed.

Ignored paths include:

```text
01-Data/raw/*
01-Data/staging/*
01-Data/processed/*
```

Secrets are also ignored:

```text
.env
.env.*
```

Public template:

```text
.env.example
```

---

## 42. Python Cache Files

Python may create:

```text
__pycache__
```

and files such as:

```text
olist_config.cpython-312.pyc
```

These are normal and should not be committed.

Relevant `.gitignore` rules:

```text
__pycache__/
*.py[cod]
```

---

## 43. Source Integrity Principle

Olist is the real transactional source.

NOVA is the business intelligence and data warehouse layer.

Do not mix old synthetic NOVA transactions with real Olist facts.

Do not present Brazilian Olist transactions as Iranian retail transactions.

The dashboard interface may be Persian and English while the source remains Brazilian e-commerce data.

---

## 44. Date Rule

Actual order-purchase range:

```text
2016-09-04 21:15:19
to
2018-10-17 17:30:18
```

Do not artificially expand the source to five years.

Jalali date attributes may later be added to `DimDate` without changing source dates.

---

## 45. SQL Alias Style

For aliases that may conflict with T-SQL keywords, use brackets.

Preferred:

```sql
SELECT COUNT(*) AS [RowCount]
FROM stg.orders;
```

Avoid:

```sql
AS 'RowCount'
```

---

## 46. Standard Dataset Workflow

Each dataset should follow:

```text
1. Design staging table
2. Create staging table
3. Validate SQL structure
4. Add metadata to olist_config.py
5. Validate metadata
6. Run generic loader
7. Validate row count
8. Run DQ checks
9. Investigate known issues
10. Document findings
11. Review git status
12. Review unexpected diffs
13. Commit
14. Push
15. Confirm clean working tree
```

---

## 47. Development Principle

```text
Design
    ↓
Create
    ↓
Load
    ↓
Validate
    ↓
Document
    ↓
Commit
    ↓
Push
```

Only validated work should be committed to `main`.

---

## 48. Final Git Check

```powershell
git status
```

Expected:

```text
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
```

---

## 49. Runbook Maintenance

Add a command to this runbook when it is:

```text
Reusable
Required for setup
Part of the pipeline
Important for troubleshooting
Important for project maintenance
```

Do not add temporary commands containing secrets.

