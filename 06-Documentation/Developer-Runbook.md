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
## Load DimCustomer

Create the DimCustomer target table:

```text
02-SQL/03-DWH/003-Create-DimCustomer.sql
```

The table is created empty. Population is performed by SSIS.

SSIS package:

```text
04-ETL/SSIS/NOVA_Market_ETL/02-Load-DimCustomer.dtsx
```

ETL flow:

```text
conformed.Customer
        ↓
SSIS OLE DB Source
        ↓
Lookup: dwh.DimGeography
        ↓
dwh.DimCustomer
```

`ZipCodePrefix` is resolved to `RepresentativeGeographyKey` through a full-cache SSIS Lookup against `dwh.DimGeography`.

The package first:

- truncates `dwh.DimCustomer`
- inserts the Unknown member with `CustomerKey = 0`
- loads business customers with SQL Server-generated surrogate keys

Expected load result:

```text
Total rows: 96,097
Business rows: 96,096
Unknown members: 1
Minimum CustomerKey: 0
Maximum CustomerKey: 96,096
```

Run the DimCustomer data-quality validation:

```text
02-SQL/04-DQ/014-Validate-DimCustomer.sql
```

Expected:

```text
Invalid business GeographyKeys: 0
Source rows missing or different in DWH: 0
DWH rows missing or different in source: 0

DIM CUSTOMER VALIDATION PASSED
```

Important modeling note:

`RepresentativeGeographyKey` is a customer-profile attribute based on the latest purchase geography. Historical order geography will be stored separately on FactOrder so earlier orders are not incorrectly attributed to a customer's latest location.
---
## DimSeller ETL

`dwh.DimSeller` is loaded directly from `stg.sellers` through SSIS.

### Grain

One row per source `seller_id`.

The source already contains one unique row per seller, so no separate
`conformed.Seller` entity is required.

### Geography

Seller geography is resolved through `dwh.DimGeography` using
`seller_zip_code_prefix`.

The SSIS package uses a full-cache Lookup and fails the component if a seller
ZIP code cannot be resolved.

Source geography attributes are preserved for lineage:

- `SourceZipCodePrefix`
- `SourceCityName`
- `SourceStateCode`

The canonical reporting geography is represented by `GeographyKey`.

### Geography mismatch flags

Two diagnostic flags are stored in the dimension:

- `CityMismatchFlag`
- `StateMismatchFlag`

These flags identify differences between the raw seller geography attributes
and the canonical ZIP-level geography.

City comparison is normalized by:

- trimming leading and trailing spaces,
- converting to lowercase,
- removing spaces,
- removing hyphens,
- removing apostrophes,
- comparing with `Latin1_General_100_CI_AI` collation.

The accent-insensitive comparison is intentional. For example, values such as
`sao paulo` and `são paulo` are treated as equivalent.

The source values are never overwritten by the canonical values.

### Unknown member

The package creates the standard Unknown member before loading business rows:

- `SellerKey = 0`
- `SellerID = NULL`
- `GeographyKey = 0`
- `SourceCityName = 'Unknown'`
- mismatch flags = `0`

