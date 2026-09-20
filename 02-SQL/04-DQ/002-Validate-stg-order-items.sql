USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.order_items
   Source: Olist order items dataset
   Grain : one row per (order_id, order_item_id)
   ========================================================= */

-- 1. Row count
SELECT COUNT(*) AS [RowCount]
FROM stg.order_items;

-- 2. Duplicate composite key
SELECT
    order_id,
    order_item_id,
    COUNT(*) AS DuplicateCount
FROM stg.order_items
GROUP BY
    order_id,
    order_item_id
HAVING COUNT(*) > 1;

-- 3. NULL audit
SELECT
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN order_item_id IS NULL THEN 1 ELSE 0 END) AS order_item_id_nulls,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS product_id_nulls,
    SUM(CASE WHEN seller_id IS NULL THEN 1 ELSE 0 END) AS seller_id_nulls,
    SUM(CASE WHEN shipping_limit_date IS NULL THEN 1 ELSE 0 END) AS shipping_limit_date_nulls,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS price_nulls,
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS freight_value_nulls
FROM stg.order_items;

-- 4. Orphan check against orders
SELECT COUNT(*) AS OrphanOrderItems
FROM stg.order_items oi
LEFT JOIN stg.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- 5. Numeric sanity check
SELECT
    MIN(price) AS MinPrice,
    MAX(price) AS MaxPrice,
    MIN(freight_value) AS MinFreight,
    MAX(freight_value) AS MaxFreight,
    SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END) AS ZeroFreightRows
FROM stg.order_items;

-- 6. Invalid negative values
SELECT
    SUM(CASE WHEN price < 0 THEN 1 ELSE 0 END) AS NegativePriceRows,
    SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END) AS NegativeFreightRows
FROM stg.order_items;