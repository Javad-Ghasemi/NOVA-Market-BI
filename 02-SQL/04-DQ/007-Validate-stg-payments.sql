USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.payments
   Source: Olist order payments dataset
   Grain : one row per (order_id, payment_sequential)

   Purpose:
   - Validate payment source integrity
   - Validate payment values and installments
   - Validate referential integrity with orders
   - Identify orders with multiple payment records
   - Document known source payment anomalies
   - Prevent payment/order-item fan-out in the DWH

   Known Source Expectations:
   - Total rows = 103,886
   - Distinct orders with payments = 99,440
   - Orders with multiple payment rows = 2,961
   - Maximum payment rows per order = 29

   Modeling Note:
   Payments must remain a separate fact domain.

   Do NOT directly join payment rows to order-item rows when
   calculating sales because both tables may contain multiple
   rows per order and can create fan-out.

   Future DWH target:
   FactPayment
   Grain = one row per payment record
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.payments;

-- Expected: 103,886


------------------------------------------------------------
-- 2. Duplicate Composite Key
--    (order_id, payment_sequential)
------------------------------------------------------------
SELECT
    order_id,
    payment_sequential,
    COUNT(*) AS DuplicateCount
FROM stg.payments
GROUP BY
    order_id,
    payment_sequential
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 3. NULL Audit
------------------------------------------------------------
SELECT
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END)
        AS OrderIdNulls,

    SUM(CASE WHEN payment_sequential IS NULL THEN 1 ELSE 0 END)
        AS PaymentSequentialNulls,

    SUM(CASE WHEN payment_type IS NULL THEN 1 ELSE 0 END)
        AS PaymentTypeNulls,

    SUM(CASE WHEN payment_installments IS NULL THEN 1 ELSE 0 END)
        AS PaymentInstallmentsNulls,

    SUM(CASE WHEN payment_value IS NULL THEN 1 ELSE 0 END)
        AS PaymentValueNulls

FROM stg.payments;

-- Expected: all 0


------------------------------------------------------------
-- 4. Blank Payment Type
------------------------------------------------------------
SELECT
    COUNT(*) AS BlankPaymentTypeRows
FROM stg.payments
WHERE payment_type IS NOT NULL
  AND LTRIM(RTRIM(payment_type)) = '';

-- Expected: 0


------------------------------------------------------------
-- 5. Referential Integrity:
--    payments -> orders
------------------------------------------------------------
SELECT
    COUNT(*) AS OrphanPayments
FROM stg.payments p
LEFT JOIN stg.orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Expected: 0


------------------------------------------------------------
-- 6. Orders Without Payment Records
------------------------------------------------------------
SELECT
    COUNT(*) AS OrdersWithoutPayments
FROM stg.orders o
LEFT JOIN stg.payments p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL;

-- Known Source Gap: 1


------------------------------------------------------------
-- Known Source Payment Coverage Gap
--
-- One delivered order has no payment record:
--
-- OrderID:
-- bfbd0f9bdef84302105ad712db648a6c
--
-- Status     = delivered
-- Order Items = 3
--
-- The order is preserved exactly as provided by the source.
-- No synthetic payment record is created.
------------------------------------------------------------


------------------------------------------------------------
-- 7. Orders Without Payment Records - Detail
------------------------------------------------------------
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_customer_date,
    COUNT(oi.order_id) AS OrderItemCount
FROM stg.orders o
LEFT JOIN stg.payments p
    ON o.order_id = p.order_id
LEFT JOIN stg.order_items oi
    ON o.order_id = oi.order_id
WHERE p.order_id IS NULL
GROUP BY
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_customer_date;

-- Expected known record:
-- bfbd0f9bdef84302105ad712db648a6c


------------------------------------------------------------
-- 8. Distinct Orders Represented in Payments
------------------------------------------------------------
SELECT
    COUNT(DISTINCT order_id) AS OrdersWithPayments
FROM stg.payments;

-- Expected: 99,440


------------------------------------------------------------
-- 9. Orders With Multiple Payment Rows
------------------------------------------------------------
SELECT
    COUNT(*) AS OrdersWithMultiplePayments