Business surrogate keys are generated by SQL Server identity values.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/03-Load-DimSeller.dtsx`

Control Flow:

`SQL - Prepare DimSeller`
→ `DFT - Load DimSeller`

Data Flow:

`SRC - Sellers`
→ `LKP - Seller Geography`
→ `DER - Seller Geography Flags`
→ `DST - DimSeller`

The city and state mismatch rules are evaluated by SQL Server in the source
query so that the same collation semantics used by the conformed geography
logic are preserved consistently.

### Validation

Validation script:

`02-SQL/04-DQ/015-Validate-DimSeller.sql`

Validated results:

- Source sellers: `3,095`
- Business dimension rows: `3,095`
- Unknown rows: `1`
- Total dimension rows: `3,096`
- City mismatches: `94`
- State mismatches: `35`
- Missing geography keys: `0`
- Invalid geography keys: `0`
- Duplicate Seller IDs: `0`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Final result:

`DIMSELLER VALIDATION PASSED.`
---
## Product Category Conformance and Localization

Product categories are modeled through three distinct layers:

`stg.products` + `stg.category_translation`
→ `conformed.ProductCategory`
→ `meta.ProductCategoryLocalization`
→ `dwh.DimProductCategory`

This separation preserves source lineage while allowing curated Persian labels
for the reporting layer.

### Source profile

The product source contains:

- Product rows: `32,951`
- Products without a source category: `610`
- Distinct non-null source categories: `73`

The Olist category translation source contains:

- Translation rows: `71`
- Distinct source categories translated: `71`
- Null English translations: `0`
- Duplicate English translations: `0`

Two source categories are used by products but do not have an English
translation in the Olist translation file:

- `pc_gamer` — `3` products
- `portateis_cozinha_e_preparadores_de_alimentos` — `10` products

No English translation is fabricated for these categories.

Products whose source category is NULL are not assigned an artificial business
category. They will resolve to the Unknown category member when DimProduct is
loaded.

### Conformed ProductCategory

Build script:

`02-SQL/02-Conformed/004-Build-conformed-product-category.sql`

Grain:

One row per distinct non-null source `product_category_name` used by products.

Columns:

- `SourceCategoryName`
- `EnglishCategoryName`
- `MissingEnglishTranslationFlag`

The source Portuguese category name is preserved exactly as the business key.

The English category name is taken only from the Olist category translation
source. Source-provided spelling and wording are preserved and are not
silently corrected.

For categories that do not have an English translation:

- `EnglishCategoryName = NULL`
- `MissingEnglishTranslationFlag = 1`

Validated results:

- Conformed category rows: `73`
- Missing English translations: `2`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Validation script:

`02-SQL/04-DQ/016-Validate-conformed-product-category.sql`

Final result:

`CONFORMED PRODUCT CATEGORY VALIDATION PASSED.`

### Persian product category localization

Persian names are project-curated localization metadata. They are not part of
the Olist source dataset and are therefore stored separately from the
conformed source representation.

Localization table:

`meta.ProductCategoryLocalization`

Build script:

`02-SQL/05-Metadata/001-Create-product-category-persian-localization.sql`

Grain:

One row per `SourceCategoryName`.

Columns:

- `SourceCategoryName`
- `PersianCategoryName`

Validated localization coverage:

- Conformed categories: `73`
- Persian localization rows: `73`
- Missing Persian names: `0`
- Missing localization rows: `0`
- Orphan localization rows: `0`
- Duplicate localization rows: `0`

The two categories without an Olist English translation still have curated
Persian labels. Their English values remain NULL, so source lineage is not
altered.

Validation script:

`02-SQL/04-DQ/017-Validate-product-category-persian-localization.sql`

Final result:

`PRODUCT CATEGORY PERSIAN LOCALIZATION VALIDATION PASSED.`

### DimProductCategory

DDL script:

`02-SQL/03-DWH/005-Create-DimProductCategory.sql`

Grain:

One row per business product category plus one Unknown member.

Columns:

- `ProductCategoryKey`
- `SourceCategoryName`
- `EnglishCategoryName`
- `PersianCategoryName`
- `MissingEnglishTranslationFlag`
- `MissingPersianLocalizationFlag`

`ProductCategoryKey` is the warehouse surrogate key.

`SourceCategoryName` remains the source business key.

The dimension is intentionally multilingual so Power BI can expose Portuguese,
English, or Persian labels without changing fact relationships.

### Unknown member

The SSIS package creates the standard Unknown member before business rows are
loaded:

- `ProductCategoryKey = 0`
- `SourceCategoryName = NULL`
- `EnglishCategoryName = 'Unknown'`
- `PersianCategoryName = N'نامشخص'`
- `MissingEnglishTranslationFlag = 0`
- `MissingPersianLocalizationFlag = 0`

Products with a NULL source category will later resolve to this member during
DimProduct loading.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/04-Load-DimProductCategory.dtsx`

Control Flow:

`SQL - Prepare DimProductCategory`
→ `DFT - Load DimProductCategory`

Data Flow:

`SRC - Product Categories`
→ `DST - DimProductCategory`

The source query combines:

- `conformed.ProductCategory`
- `meta.ProductCategoryLocalization`

Business surrogate keys are generated by the SQL Server identity column.

### DimProductCategory validation

Validation script:

`02-SQL/04-DQ/018-Validate-DimProductCategory.sql`

Validated results:

- Expected business rows: `73`
- Actual business rows: `73`
- Unknown rows: `1`
- Total dimension rows: `74`
- Missing English translations: `2`
- Missing Persian localizations: `0`
- Duplicate source categories: `0`
- Null business categories: `0`
- Missing Persian names: `0`
- Invalid English flags: `0`
- Invalid Persian flags: `0`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Final result:

`DIMPRODUCTCATEGORY VALIDATION PASSED.`
---
## DimProduct ETL

`dwh.DimProduct` is loaded directly from `stg.products` through SSIS.

A separate `conformed.Product` table is intentionally not created because the
source product grain is already clean and deterministic:

- Source product rows: `32,951`
- Distinct `product_id` values: `32,951`
- NULL `product_id` values: `0`
- Duplicate `product_id` values: `0`

No product names, costs, profitability attributes, or other unsupported
business data are fabricated.

