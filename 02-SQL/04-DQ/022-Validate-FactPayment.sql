USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedFactPayment;
GO


/* =========================================================
   Build expected FactPayment rows
   ========================================================= */

WITH PaymentProfile AS
(
    SELECT
        p.order_id,
        p.payment_sequential,
        p.payment_type,
        p.payment_installments,
        p.payment_value,

        MIN(p.payment_sequential)
            OVER (PARTITION BY p.order_id)
            AS MinPaymentSequence,

        MAX(p.payment_sequential)
            OVER (PARTITION BY p.order_id)
            AS MaxPaymentSequence,

        COUNT(*)
            OVER (PARTITION BY p.order_id)
            AS PaymentRowsPerOrder

    FROM stg.payments AS p
)
SELECT
    p.order_id AS OrderID,
    p.payment_sequential AS PaymentSequential,

    dc.CustomerKey,
    dg.GeographyKey AS CustomerGeographyKey,

    CONVERT(
        INT,
        CONVERT(
            CHAR(8),
            CAST(o.order_purchase_timestamp AS DATE),
            112
        )
    ) AS PurchaseDateKey,

    o.order_status AS OrderStatus,

    p.payment_type AS PaymentType,
    p.payment_installments AS PaymentInstallments,

    CAST(p.payment_value AS DECIMAL(18,2))
        AS PaymentAmount,

    CAST(1 AS TINYINT)
        AS PaymentCount,

    CAST(
        CASE
            WHEN p.MinPaymentSequence <> 1
              OR p.MaxPaymentSequence <> p.PaymentRowsPerOrder
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS PaymentSequenceAnomalyFlag,

    CAST(
        CASE
            WHEN p.payment_type = N'not_defined'
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS UndefinedPaymentTypeFlag,

    CAST(
        CASE
            WHEN p.payment_installments = 0
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS ZeroInstallmentFlag,

    CAST(
        CASE
            WHEN p.payment_value = 0
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS ZeroPaymentValueFlag

INTO #ExpectedFactPayment

FROM PaymentProfile AS p

INNER JOIN stg.orders AS o
    ON p.order_id = o.order_id

INNER JOIN stg.customers AS c
    ON o.customer_id = c.customer_id

LEFT JOIN dwh.DimCustomer AS dc
    ON c.customer_unique_id = dc.CustomerUniqueID

LEFT JOIN dwh.DimGeography AS dg
    ON c.customer_zip_code_prefix = dg.ZipCodePrefix;
GO


/* =========================================================
   Expected summary
   ========================================================= */

SELECT
    COUNT(*) AS ExpectedRows,

    COUNT(DISTINCT OrderID)
        AS ExpectedDistinctOrders,

    SUM(PaymentCount)
        AS ExpectedPaymentCount,

    SUM(PaymentAmount)
        AS ExpectedPaymentAmount,

    (
        SELECT COUNT(*)
        FROM
        (
            SELECT OrderID
            FROM #ExpectedFactPayment
            WHERE PaymentSequenceAnomalyFlag = 1
            GROUP BY OrderID
        ) AS a
    ) AS ExpectedSequenceAnomalyOrders,

    SUM(
        CASE
            WHEN PaymentSequenceAnomalyFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedSequenceAnomalyRows,

    SUM(
        CASE
            WHEN UndefinedPaymentTypeFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedUndefinedPaymentTypes,

    SUM(
        CASE
            WHEN ZeroInstallmentFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedZeroInstallments,

    SUM(
        CASE
            WHEN ZeroPaymentValueFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedZeroPaymentValues

FROM #ExpectedFactPayment;
GO


/* =========================================================
   Actual summary
   ========================================================= */

SELECT
    COUNT(*) AS [FactPaymentRows],

    COUNT(DISTINCT OrderID)
        AS DistinctOrders,

    SUM(PaymentCount)
        AS TotalPaymentCount,

    SUM(PaymentAmount)
        AS TotalPaymentAmount,

    (
        SELECT COUNT(*)
        FROM
        (
            SELECT OrderID
            FROM dwh.FactPayment
            WHERE PaymentSequenceAnomalyFlag = 1
            GROUP BY OrderID
        ) AS a
    ) AS SequenceAnomalyOrders,

    SUM(
        CASE
            WHEN PaymentSequenceAnomalyFlag = 1
            THEN 1 ELSE 0
        END
    ) AS SequenceAnomalyRows,

    SUM(
        CASE
            WHEN UndefinedPaymentTypeFlag = 1
            THEN 1 ELSE 0
        END
    ) AS UndefinedPaymentTypeRows,

    SUM(
        CASE
            WHEN ZeroInstallmentFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ZeroInstallmentRows,

    SUM(
        CASE
            WHEN ZeroPaymentValueFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ZeroPaymentValueRows

FROM dwh.FactPayment;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedRows                   INT,
    @ActualRows                     INT,
    @DuplicateNaturalGrain          INT,
    @NullOrderIDs                   INT,
    @InvalidPaymentSequential       INT,

    @MissingExpectedCustomerKeys    INT,
    @MissingExpectedGeographyKeys   INT,

    @InvalidCustomerKeys            INT,
    @InvalidGeographyKeys           INT,
    @InvalidDateKeys                INT,
    @InvalidPaymentCounts           INT,

    @MissingFactOrderMatches        INT,

    @SourceOrdersWithoutPayments    INT,
    @FactOrdersWithoutPayments      INT,

    @SourceToTargetDifferences      INT,
    @TargetToSourceDifferences      INT;


SELECT
    @ExpectedRows = COUNT(*)
FROM #ExpectedFactPayment;


SELECT
    @ActualRows = COUNT(*)
FROM dwh.FactPayment;


SELECT
    @DuplicateNaturalGrain = COUNT(*)
FROM
(
    SELECT
        OrderID,
        PaymentSequential
    FROM dwh.FactPayment
    GROUP BY
        OrderID,
        PaymentSequential
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullOrderIDs = COUNT(*)
FROM dwh.FactPayment
WHERE OrderID IS NULL;


SELECT
    @InvalidPaymentSequential = COUNT(*)
FROM dwh.FactPayment
WHERE PaymentSequential IS NULL
   OR PaymentSequential < 1;


SELECT
    @MissingExpectedCustomerKeys = COUNT(*)
FROM #ExpectedFactPayment
WHERE CustomerKey IS NULL;


SELECT
    @MissingExpectedGeographyKeys = COUNT(*)
FROM #ExpectedFactPayment
WHERE CustomerGeographyKey IS NULL;


SELECT
    @InvalidCustomerKeys = COUNT(*)
FROM dwh.FactPayment AS f

LEFT JOIN dwh.DimCustomer AS d
    ON f.CustomerKey = d.CustomerKey

WHERE d.CustomerKey IS NULL;


SELECT
    @InvalidGeographyKeys = COUNT(*)
FROM dwh.FactPayment AS f

LEFT JOIN dwh.DimGeography AS d
    ON f.CustomerGeographyKey = d.GeographyKey

WHERE d.GeographyKey IS NULL;


SELECT
    @InvalidDateKeys = COUNT(*)
FROM dwh.FactPayment AS f

LEFT JOIN dwh.DimDate AS d
    ON f.PurchaseDateKey = d.DateKey

WHERE d.DateKey IS NULL;


SELECT
    @InvalidPaymentCounts = COUNT(*)
FROM dwh.FactPayment
WHERE PaymentCount <> 1;


SELECT
    @MissingFactOrderMatches = COUNT(*)
FROM dwh.FactPayment AS p

LEFT JOIN dwh.FactOrder AS o
    ON p.OrderID = o.OrderID

WHERE o.OrderID IS NULL;


/* Source orders that genuinely have no payment row */
SELECT
    @SourceOrdersWithoutPayments = COUNT(*)
FROM stg.orders AS o

LEFT JOIN stg.payments AS p
    ON o.order_id = p.order_id

WHERE p.order_id IS NULL;


/* Warehouse orders that have no FactPayment row */
SELECT
    @FactOrdersWithoutPayments = COUNT(*)
FROM dwh.FactOrder AS o

LEFT JOIN dwh.FactPayment AS p
    ON o.OrderID = p.OrderID

WHERE p.OrderID IS NULL;


SELECT
    @SourceToTargetDifferences = COUNT(*)
FROM
(
    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM #ExpectedFactPayment

    EXCEPT

    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM dwh.FactPayment
) AS x;


SELECT
    @TargetToSourceDifferences = COUNT(*)
FROM
(
    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM dwh.FactPayment

    EXCEPT

    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM #ExpectedFactPayment
) AS x;


SELECT
    @ExpectedRows                  AS ExpectedRows,
    @ActualRows                    AS ActualRows,
    @DuplicateNaturalGrain         AS DuplicateNaturalGrain,
    @NullOrderIDs                  AS NullOrderIDs,
    @InvalidPaymentSequential      AS InvalidPaymentSequential,

    @MissingExpectedCustomerKeys   AS MissingExpectedCustomerKeys,
    @MissingExpectedGeographyKeys  AS MissingExpectedGeographyKeys,

    @InvalidCustomerKeys           AS InvalidCustomerKeys,
    @InvalidGeographyKeys          AS InvalidGeographyKeys,
    @InvalidDateKeys               AS InvalidDateKeys,
    @InvalidPaymentCounts          AS InvalidPaymentCounts,

    @MissingFactOrderMatches       AS MissingFactOrderMatches,

    @SourceOrdersWithoutPayments   AS SourceOrdersWithoutPayments,
    @FactOrdersWithoutPayments     AS FactOrdersWithoutPayments,

    @SourceToTargetDifferences     AS SourceToTargetDifferences,
    @TargetToSourceDifferences     AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM dwh.FactPayment
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedFactPayment
)
    THROW 51000,
        'FactPayment validation failed: row count mismatch.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        PaymentSequential
    FROM dwh.FactPayment
    GROUP BY
        OrderID,
        PaymentSequential
    HAVING COUNT(*) > 1
)
    THROW 51001,
        'FactPayment validation failed: duplicate natural grain.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactPayment
    WHERE OrderID IS NULL
       OR PaymentSequential IS NULL
       OR PaymentSequential < 1
)
    THROW 51002,
        'FactPayment validation failed: invalid natural key.',
        1;


IF EXISTS
(
    SELECT 1
    FROM #ExpectedFactPayment
    WHERE CustomerKey IS NULL
       OR CustomerGeographyKey IS NULL
)
    THROW 51003,
        'FactPayment validation failed: dimension resolution failure.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactPayment AS f

    LEFT JOIN dwh.DimCustomer AS c
        ON f.CustomerKey = c.CustomerKey

    LEFT JOIN dwh.DimGeography AS g
        ON f.CustomerGeographyKey = g.GeographyKey

    LEFT JOIN dwh.DimDate AS d
        ON f.PurchaseDateKey = d.DateKey

    WHERE c.CustomerKey IS NULL
       OR g.GeographyKey IS NULL
       OR d.DateKey IS NULL
)
    THROW 51004,
        'FactPayment validation failed: invalid dimension surrogate key.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactPayment
    WHERE PaymentCount <> 1
)
    THROW 51005,
        'FactPayment validation failed: invalid PaymentCount.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactPayment AS p

    LEFT JOIN dwh.FactOrder AS o
        ON p.OrderID = o.OrderID

    WHERE o.OrderID IS NULL
)
    THROW 51006,
        'FactPayment validation failed: OrderID missing from FactOrder.',
        1;


/* The set of orders without payments must remain unchanged */
IF EXISTS
(
    SELECT o.order_id
    FROM stg.orders AS o
    LEFT JOIN stg.payments AS p
        ON o.order_id = p.order_id
    WHERE p.order_id IS NULL

    EXCEPT

    SELECT o.OrderID
    FROM dwh.FactOrder AS o
    LEFT JOIN dwh.FactPayment AS p
        ON o.OrderID = p.OrderID
    WHERE p.OrderID IS NULL
)
    THROW 51007,
        'FactPayment validation failed: source no-payment orders differ from warehouse.',
        1;


IF EXISTS
(
    SELECT o.OrderID
    FROM dwh.FactOrder AS o
    LEFT JOIN dwh.FactPayment AS p
        ON o.OrderID = p.OrderID
    WHERE p.OrderID IS NULL

    EXCEPT

    SELECT o.order_id
    FROM stg.orders AS o
    LEFT JOIN stg.payments AS p
        ON o.order_id = p.order_id
    WHERE p.order_id IS NULL
)
    THROW 51008,
        'FactPayment validation failed: unexpected warehouse no-payment orders.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM #ExpectedFactPayment

    EXCEPT

    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM dwh.FactPayment
)
    THROW 51009,
        'FactPayment validation failed: expected rows missing or different.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM dwh.FactPayment

    EXCEPT

    SELECT
        OrderID,
        PaymentSequential,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        OrderStatus,
        PaymentType,
        PaymentInstallments,
        PaymentAmount,
        PaymentCount,
        PaymentSequenceAnomalyFlag,
        UndefinedPaymentTypeFlag,
        ZeroInstallmentFlag,
        ZeroPaymentValueFlag
    FROM #ExpectedFactPayment
)
    THROW 51010,
        'FactPayment validation failed: unexpected target rows.',
        1;


PRINT 'FACTPAYMENT VALIDATION PASSED.';
GO