FROM
(
    SELECT
        order_id
    FROM stg.payments
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x;

-- Expected: 2,961


------------------------------------------------------------
-- 10. Maximum Payment Rows per Order
------------------------------------------------------------
SELECT
    MAX(x.PaymentRowCount) AS MaxPaymentRowsPerOrder
FROM
(
    SELECT
        order_id,
        COUNT(*) AS PaymentRowCount
    FROM stg.payments
    GROUP BY order_id
) x;

-- Expected: 29


------------------------------------------------------------
-- 11. Payment Row Distribution per Order
------------------------------------------------------------
SELECT
    PaymentRowCount,
    COUNT(*) AS OrderCount
FROM
(
    SELECT
        order_id,
        COUNT(*) AS PaymentRowCount
    FROM stg.payments
    GROUP BY order_id
) x
GROUP BY PaymentRowCount
ORDER BY PaymentRowCount;

-- Informational


------------------------------------------------------------
-- 12. Invalid Negative Values
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN payment_sequential < 0
            THEN 1 ELSE 0
        END
    ) AS NegativePaymentSequentialRows,

    SUM(
        CASE
            WHEN payment_installments < 0
            THEN 1 ELSE 0
        END
    ) AS NegativeInstallmentRows,

    SUM(
        CASE
            WHEN payment_value < 0
            THEN 1 ELSE 0
        END
    ) AS NegativePaymentValueRows

FROM stg.payments;

-- Expected: all 0


------------------------------------------------------------
-- 13. Zero Payment Values
------------------------------------------------------------
SELECT
    COUNT(*) AS ZeroPaymentValueRows
FROM stg.payments
WHERE payment_value = 0;

-- Observed: 9
-- Informational / source-preserved value


------------------------------------------------------------
-- 14. Zero Installment Values
------------------------------------------------------------
SELECT
    COUNT(*) AS ZeroInstallmentRows
FROM stg.payments
WHERE payment_installments = 0;

-- Observed: 2
-- Informational / source-preserved value


------------------------------------------------------------
-- 15. Numeric Range / Sanity Check
------------------------------------------------------------
SELECT
    MIN(payment_sequential) AS MinPaymentSequential,
    MAX(payment_sequential) AS MaxPaymentSequential,

    MIN(payment_installments) AS MinInstallments,
    MAX(payment_installments) AS MaxInstallments,

    MIN(payment_value) AS MinPaymentValue,
    MAX(payment_value) AS MaxPaymentValue

FROM stg.payments;


------------------------------------------------------------
-- 16. Payment Type Distribution
------------------------------------------------------------
SELECT
    payment_type,
    COUNT(*) AS PaymentCount,
    CAST(
        SUM(payment_value)
        AS DECIMAL(18,2)
    ) AS TotalPaymentValue
FROM stg.payments
GROUP BY payment_type
ORDER BY PaymentCount DESC;

-- Informational


------------------------------------------------------------
-- Known Source Payment Sequence Anomaly
--
-- 80 orders do not start payment_sequential at 1:
--
-- - 78 orders contain only sequence 2
-- - 2 orders contain sequences 2 and 3
--
-- These values are preserved exactly as provided by the source.
-- No renumbering is applied in staging.
--
-- This is treated as a known source anomaly rather than an
-- ingestion failure.
------------------------------------------------------------


------------------------------------------------------------
-- 17. Payment Sequence Starting Value Check
------------------------------------------------------------
SELECT
    order_id,
    COUNT(*) AS PaymentRows,
    MIN(payment_sequential) AS MinSequence,
    MAX(payment_sequential) AS MaxSequence
FROM stg.payments
GROUP BY order_id
HAVING MIN(payment_sequential) <> 1
ORDER BY
    PaymentRows DESC,
    order_id;

-- Expected known anomaly:
-- 80 orders


------------------------------------------------------------
-- 18. Payment Sequence Anomaly Summary
------------------------------------------------------------
WITH PaymentSequence AS
(
    SELECT
        order_id,
        COUNT(*) AS PaymentRows,
        MIN(payment_sequential) AS MinSequence,
        MAX(payment_sequential) AS MaxSequence
    FROM stg.payments
    GROUP BY order_id
),
AnomalyOrders AS
(
    SELECT
        order_id,
        PaymentRows,
        MinSequence,
        MaxSequence
    FROM PaymentSequence
    WHERE
        MinSequence <> 1
        OR MaxSequence <> PaymentRows
)
SELECT
    PaymentRows,
    MinSequence,
    MaxSequence,
    COUNT(*) AS OrderCount
FROM AnomalyOrders
GROUP BY
    PaymentRows,
    MinSequence,
    MaxSequence
ORDER BY
    PaymentRows,
    MinSequence,
    MaxSequence;

-- Expected:
--
-- PaymentRows = 1, Min = 2, Max = 2, Orders = 78
-- PaymentRows = 2, Min = 2, Max = 3, Orders = 2


------------------------------------------------------------
-- 19. Order-Level Payment Totals
------------------------------------------------------------
SELECT TOP (20)
    order_id,
    COUNT(*) AS PaymentRows,
    CAST(
        SUM(payment_value)
        AS DECIMAL(18,2)
    ) AS TotalPaymentValue
FROM stg.payments
GROUP BY order_id
ORDER BY TotalPaymentValue DESC;

-- Informational