### Source profile

The Olist product source contains:

- Products without a source category: `610`
- Products with missing descriptive attributes: `610`
- Products with missing physical attributes: `2`
- Products with zero weight: `4`
- Products with negative weight: `0`
- Products with non-positive dimensions: `0`

The `610` products without a category are exactly the same products whose
following descriptive attributes are NULL:

- `product_name_lenght`
- `product_description_lenght`
- `product_photos_qty`

Source NULL values and zero values are preserved in the warehouse.

### Grain

One row per source `product_id`, plus one Unknown member.

### Product category resolution

Product category relationships are resolved through
`dwh.DimProductCategory`.

Products with a non-null source category are routed through an SSIS Lookup
using `SourceCategoryName`.

Every non-null source category must resolve successfully. The Lookup is
configured to fail the component if no matching dimension category exists.

Products whose source `product_category_name` is NULL do not enter the Lookup.
They are explicitly assigned:

`ProductCategoryKey = 0`

This preserves the distinction between a genuinely missing source category and
a failed category lookup.

Validated category behavior:

- Products assigned to Unknown category: `610`
- Non-null source categories without a dimension match: `0`
- Invalid category surrogate keys: `0`

### Data quality flags

The following diagnostic flags are stored in `dwh.DimProduct`:

- `MissingSourceCategoryFlag`
- `MissingDescriptiveAttributesFlag`
- `MissingPhysicalAttributesFlag`
- `ZeroWeightFlag`

Rules:

`MissingSourceCategoryFlag = 1`

when `product_category_name` is NULL.

`MissingDescriptiveAttributesFlag = 1`

when any of the following is NULL:

- product name length
- product description length
- product photo quantity

`MissingPhysicalAttributesFlag = 1`

when any of the following is NULL:

- weight
- length
- height
- width

`ZeroWeightFlag = 1`

when source `product_weight_g = 0`.

These flags describe source quality. They do not replace, correct, or impute
the original values.

### DimProduct

DDL script:

`02-SQL/03-DWH/006-Create-DimProduct.sql`

Columns include:

- `ProductKey`
- `ProductID`
- `ProductCategoryKey`
- `ProductNameLength`
- `ProductDescriptionLength`
- `ProductPhotosQty`
- `ProductWeightG`
- `ProductLengthCm`
- `ProductHeightCm`
- `ProductWidthCm`
- `MissingSourceCategoryFlag`
- `MissingDescriptiveAttributesFlag`
- `MissingPhysicalAttributesFlag`
- `ZeroWeightFlag`

`ProductKey` is the warehouse surrogate key.

`ProductID` is the source business key.

The Olist source does not contain an actual product name. It contains only the
product name length field, so no synthetic product name is created.

### Unknown member

The SSIS package creates the standard Unknown product member before loading
business products:

- `ProductKey = 0`
- `ProductID = NULL`
- `ProductCategoryKey = 0`
- source attribute measures = NULL
- data quality flags = `0`

