USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.customers
   Source: Olist customers dataset
   Grain : one row per customer_id

   Important Modeling Note:
   - customer_id is the source-level unique key.
   - customer_unique_id represents the analytical customer identity.
   - One customer_unique_id may legitimately appear with multiple
     customer_id values across different orders.

   Known Source Expectations:
   - Total rows              = 99,441
   - Distinct customer_id    = 99,441
   - Distinct customer_unique_id = 96,096
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.customers;

-- Expected: 99,441


------------------------------------------------------------
-- 2. Duplicate Source Key: customer_id
------------------------------------------------------------
SELECT
    customer_id,
    COUNT(*) AS DuplicateCount
FROM stg.customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 3. NULL Audit
------------------------------------------------------------
SELECT
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END)
        AS CustomerIdNulls,

    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END)
        AS CustomerUniqueIdNulls,

    SUM(CASE WHEN customer_zip_code_prefix IS NULL THEN 1 ELSE 0 END)
        AS ZipCodeNulls,

    SUM(CASE WHEN customer_city IS NULL THEN 1 ELSE 0 END)
        AS CityNulls,

    SUM(CASE WHEN customer_state IS NULL THEN 1 ELSE 0 END)
        AS StateNulls

FROM stg.customers;

-- Expected: all 0


------------------------------------------------------------
-- 4. Blank / Empty Text Values
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN LTRIM(RTRIM(customer_unique_id)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankCustomerUniqueId,

    SUM(
        CASE
            WHEN customer_zip_code_prefix IS NOT NULL
             AND LTRIM(RTRIM(customer_zip_code_prefix)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankZipCode,

    SUM(
        CASE
            WHEN customer_city IS NOT NULL
             AND LTRIM(RTRIM(customer_city)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankCity,

    SUM(
        CASE
            WHEN customer_state IS NOT NULL
             AND LTRIM(RTRIM(customer_state)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankState

FROM stg.customers;

-- Expected: all 0


------------------------------------------------------------
-- 5. Distinct Analytical Customers
------------------------------------------------------------
SELECT
    COUNT(DISTINCT customer_unique_id)
        AS DistinctCustomerUniqueIds
FROM stg.customers;

-- Expected: 96,096


------------------------------------------------------------
-- 6. Repeated customer_unique_id Values
------------------------------------------------------------
SELECT
    customer_unique_id,
    COUNT(*) AS CustomerIdCount
FROM stg.customers
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY CustomerIdCount DESC;

-- Informational
-- These are NOT duplicate source records.
-- They represent customers appearing in multiple orders.


------------------------------------------------------------
-- 7. Count of Returning Customer Identities
------------------------------------------------------------
SELECT
    COUNT(*) AS ReturningCustomerCount
FROM
(
    SELECT
        customer_unique_id
    FROM stg.customers
    GROUP BY customer_unique_id
    HAVING COUNT(*) > 1
) x;

-- Informational


------------------------------------------------------------
-- 8. Referential Integrity: orders -> customers
------------------------------------------------------------
SELECT
    COUNT(*) AS OrphanOrders
FROM stg.orders o
LEFT JOIN stg.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Expected: 0


------------------------------------------------------------
-- 9. Customers Without Orders
------------------------------------------------------------
SELECT
    COUNT(*) AS CustomersWithoutOrders
FROM stg.customers c
LEFT JOIN stg.orders o
    ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;

-- Expected: 0


------------------------------------------------------------
-- 10. customer_id Used by More Than One Order
------------------------------------------------------------
SELECT
    c.customer_id,
    COUNT(o.order_id) AS OrderCount
FROM stg.customers c
INNER JOIN stg.orders o
    ON c.customer_id = o.customer_id
GROUP BY c.customer_id
HAVING COUNT(o.order_id) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 11. ZIP Code Length Distribution
------------------------------------------------------------
SELECT
    LEN(customer_zip_code_prefix) AS ZipLength,
    COUNT(*) AS CustomerCount
FROM stg.customers
GROUP BY LEN(customer_zip_code_prefix)
ORDER BY ZipLength;

-- Informational
-- Staging preserves source formatting exactly.


------------------------------------------------------------
-- 12. Non-Numeric ZIP Code Values
------------------------------------------------------------
SELECT
    customer_zip_code_prefix,
    COUNT(*) AS CustomerCount
FROM stg.customers
WHERE customer_zip_code_prefix IS NOT NULL
  AND customer_zip_code_prefix LIKE '%[^0-9]%'
GROUP BY customer_zip_code_prefix
ORDER BY customer_zip_code_prefix;

-- Expected: No rows


------------------------------------------------------------
-- 13. State Code Length Validation
------------------------------------------------------------
SELECT
    customer_state,
    COUNT(*) AS CustomerCount
FROM stg.customers
WHERE customer_state IS NULL
   OR LEN(customer_state) <> 2
GROUP BY customer_state;

-- Expected: No rows


------------------------------------------------------------
-- 14. Brazilian State Code Validation
------------------------------------------------------------
SELECT
    customer_state,
    COUNT(*) AS CustomerCount
FROM stg.customers
WHERE customer_state NOT IN
(
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF',
    'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA',
    'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS',
    'RO', 'RR', 'SC', 'SP', 'SE', 'TO'
)
GROUP BY customer_state
ORDER BY customer_state;

-- Expected: No rows


------------------------------------------------------------
-- 15. Customer Distribution by State
------------------------------------------------------------
SELECT
    customer_state,
    COUNT(*) AS CustomerCount
FROM stg.customers
GROUP BY customer_state
ORDER BY CustomerCount DESC;

-- Informational


------------------------------------------------------------
-- 16. Customer Distribution by City
------------------------------------------------------------
SELECT
    customer_city,
    customer_state,
    COUNT(*) AS CustomerCount
FROM stg.customers
GROUP BY
    customer_city,
    customer_state
ORDER BY CustomerCount DESC;

-- Informational