------------------------------------------------------------
-- 20. Payment vs Order-Item Total Reconciliation
--
-- Payment totals are compared with:
--
--     SUM(price + freight_value)
--
-- Known Source Behavior:
--
-- A subset of orders shows reconciliation gaps.
-- These gaps are strongly associated with credit-card
-- installment payments and generally increase with higher
-- installment counts.
--
-- Therefore:
--
-- - A mismatch is NOT automatically treated as a DQ failure.
-- - Source payment values must be preserved.
-- - No synthetic correction is applied.
-- - payment_value and item + freight totals remain separate
--   analytical measures.
--
-- Observed during DQ:
--
-- Total mismatch orders (> 0.01) = 303
--
-- Status distribution:
-- Delivered = 299
-- Shipped   = 2
-- Canceled  = 2
--
-- Difference profile:
-- Minimum absolute difference = 0.02
-- Maximum absolute difference = 182.81
-- Average absolute difference = 10.79
--
-- Difference <= 1  = 54 orders
-- Difference > 1   = 249 orders
-- Difference > 10  = 98 orders
-- Difference > 100 = 3 orders
--
-- Among mismatched single-row credit-card payments,
-- higher installment counts generally show larger
-- positive reconciliation differences.
--
-- The exact commercial meaning of the additional amount
-- is not assumed because the source dataset does not
-- explicitly identify it as interest, fee, or another charge.
------------------------------------------------------------


------------------------------------------------------------
-- 21. Payment vs Item + Freight Mismatch Count
------------------------------------------------------------
WITH PaymentTotals AS
(
    SELECT
        order_id,
        SUM(payment_value) AS PaymentTotal
    FROM stg.payments
    GROUP BY order_id
),
ItemTotals AS
(
    SELECT
        order_id,
        SUM(price + freight_value) AS ItemAndFreightTotal
    FROM stg.order_items
    GROUP BY order_id
)
SELECT
    COUNT(*) AS ReconciliationMismatchOrders
FROM PaymentTotals p
INNER JOIN ItemTotals i
    ON p.order_id = i.order_id
WHERE ABS(
    p.PaymentTotal - i.ItemAndFreightTotal
) > 0.01;

-- Observed: 303


------------------------------------------------------------
-- 22. Reconciliation Difference Summary
------------------------------------------------------------
WITH PaymentTotals AS
(
    SELECT
        order_id,
        SUM(payment_value) AS PaymentTotal
    FROM stg.payments
    GROUP BY order_id
),
ItemTotals AS
(
    SELECT
        order_id,
        SUM(price + freight_value) AS ItemAndFreightTotal
    FROM stg.order_items
    GROUP BY order_id
),
Differences AS
(
    SELECT
        p.order_id,
        p.PaymentTotal,
        i.ItemAndFreightTotal,
        ABS(
            p.PaymentTotal - i.ItemAndFreightTotal
        ) AS AbsDifference
    FROM PaymentTotals p
    INNER JOIN ItemTotals i
        ON p.order_id = i.order_id
    WHERE ABS(
        p.PaymentTotal - i.ItemAndFreightTotal
    ) > 0.01
)
SELECT
    COUNT(*) AS MismatchOrders,

    CAST(
        MIN(AbsDifference)
        AS DECIMAL(18,2)
    ) AS MinDifference,

    CAST(
        MAX(AbsDifference)
        AS DECIMAL(18,2)
    ) AS MaxDifference,

    CAST(
        AVG(AbsDifference)
        AS DECIMAL(18,2)
    ) AS AvgDifference,

    SUM(
        CASE
            WHEN AbsDifference <= 1
            THEN 1 ELSE 0
        END
    ) AS DifferenceLessOrEqual1,

    SUM(
        CASE
            WHEN AbsDifference > 1
            THEN 1 ELSE 0
        END
    ) AS DifferenceGreaterThan1,

    SUM(
        CASE
            WHEN AbsDifference > 10
            THEN 1 ELSE 0
        END
    ) AS DifferenceGreaterThan10,

    SUM(
        CASE
            WHEN AbsDifference > 100
            THEN 1 ELSE 0
        END
    ) AS DifferenceGreaterThan100

FROM Differences;


------------------------------------------------------------
-- 23. Reconciliation by Order Status
------------------------------------------------------------
WITH PaymentTotals AS
(
    SELECT
        order_id,
        SUM(payment_value) AS PaymentTotal
    FROM stg.payments
    GROUP BY order_id
),
ItemTotals AS
(
    SELECT
        order_id,
        SUM(price + freight_value) AS ItemAndFreightTotal
    FROM stg.order_items
    GROUP BY order_id
),
Mismatch AS
(
    SELECT
        p.order_id,
        p.PaymentTotal,
        i.ItemAndFreightTotal,
        p.PaymentTotal - i.ItemAndFreightTotal AS Difference
    FROM PaymentTotals p
    INNER JOIN ItemTotals i
        ON p.order_id = i.order_id
    WHERE ABS(
        p.PaymentTotal - i.ItemAndFreightTotal
    ) > 0.01
)
SELECT
    o.order_status,
    COUNT(*) AS OrderCount,

    SUM(
        CASE
            WHEN m.Difference > 0
            THEN 1 ELSE 0
        END
    ) AS PaymentHigherCount,

    SUM(
        CASE
            WHEN m.Difference < 0
            THEN 1 ELSE 0
        END
    ) AS PaymentLowerCount