Business surrogate keys are generated by the SQL Server identity column.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/05-Load-DimProduct.dtsx`

Control Flow:

`SQL - Prepare DimProduct`
→ `DFT - Load DimProduct`

Data Flow:

`SRC - Products`
→ `CS - Product Category Route`

Products with a source category:

`HasCategory`
→ `LKP - Product Category`
→ `UA - Product Category Routes`

Products without a source category:

`MissingCategory`
→ `DER - Unknown Product Category`
→ `UA - Product Category Routes`

Merged rows:

`UA - Product Category Routes`
→ `DST - DimProduct`

### DimProduct validation

Validation script:

`02-SQL/04-DQ/019-Validate-DimProduct.sql`

Validated results:

- Expected business rows: `32,951`
- Actual business rows: `32,951`
- Unknown rows: `1`
- Total dimension rows: `32,952`
- Products on Unknown category: `610`
- Missing source category rows: `610`
- Missing descriptive attribute rows: `610`
- Missing physical attribute rows: `2`
- Zero-weight rows: `4`
- Duplicate Product IDs: `0`
- NULL business Product IDs: `0`
- Invalid category keys: `0`
- Unresolved non-null categories: `0`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Final result:

`DIMPRODUCT VALIDATION PASSED.`
---
## FactOrder ETL

`dwh.FactOrder` stores one row per source order.

A separate `conformed.Order` table is intentionally not created because the
source order grain is already deterministic:

- Source order rows: `99,441`
- Distinct `order_id` values: `99,441`
- NULL `order_id` values: `0`
- Duplicate `order_id` values: `0`

### Grain

One row per source `order_id`.

`OrderID` is stored as a degenerate business key in the fact.

### Customer modeling

Each order stores both:

- `CustomerKey`
- `CustomerGeographyKey`

`CustomerKey` represents the conformed customer identity.

`CustomerGeographyKey` represents the customer ZIP code recorded on the
specific order through the source `customer_id`.

This is intentionally different from the representative geography stored in
`DimCustomer`, which reflects the customer's latest representative profile.

This design preserves historical order geography and prevents older orders
from being attributed to a customer's later location.

Validated resolution results:

- Orders without source customer match: `0`
- Orders without `DimCustomer` match: `0`
- Orders without `DimGeography` match: `0`

### Date keys

The fact stores the following role-playing `DimDate` keys:

- `PurchaseDateKey`
- `ApprovedDateKey`
- `CarrierDateKey`
- `DeliveredDateKey`
- `EstimatedDeliveryDateKey`

Source timestamps are also preserved separately.

When an optional source event timestamp is NULL, its corresponding date key is
assigned:

`DateKey = 0`

The raw timestamp remains NULL.

Validated Unknown date counts:

- Approved date: `160`
- Carrier date: `1,783`
- Delivered date: `2,965`
- Estimated delivery date: `0`

All non-zero date keys resolve to `dwh.DimDate`.

### Source timestamps

The following source values are preserved:

- `PurchaseTimestamp`
- `ApprovedTimestamp`
- `DeliveredCarrierTimestamp`
- `DeliveredCustomerTimestamp`
- `EstimatedDeliveryDate`

Source temporal anomalies are not corrected.

### Temporal data quality flags

The fact stores the following source-quality flags:

- `CarrierBeforePurchaseFlag`
- `CarrierBeforeApprovalFlag`
- `DeliveredBeforeCarrierFlag`

Validated counts:

- Carrier before purchase: `166`
- Carrier before approval: `1,359`
- Delivered before carrier: `23`

These values are preserved as source anomalies and are not rewritten.

### Late delivery KPI

`DeliveredLateFlag` is a business KPI, not a data quality correction.

The correct comparison is date-to-date:

`CAST(order_delivered_customer_date AS DATE) > order_estimated_delivery_date`

This prevents orders delivered later during the estimated delivery date from
being incorrectly classified as late.

Audit results showed:

- Timestamp-based late count: `7,827`
- Date-based late count: `6,535`
- Delivered exactly on estimated date: `1,292`

The warehouse therefore uses the date-based rule.

`DeliveredLateFlag` semantics:

- `1` = delivered after the estimated delivery date
- `0` = delivered on or before the estimated delivery date
- `NULL` = no actual customer delivery timestamp

Validated results:

- Late deliveries: `6,535`
- NULL late status: `2,965`

### OrderCount measure

Each fact row stores:

`OrderCount = 1`

This provides a simple additive order-count measure.

Validated:

- Fact rows: `99,441`
- `SUM(OrderCount)`: `99,441`

### FactOrder

DDL script:

`02-SQL/03-DWH/007-Create-FactOrder.sql`

Main columns:

- `OrderKey`
- `OrderID`
- `CustomerKey`
- `CustomerGeographyKey`
- `PurchaseDateKey`
- `ApprovedDateKey`
- `CarrierDateKey`
- `DeliveredDateKey`
- `EstimatedDeliveryDateKey`
- `OrderStatus`
- source timestamps
- `OrderCount`
- temporal DQ flags
- `DeliveredLateFlag`

`OrderKey` is the warehouse surrogate key.

### Referential integrity strategy

Physical foreign key constraints are intentionally not added to the fact at
this stage.

Current dimension packages use full-refresh preparation with `TRUNCATE TABLE`.
SQL Server does not allow truncating a table that is referenced by a foreign
key, even when the referencing fact table is empty.

Instead, referential integrity is enforced through:

- SSIS dimension lookups,
- fail-on-no-match behavior,
- explicit DQ validation,
- surrogate-key coverage checks.

If the refresh strategy later moves from `TRUNCATE` to `DELETE` or incremental
loading, physical foreign keys can be reconsidered.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/06-Load-FactOrder.dtsx`

Control Flow:

`SQL - Prepare FactOrder`
→ `DFT - Load FactOrder`

Data Flow:

`SRC - Orders`
→ `LKP - Customer`
→ `LKP - Customer Geography`
→ `DST - FactOrder`

Both lookups use full cache and fail the component when a required dimension
member cannot be resolved.

Date keys are generated deterministically from the source dates and do not
require separate SSIS Lookup components because `DimDate.DateKey` uses the
same `YYYYMMDD` key convention.

### FactOrder validation

Validation script:

`02-SQL/04-DQ/020-Validate-FactOrder.sql`

Validated results:

