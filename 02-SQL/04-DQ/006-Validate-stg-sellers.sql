USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.sellers
   Source: Olist sellers dataset
   Grain : one row per seller_id

   Purpose:
   - Validate seller source integrity
   - Validate seller geographic attributes
   - Validate referential integrity with order_items

   Known Source Expectation:
   - Total rows = 3,095
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.sellers;

-- Expected: 3,095


------------------------------------------------------------
-- 2. Duplicate Source Key: seller_id
------------------------------------------------------------
SELECT
    seller_id,
    COUNT(*) AS DuplicateCount
FROM stg.sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 3. NULL Audit
------------------------------------------------------------
SELECT
    SUM(CASE WHEN seller_id IS NULL THEN 1 ELSE 0 END)
        AS SellerIdNulls,

    SUM(CASE WHEN seller_zip_code_prefix IS NULL THEN 1 ELSE 0 END)
        AS ZipCodeNulls,

    SUM(CASE WHEN seller_city IS NULL THEN 1 ELSE 0 END)
        AS CityNulls,

    SUM(CASE WHEN seller_state IS NULL THEN 1 ELSE 0 END)
        AS StateNulls

FROM stg.sellers;


------------------------------------------------------------
-- 4. Blank / Empty Text Values
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN seller_zip_code_prefix IS NOT NULL
             AND LTRIM(RTRIM(seller_zip_code_prefix)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankZipCode,

    SUM(
        CASE
            WHEN seller_city IS NOT NULL
             AND LTRIM(RTRIM(seller_city)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankCity,

    SUM(
        CASE
            WHEN seller_state IS NOT NULL
             AND LTRIM(RTRIM(seller_state)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankState

FROM stg.sellers;


------------------------------------------------------------
-- 5. Referential Integrity:
-- order_items -> sellers
------------------------------------------------------------
SELECT
    COUNT(*) AS OrphanOrderItems
FROM stg.order_items oi
LEFT JOIN stg.sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- Expected: 0


------------------------------------------------------------
-- 6. Sellers Without Any Order Item
------------------------------------------------------------
SELECT
    COUNT(*) AS SellersWithoutOrderItems
FROM stg.sellers s
LEFT JOIN stg.order_items oi
    ON s.seller_id = oi.seller_id
WHERE oi.seller_id IS NULL;

-- Informational only


------------------------------------------------------------
-- 7. ZIP Code Length Distribution
------------------------------------------------------------
SELECT
    LEN(seller_zip_code_prefix) AS ZipLength,
    COUNT(*) AS SellerCount
FROM stg.sellers
GROUP BY LEN(seller_zip_code_prefix)
ORDER BY ZipLength;

-- Informational
-- ZIP prefix is stored as text to preserve formatting.


------------------------------------------------------------
-- 8. Non-Numeric ZIP Code Values
------------------------------------------------------------
SELECT
    seller_zip_code_prefix,
    COUNT(*) AS SellerCount
FROM stg.sellers
WHERE seller_zip_code_prefix IS NOT NULL
  AND seller_zip_code_prefix LIKE '%[^0-9]%'
GROUP BY seller_zip_code_prefix
ORDER BY seller_zip_code_prefix;

-- Expected: No rows


------------------------------------------------------------
-- 9. State Code Length Validation
------------------------------------------------------------
SELECT
    seller_state,
    COUNT(*) AS SellerCount
FROM stg.sellers
WHERE seller_state IS NULL
   OR LEN(seller_state) <> 2
GROUP BY seller_state;

-- Expected: No rows


------------------------------------------------------------
-- 10. Brazilian State Code Validation
------------------------------------------------------------
SELECT
    seller_state,
    COUNT(*) AS SellerCount
FROM stg.sellers
WHERE seller_state NOT IN
(
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF',
    'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA',
    'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS',
    'RO', 'RR', 'SC', 'SP', 'SE', 'TO'
)
GROUP BY seller_state
ORDER BY seller_state;

-- Expected: No rows


------------------------------------------------------------
-- 11. Seller Distribution by State
------------------------------------------------------------
SELECT
    seller_state,
    COUNT(*) AS SellerCount
FROM stg.sellers
GROUP BY seller_state
ORDER BY SellerCount DESC;

-- Informational


------------------------------------------------------------
-- 12. Seller Distribution by City
------------------------------------------------------------
SELECT
    seller_city,
    seller_state,
    COUNT(*) AS SellerCount
FROM stg.sellers
GROUP BY
    seller_city,
    seller_state
ORDER BY SellerCount DESC;

-- Informational


------------------------------------------------------------
-- 13. Order Item Count per Seller
------------------------------------------------------------
SELECT
    s.seller_id,
    COUNT(oi.order_id) AS OrderItemCount
FROM stg.sellers s
LEFT JOIN stg.order_items oi
    ON s.seller_id = oi.seller_id
GROUP BY s.seller_id
ORDER BY OrderItemCount DESC;

-- Informational
-- Useful later for seller activity analysis.


------------------------------------------------------------
-- 14. Seller Activity Summary
------------------------------------------------------------
SELECT
    MIN(x.OrderItemCount) AS MinOrderItemsPerSeller,
    MAX(x.OrderItemCount) AS MaxOrderItemsPerSeller,
    CAST(AVG(CAST(x.OrderItemCount AS DECIMAL(18,2)))
         AS DECIMAL(18,2)) AS AvgOrderItemsPerSeller
FROM
(
    SELECT
        s.seller_id,
        COUNT(oi.order_id) AS OrderItemCount
    FROM stg.sellers s
    LEFT JOIN stg.order_items oi
        ON s.seller_id = oi.seller_id
    GROUP BY s.seller_id
) x;

-- Informational