FROM Mismatch m
INNER JOIN stg.orders o
    ON m.order_id = o.order_id
GROUP BY o.order_status
ORDER BY OrderCount DESC;

-- Observed:
--
-- delivered = 299
-- shipped   = 2
-- canceled  = 2


------------------------------------------------------------
-- 24. Credit-Card Installment Reconciliation Pattern
------------------------------------------------------------
WITH PaymentTotals AS
(
    SELECT
        order_id,
        COUNT(*) AS PaymentRows,
        MAX(payment_type) AS PaymentType,
        MAX(payment_installments) AS Installments,
        SUM(payment_value) AS PaymentTotal
    FROM stg.payments
    GROUP BY order_id
),
ItemTotals AS
(
    SELECT
        order_id,
        SUM(price + freight_value) AS ItemAndFreightTotal
    FROM stg.order_items
    GROUP BY order_id
),
Mismatch AS
(
    SELECT
        p.order_id,
        p.PaymentRows,
        p.PaymentType,
        p.Installments,
        p.PaymentTotal,
        i.ItemAndFreightTotal,
        p.PaymentTotal - i.ItemAndFreightTotal AS Difference
    FROM PaymentTotals p
    INNER JOIN ItemTotals i
        ON p.order_id = i.order_id
    WHERE ABS(
        p.PaymentTotal - i.ItemAndFreightTotal
    ) > 0.01
)
SELECT
    Installments,
    COUNT(*) AS OrderCount,

    SUM(
        CASE
            WHEN Difference > 0
            THEN 1 ELSE 0
        END
    ) AS PaymentHigherCount,

    SUM(
        CASE
            WHEN Difference < 0
            THEN 1 ELSE 0
        END
    ) AS PaymentLowerCount,

    CAST(
        AVG(Difference)
        AS DECIMAL(18,2)
    ) AS AvgDifference,

    CAST(
        MAX(Difference)
        AS DECIMAL(18,2)
    ) AS MaxDifference,

    CAST(
        MIN(Difference)
        AS DECIMAL(18,2)
    ) AS MinDifference

FROM Mismatch
WHERE PaymentRows = 1
  AND PaymentType = N'credit_card'
GROUP BY Installments
ORDER BY Installments;

-- Informational
-- Used to document the relationship between installment
-- count and reconciliation differences.


------------------------------------------------------------
-- 25. Reconciliation Detail
------------------------------------------------------------
WITH PaymentTotals AS
(
    SELECT
        order_id,
        COUNT(*) AS PaymentRows,
        SUM(payment_value) AS PaymentTotal
    FROM stg.payments
    GROUP BY order_id
),
ItemTotals AS
(
    SELECT
        order_id,
        COUNT(*) AS ItemRows,
        SUM(price) AS ItemPriceTotal,
        SUM(freight_value) AS FreightTotal,
        SUM(price + freight_value) AS ItemAndFreightTotal
    FROM stg.order_items
    GROUP BY order_id
)
SELECT TOP (100)
    p.order_id,
    o.order_status,
    p.PaymentRows,
    i.ItemRows,

    CAST(
        i.ItemPriceTotal
        AS DECIMAL(18,2)
    ) AS ItemPriceTotal,

    CAST(
        i.FreightTotal
        AS DECIMAL(18,2)
    ) AS FreightTotal,

    CAST(
        i.ItemAndFreightTotal
        AS DECIMAL(18,2)
    ) AS ExpectedItemAndFreight,

    CAST(
        p.PaymentTotal
        AS DECIMAL(18,2)
    ) AS PaymentTotal,

    CAST(
        p.PaymentTotal - i.ItemAndFreightTotal
        AS DECIMAL(18,2)
    ) AS Difference

FROM PaymentTotals p
INNER JOIN ItemTotals i
    ON p.order_id = i.order_id
INNER JOIN stg.orders o
    ON p.order_id = o.order_id
WHERE ABS(
    p.PaymentTotal - i.ItemAndFreightTotal
) > 0.01
ORDER BY ABS(
    p.PaymentTotal - i.ItemAndFreightTotal
) DESC;

-- Diagnostic detail only.
-- Source values must not be modified based on this result.