- Expected rows: `99,441`
- Actual rows: `99,441`
- Distinct Order IDs: `99,441`
- Duplicate Order IDs: `0`
- NULL Order IDs: `0`
- Missing expected customer keys: `0`
- Missing expected geography keys: `0`
- Invalid customer keys: `0`
- Invalid geography keys: `0`
- Invalid date keys: `0`
- Invalid OrderCount values: `0`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Final result:

`FACTORDER VALIDATION PASSED.`
---
## FactOrderItem ETL

`dwh.FactOrderItem` stores one row per source order item.

### Grain

The natural transaction grain is:

`OrderID + OrderItemID`

Source audit results:

- Source order-item rows: `112,650`
- Distinct natural-grain rows: `112,650`
- Duplicate natural-grain rows: `0`
- NULL Order IDs: `0`
- NULL Order Item IDs: `0`
- Minimum Order Item ID: `1`
- Maximum Order Item ID: `21`
- Orders whose item sequence does not start at `1`: `0`
- Orders with item-sequence gaps: `0`

### Dimension relationships

Each item row carries the following surrogate keys directly:

- `CustomerKey`
- `CustomerGeographyKey`
- `ProductKey`
- `SellerKey`
- `PurchaseDateKey`
- `ShippingLimitDateKey`

These keys are stored directly on the item fact so reporting does not depend on
fact-to-fact relationships through `FactOrder`.

`CustomerGeographyKey` represents the customer geography associated with the
specific order, not the customer's latest representative geography.

Validated SSIS lookup results:

- Product lookup misses: `0`
- Seller lookup misses: `0`
- Customer lookup misses: `0`
- Customer geography lookup misses: `0`

### Order relationship

`OrderID` is retained as a degenerate business key.

Every `FactOrderItem.OrderID` must also exist in `dwh.FactOrder`.

Validated missing FactOrder matches:

`0`

No physical fact-to-fact foreign key is created.

### Measures

The fact contains only monetary measures supported by the source dataset:

- `PriceAmount`
- `FreightAmount`

No cost, COGS, profit, margin, or other unsupported financial measures are
fabricated.

Validated source totals:

- Total price amount: `13,591,643.70`
- Total freight amount: `2,251,909.54`
- Zero-price rows: `0`
- Zero-freight rows: `383`
- Negative-price rows: `0`
- Negative-freight rows: `0`

### OrderItemCount

Each fact row contains:

`OrderItemCount = 1`

This provides a simple additive item-count measure.

Validated:

- Fact rows: `112,650`
- `SUM(OrderItemCount)`: `112,650`

### Shipping limit date

The source `shipping_limit_date` is preserved as:

- `ShippingLimitTimestamp`
- `ShippingLimitDateKey`

The source contains shipping-limit values extending into `2020`.
These values are preserved as source data and are not corrected.

Validated results:

- NULL shipping-limit dates: `0`
- Shipping-limit dates before purchase: `0`
- Shipping-limit dates missing from `DimDate`: `0`

### Order status

`OrderStatus` is replicated from the order source onto `FactOrderItem`.

This allows item-level price and freight analysis by order status without
requiring a fact-to-fact relationship with `FactOrder`.

### FactOrderItem

DDL script:

`02-SQL/03-DWH/008-Create-FactOrderItem.sql`

Main columns:

- `OrderItemKey`
- `OrderID`
- `OrderItemID`
- `CustomerKey`
- `CustomerGeographyKey`
- `ProductKey`
- `SellerKey`
- `PurchaseDateKey`
- `ShippingLimitDateKey`
- `OrderStatus`
- `ShippingLimitTimestamp`
- `PriceAmount`
- `FreightAmount`
- `OrderItemCount`

`OrderItemKey` is the warehouse surrogate key.

A unique index enforces the natural grain:

`OrderID + OrderItemID`

### Referential integrity strategy

Physical foreign key constraints are intentionally not added to the fact at
this stage.

Current dimension packages use full-refresh preparation with `TRUNCATE TABLE`.
Referential integrity is instead enforced through:

