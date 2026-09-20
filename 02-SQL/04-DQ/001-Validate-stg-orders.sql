USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.orders
   Source: Olist orders dataset
   ========================================================= */

-- 1. Row count
SELECT COUNT(*) AS [RowCount]
FROM stg.orders;

-- 2. Duplicate order_id
SELECT
    order_id,
    COUNT(*) AS DuplicateCount
FROM stg.orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- 3. NULL audit
SELECT
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS customer_id_nulls,
    SUM(CASE WHEN order_status IS NULL THEN 1 ELSE 0 END) AS order_status_nulls,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS purchase_nulls,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS approved_nulls,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS carrier_nulls,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS delivered_nulls,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS estimated_nulls
FROM stg.orders;

-- 4. Purchase date range
SELECT
    MIN(order_purchase_timestamp) AS MinPurchaseDate,
    MAX(order_purchase_timestamp) AS MaxPurchaseDate
FROM stg.orders;

-- 5. Order status distribution
SELECT
    order_status,
    COUNT(*) AS OrderCount
FROM stg.orders
GROUP BY order_status
ORDER BY OrderCount DESC;