- SSIS full-cache lookups,
- fail-on-no-match behavior,
- explicit DQ validation,
- surrogate-key coverage checks,
- source-to-target reconciliation.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/07-Load-FactOrderItem.dtsx`

Control Flow:

`SQL - Prepare FactOrderItem`
→ `DFT - Load FactOrderItem`

Data Flow:

`SRC - Order Items`
→ `LKP - Product`
→ `LKP - Seller`
→ `LKP - Customer`
→ `LKP - Customer Geography`
→ `DST - FactOrderItem`

All required dimension lookups use full cache and fail the component if a
business key cannot be resolved.

### FactOrderItem validation

Validation script:

`02-SQL/04-DQ/021-Validate-FactOrderItem.sql`

Validated results:

- Expected rows: `112,650`
- Actual rows: `112,650`
- Duplicate natural grain: `0`
- NULL Order IDs: `0`
- Invalid Order Item IDs: `0`
- Missing expected Product keys: `0`
- Missing expected Seller keys: `0`
- Missing expected Customer keys: `0`
- Missing expected Geography keys: `0`
- Invalid Product keys: `0`
- Invalid Seller keys: `0`
- Invalid Customer keys: `0`
- Invalid Geography keys: `0`
- Invalid Date keys: `0`
- Invalid OrderItemCount values: `0`
- Missing FactOrder matches: `0`
- Source-to-target differences: `0`
- Target-to-source differences: `0`
- Total price amount: `13,591,643.70`
- Total freight amount: `2,251,909.54`
- Zero-price rows: `0`
- Zero-freight rows: `383`

Final result:

`FACTORDERITEM VALIDATION PASSED.`
---
## FactPayment ETL

`dwh.FactPayment` stores one row per source payment record.

### Grain

The natural transaction grain is:

`OrderID + PaymentSequential`

Source audit results:

- Source payment rows: `103,886`
- Distinct orders with payments: `99,440`
- Duplicate natural-grain rows: `0`
- NULL Order IDs: `0`
- NULL payment sequence values: `0`
- Minimum payment sequence: `1`
- Maximum payment sequence: `29`

Multi-payment behavior is preserved exactly as supplied by the source.

Validated profile:

- Orders with more than one payment row: `2,961`
- Maximum payment rows for one order: `29`

Payment rows are never joined directly to order-item rows during warehouse
loading because that would create a fact-to-fact fan-out.

### Dimension relationships

Each payment row carries the following conformed surrogate keys directly:

- `CustomerKey`
- `CustomerGeographyKey`
- `PurchaseDateKey`

`CustomerGeographyKey` represents the customer geography associated with the
specific order.

Validated dimension resolution:

- Missing expected Customer keys: `0`
- Missing expected Geography keys: `0`
- Invalid Customer keys: `0`
- Invalid Geography keys: `0`
- Invalid PurchaseDate keys: `0`

### Order relationship

`OrderID` is retained as a degenerate business key.

Every payment row must correspond to an existing `FactOrder`.

Validated missing FactOrder matches:

`0`

The source contains one real order without any payment row.

Validated no-payment behavior:

- Source orders without payments: `1`
- Warehouse orders without payments: `1`

No synthetic payment row is generated for this order.

### Payment attributes and measure

The fact preserves these source attributes:

- `PaymentType`
- `PaymentInstallments`
- `PaymentAmount`

`PaymentAmount` is stored as `DECIMAL(18,2)`.

Validated total:

`16,008,872.12`

No assumptions are made about interest, financing cost, fees, profit, margin,
or any other unsupported financial concept.

### PaymentCount

Each payment fact row contains:

`PaymentCount = 1`

Validated:

- Fact rows: `103,886`
- `SUM(PaymentCount)`: `103,886`

### Payment sequence anomalies

The source contains payment sequences that do not always start at `1` or form a
contiguous sequence.

Validated results:

- Orders with sequence anomaly: `80`
- Payment rows belonging to those orders: `82`

The source `payment_sequential` value is preserved exactly and is never
renumbered.

`PaymentSequenceAnomalyFlag = 1` is applied to every payment row belonging to
an order whose sequence profile is anomalous.

### Additional payment quality flags

The fact stores these diagnostic flags:

- `UndefinedPaymentTypeFlag`
- `ZeroInstallmentFlag`
- `ZeroPaymentValueFlag`

Validated results:

- `payment_type = 'not_defined'`: `3` rows
- Zero-installment rows: `2`
- Zero-payment-value rows: `9`
- Negative installment rows: `0`
- Negative payment values: `0`

Source values are preserved and are not corrected.

### FactPayment

DDL script:

`02-SQL/03-DWH/009-Create-FactPayment.sql`

Main columns:

- `PaymentKey`
- `OrderID`
- `PaymentSequential`
- `CustomerKey`
- `CustomerGeographyKey`
- `PurchaseDateKey`
- `OrderStatus`
- `PaymentType`
- `PaymentInstallments`
- `PaymentAmount`
- `PaymentCount`
- `PaymentSequenceAnomalyFlag`
- `UndefinedPaymentTypeFlag`
- `ZeroInstallmentFlag`
- `ZeroPaymentValueFlag`

`PaymentKey` is the warehouse surrogate key.

A unique index enforces the natural grain:

`OrderID + PaymentSequential`

### Referential integrity strategy

Physical foreign key constraints are intentionally not added to the fact at
this stage.

Current dimension packages use full-refresh preparation with `TRUNCATE TABLE`.

Referential integrity is instead enforced through:

- SSIS full-cache lookups,
- fail-on-no-match behavior,
- explicit DQ validation,
- surrogate-key coverage checks,
- source-to-target reconciliation.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/08-Load-FactPayment.dtsx`

Control Flow:

`SQL - Prepare FactPayment`
→ `DFT - Load FactPayment`

Data Flow:

`SRC - Payments`
→ `LKP - Customer`
→ `LKP - Customer Geography`
→ `DST - FactPayment`

Required dimension lookups use full cache and fail the component when a
business key cannot be resolved.

### FactPayment validation

Validation script:

`02-SQL/04-DQ/022-Validate-FactPayment.sql`

Validated results:

- Expected rows: `103,886`
- Actual rows: `103,886`
- Distinct orders: `99,440`
- Duplicate natural grain: `0`
- NULL Order IDs: `0`
- Invalid payment sequence values: `0`
- Missing expected Customer keys: `0`
- Missing expected Geography keys: `0`
- Invalid Customer keys: `0`
- Invalid Geography keys: `0`
- Invalid Date keys: `0`
- Invalid PaymentCount values: `0`
- Missing FactOrder matches: `0`
- Source orders without payments: `1`
- Warehouse orders without payments: `1`
- Sequence-anomaly orders: `80`
- Sequence-anomaly payment rows: `82`
- Undefined payment-type rows: `3`
- Zero-installment rows: `2`
- Zero-payment-value rows: `9`
- Total payment amount: `16,008,872.12`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Final result:

`FACTPAYMENT VALIDATION PASSED.`
---
## FactReview ETL

`dwh.FactReview` stores one row per source review record.

### Grain

The natural transaction grain is:

`ReviewID + OrderID`

Source audit results:

- Source review rows: `99,224`
- Distinct Review IDs: `98,410`
- Distinct orders with reviews: `98,673`
- Duplicate Review ID groups: `789`
- Extra rows caused by duplicate Review IDs: `814`
- Rows whose Review ID occurs more than once: `1,603`
- Duplicate `ReviewID + OrderID` rows: `0`
- Orders with multiple review rows: `547`
- Maximum review rows for one order: `3`
- Orders without reviews: `768`

`ReviewID` alone is not unique in the source.

No duplicate Review IDs are removed, merged, or corrected.

The unique warehouse grain is enforced as:

`ReviewID + OrderID`

Review rows are never joined directly to order-item rows because an order can
contain multiple items and multiple reviews, which would create fact-to-fact
fan-out.

### Dimension relationships

Each review row carries:

- `CustomerKey`
- `CustomerGeographyKey`
- `PurchaseDateKey`
- `ReviewCreationDateKey`
- `ReviewAnswerDateKey`

`CustomerGeographyKey` represents the customer geography associated with the
specific order.

Validated dimension resolution:

- Missing expected Customer keys: `0`
- Missing expected Geography keys: `0`
- Missing expected Date keys: `0`
- Invalid Customer keys: `0`
- Invalid Geography keys: `0`
- Invalid Date keys: `0`

All review creation and answer dates are covered by `DimDate`.

### Order relationship

`OrderID` is retained as a degenerate business key.

Every review row must correspond to an existing `FactOrder`.

Validated missing FactOrder matches:

`0`

The source contains:

`768`

orders without any review row.

The warehouse preserves the same set:

`768`

No synthetic review row is generated for those orders.

### Review score

`ReviewScore` is preserved directly from the source.

Validated score domain:

- Minimum score: `1`
- Maximum score: `5`
- NULL scores: `0`
- Invalid scores outside `1..5`: `0`

Validated total review score:

`405,471`

### Review text

The source review text columns are preserved without synthetic replacement:

- `ReviewCommentTitle`
- `ReviewCommentMessage`

Source profile:

- NULL comment titles: `87,656`
- NULL comment messages: `58,247`
- Reviews with neither title nor message: `56,518`
- Non-NULL empty titles: `2`
- Non-NULL empty messages: `9`

NULL and empty values are preserved as supplied by the source.

### Review timestamps

The source provides:

- `review_creation_date`
- `review_answer_timestamp`

Both source values are preserved in the fact as:

- `ReviewCreationTimestamp`
- `ReviewAnswerTimestamp`

`review_creation_date` behaves primarily as a business date:

- Rows with non-midnight creation time: `85`
- Rows with non-midnight answer time: `99,223`

Because creation time-of-day is mostly not meaningful, creation-related
anomaly rules use date-to-date comparison.

Answer timestamps contain meaningful time-of-day and therefore use full
timestamp comparison.

### Temporal quality flags

The fact stores:

- `ReviewCreatedBeforePurchaseFlag`
- `ReviewCreatedBeforeDeliveryFlag`
- `ReviewAnsweredBeforePurchaseFlag`
- `ReviewAnsweredBeforeDeliveryFlag`
- `ReviewAnsweredBeforeCreationFlag`

Validated results:

- Reviews created before purchase using date semantics: `64`
- Reviews created before delivery using date semantics: `5,127`
- Reviews answered before purchase using timestamp semantics: `63`
- Reviews answered before delivery using timestamp semantics: `4,795`
- Reviews answered before creation: `0`

There are:

`2,865`

review rows associated with orders that have no customer-delivery timestamp.

For those rows:

- `ReviewCreatedBeforeDeliveryFlag = NULL`
- `ReviewAnsweredBeforeDeliveryFlag = NULL`

`NULL` means the delivery-relative condition cannot be evaluated.

It does not mean that the anomaly is false.

Validated invalid delivery-flag NULL semantics:

`0`

### Duplicate Review ID flag

Because `ReviewID` alone is not unique, the fact stores:

`DuplicateReviewIDFlag`

The flag is set to `1` on every row whose `ReviewID` appears more than once in
the source.

Validated flagged rows:

`1,603`

The source Review ID is always preserved unchanged.

### ReviewCount

Each fact row contains:

`ReviewCount = 1`

Validated:

- Fact rows: `99,224`
- `SUM(ReviewCount)`: `99,224`

### FactReview

DDL script:

`02-SQL/03-DWH/010-Create-FactReview.sql`

Main columns:

- `ReviewKey`
- `ReviewID`
- `OrderID`
- `CustomerKey`
- `CustomerGeographyKey`
- `PurchaseDateKey`
- `ReviewCreationDateKey`
- `ReviewAnswerDateKey`
- `OrderStatus`
- `ReviewScore`
- `ReviewCommentTitle`
- `ReviewCommentMessage`
- `ReviewCreationTimestamp`
- `ReviewAnswerTimestamp`
- `ReviewCount`
- `DuplicateReviewIDFlag`
- `ReviewCreatedBeforePurchaseFlag`
- `ReviewCreatedBeforeDeliveryFlag`
- `ReviewAnsweredBeforePurchaseFlag`
- `ReviewAnsweredBeforeDeliveryFlag`
- `ReviewAnsweredBeforeCreationFlag`

`ReviewKey` is the warehouse surrogate key.

A unique index enforces the natural grain:

`ReviewID + OrderID`

### Referential integrity strategy

Physical foreign key constraints are intentionally not added to the fact at
this stage.

Current dimension packages use full-refresh preparation with `TRUNCATE TABLE`.

Referential integrity is instead enforced through:

- SSIS full-cache lookups,
- fail-on-no-match behavior,
- explicit DQ validation,
- surrogate-key coverage checks,
- source-to-target reconciliation.

### SSIS package

Package:

`04-ETL/SSIS/NOVA_Market_ETL/09-Load-FactReview.dtsx`

Control Flow:

`SQL - Prepare FactReview`
→ `DFT - Load FactReview`

Data Flow:

`SRC - Reviews`
→ `LKP - Customer`
→ `LKP - Customer Geography`
→ `DST - FactReview`

Required dimension lookups use full cache and fail the component when a
business key cannot be resolved.

### FactReview validation

Validation script:

`02-SQL/04-DQ/023-Validate-FactReview.sql`

Validated results:

- Expected rows: `99,224`
- Actual rows: `99,224`
- Distinct orders: `98,673`
- Duplicate natural grain: `0`
- Invalid review scores: `0`
- Invalid ReviewCount values: `0`
- Missing expected Customer keys: `0`
- Missing expected Geography keys: `0`
- Missing expected Date keys: `0`
- Invalid Customer keys: `0`
- Invalid Geography keys: `0`
- Invalid Date keys: `0`
- Missing FactOrder matches: `0`
- Invalid delivery-relative NULL semantics: `0`
- Source orders without reviews: `768`
- Warehouse orders without reviews: `768`
- Duplicate Review ID rows: `1,603`
- Created-before-purchase rows: `64`
- Created-before-delivery rows: `5,127`
- Delivery-relative creation NULL rows: `2,865`
- Answered-before-purchase rows: `63`
- Answered-before-delivery rows: `4,795`
- Delivery-relative answer NULL rows: `2,865`
- Answered-before-creation rows: `0`
- Total review score: `405,471`
- Source-to-target differences: `0`
- Target-to-source differences: `0`

Final result:

`FACTREVIEW VALIDATION PASSED.`
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

