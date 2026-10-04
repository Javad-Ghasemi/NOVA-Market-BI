USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedFactOrder;
GO


/* =========================================================
   Build expected FactOrder rows from source + dimensions
   ========================================================= */

SELECT
    o.order_id AS OrderID,

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

    CASE
        WHEN o.order_approved_at IS NULL
            THEN 0
        ELSE CONVERT(
            INT,
            CONVERT(
                CHAR(8),
                CAST(o.order_approved_at AS DATE),
                112
            )
        )
    END AS ApprovedDateKey,

    CASE
        WHEN o.order_delivered_carrier_date IS NULL
            THEN 0
        ELSE CONVERT(
            INT,
            CONVERT(
                CHAR(8),
                CAST(o.order_delivered_carrier_date AS DATE),
                112
            )
        )
    END AS CarrierDateKey,

    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN 0
        ELSE CONVERT(
            INT,
            CONVERT(
                CHAR(8),
                CAST(o.order_delivered_customer_date AS DATE),
                112
            )
        )
    END AS DeliveredDateKey,

    CASE
        WHEN o.order_estimated_delivery_date IS NULL
            THEN 0
        ELSE CONVERT(
            INT,
            CONVERT(
                CHAR(8),
                o.order_estimated_delivery_date,
                112
            )
        )
    END AS EstimatedDeliveryDateKey,

    o.order_status AS OrderStatus,

    CAST(o.order_purchase_timestamp AS DATETIME2(0))
        AS PurchaseTimestamp,

    CAST(o.order_approved_at AS DATETIME2(0))
        AS ApprovedTimestamp,

    CAST(o.order_delivered_carrier_date AS DATETIME2(0))
        AS DeliveredCarrierTimestamp,

    CAST(o.order_delivered_customer_date AS DATETIME2(0))
        AS DeliveredCustomerTimestamp,

    o.order_estimated_delivery_date
        AS EstimatedDeliveryDate,

    CAST(1 AS TINYINT)
        AS OrderCount,

    CAST(
        CASE
            WHEN o.order_delivered_carrier_date IS NOT NULL
             AND o.order_delivered_carrier_date
                 < o.order_purchase_timestamp
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS CarrierBeforePurchaseFlag,

    CAST(
        CASE
            WHEN o.order_approved_at IS NOT NULL
             AND o.order_delivered_carrier_date IS NOT NULL
             AND o.order_delivered_carrier_date
                 < o.order_approved_at
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS CarrierBeforeApprovalFlag,

    CAST(
        CASE
            WHEN o.order_delivered_carrier_date IS NOT NULL
             AND o.order_delivered_customer_date IS NOT NULL
             AND o.order_delivered_customer_date
                 < o.order_delivered_carrier_date
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS DeliveredBeforeCarrierFlag,

    CAST(
        CASE
            WHEN o.order_delivered_customer_date IS NULL
                THEN NULL

            WHEN CAST(o.order_delivered_customer_date AS DATE)
                 > o.order_estimated_delivery_date
                THEN 1

            ELSE 0
        END
        AS BIT
    ) AS DeliveredLateFlag

INTO #ExpectedFactOrder

FROM stg.orders AS o

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
    COUNT(*) AS ExpectedBusinessRows,

    SUM(CASE WHEN ApprovedDateKey = 0 THEN 1 ELSE 0 END)
        AS ExpectedUnknownApprovedDates,

    SUM(CASE WHEN CarrierDateKey = 0 THEN 1 ELSE 0 END)
        AS ExpectedUnknownCarrierDates,

    SUM(CASE WHEN DeliveredDateKey = 0 THEN 1 ELSE 0 END)
        AS ExpectedUnknownDeliveredDates,

    SUM(CASE WHEN EstimatedDeliveryDateKey = 0 THEN 1 ELSE 0 END)
        AS ExpectedUnknownEstimatedDates,

    SUM(CASE WHEN CarrierBeforePurchaseFlag = 1 THEN 1 ELSE 0 END)
        AS ExpectedCarrierBeforePurchase,

    SUM(CASE WHEN CarrierBeforeApprovalFlag = 1 THEN 1 ELSE 0 END)
        AS ExpectedCarrierBeforeApproval,

    SUM(CASE WHEN DeliveredBeforeCarrierFlag = 1 THEN 1 ELSE 0 END)
        AS ExpectedDeliveredBeforeCarrier,

    SUM(CASE WHEN DeliveredLateFlag = 1 THEN 1 ELSE 0 END)
        AS ExpectedDeliveredLate,

    SUM(CASE WHEN DeliveredLateFlag IS NULL THEN 1 ELSE 0 END)
        AS ExpectedUndeliveredLateStatus

FROM #ExpectedFactOrder;
GO


/* =========================================================
   Actual summary
   ========================================================= */

SELECT
    COUNT(*) AS [FactOrderRows],
    COUNT(DISTINCT OrderID) AS DistinctOrderIDs,
    SUM(OrderCount) AS TotalOrderCount,

    SUM(CASE WHEN ApprovedDateKey = 0 THEN 1 ELSE 0 END)
        AS UnknownApprovedDates,

    SUM(CASE WHEN CarrierDateKey = 0 THEN 1 ELSE 0 END)
        AS UnknownCarrierDates,

    SUM(CASE WHEN DeliveredDateKey = 0 THEN 1 ELSE 0 END)
        AS UnknownDeliveredDates,

    SUM(CASE WHEN EstimatedDeliveryDateKey = 0 THEN 1 ELSE 0 END)
        AS UnknownEstimatedDates,

    SUM(CASE WHEN CarrierBeforePurchaseFlag = 1 THEN 1 ELSE 0 END)
        AS CarrierBeforePurchase,

    SUM(CASE WHEN CarrierBeforeApprovalFlag = 1 THEN 1 ELSE 0 END)
        AS CarrierBeforeApproval,

    SUM(CASE WHEN DeliveredBeforeCarrierFlag = 1 THEN 1 ELSE 0 END)
        AS DeliveredBeforeCarrier,

    SUM(CASE WHEN DeliveredLateFlag = 1 THEN 1 ELSE 0 END)
        AS DeliveredLate,

    SUM(CASE WHEN DeliveredLateFlag IS NULL THEN 1 ELSE 0 END)
        AS UndeliveredLateStatus

FROM dwh.FactOrder;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedRows                    INT,
    @ActualRows                      INT,
    @DuplicateOrderIDs               INT,
    @NullOrderIDs                    INT,
    @MissingExpectedCustomerKeys     INT,
    @MissingExpectedGeographyKeys    INT,
    @InvalidCustomerKeys             INT,
    @InvalidGeographyKeys            INT,
    @InvalidDateKeys                 INT,
    @InvalidOrderCounts              INT,
    @SourceToTargetDifferences       INT,
    @TargetToSourceDifferences       INT;


SELECT
    @ExpectedRows = COUNT(*)
FROM #ExpectedFactOrder;


SELECT
    @ActualRows = COUNT(*)
FROM dwh.FactOrder;


SELECT
    @DuplicateOrderIDs = COUNT(*)
FROM
(
    SELECT OrderID
    FROM dwh.FactOrder
    GROUP BY OrderID
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullOrderIDs = COUNT(*)
FROM dwh.FactOrder
WHERE OrderID IS NULL;


SELECT
    @MissingExpectedCustomerKeys = COUNT(*)
FROM #ExpectedFactOrder
WHERE CustomerKey IS NULL;


SELECT
    @MissingExpectedGeographyKeys = COUNT(*)
FROM #ExpectedFactOrder
WHERE CustomerGeographyKey IS NULL;


SELECT
    @InvalidCustomerKeys = COUNT(*)
FROM dwh.FactOrder AS f
LEFT JOIN dwh.DimCustomer AS c
    ON f.CustomerKey = c.CustomerKey
WHERE c.CustomerKey IS NULL;


SELECT
    @InvalidGeographyKeys = COUNT(*)
FROM dwh.FactOrder AS f
LEFT JOIN dwh.DimGeography AS g
    ON f.CustomerGeographyKey = g.GeographyKey
WHERE g.GeographyKey IS NULL;


SELECT
    @InvalidDateKeys = COUNT(*)
FROM dwh.FactOrder AS f

LEFT JOIN dwh.DimDate AS dp
    ON f.PurchaseDateKey = dp.DateKey

LEFT JOIN dwh.DimDate AS da
    ON f.ApprovedDateKey = da.DateKey

LEFT JOIN dwh.DimDate AS dcarr
    ON f.CarrierDateKey = dcarr.DateKey

LEFT JOIN dwh.DimDate AS ddel
    ON f.DeliveredDateKey = ddel.DateKey

LEFT JOIN dwh.DimDate AS dest
    ON f.EstimatedDeliveryDateKey = dest.DateKey

WHERE dp.DateKey IS NULL
   OR da.DateKey IS NULL
   OR dcarr.DateKey IS NULL
   OR ddel.DateKey IS NULL
   OR dest.DateKey IS NULL;


SELECT
    @InvalidOrderCounts = COUNT(*)
FROM dwh.FactOrder
WHERE OrderCount <> 1;


SELECT
    @SourceToTargetDifferences = COUNT(*)
FROM
(
    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM #ExpectedFactOrder

    EXCEPT

    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM dwh.FactOrder
) AS x;


SELECT
    @TargetToSourceDifferences = COUNT(*)
FROM
(
    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM dwh.FactOrder

    EXCEPT

    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM #ExpectedFactOrder
) AS x;


SELECT
    @ExpectedRows                  AS ExpectedRows,
    @ActualRows                    AS ActualRows,
    @DuplicateOrderIDs             AS DuplicateOrderIDs,
    @NullOrderIDs                  AS NullOrderIDs,
    @MissingExpectedCustomerKeys   AS MissingExpectedCustomerKeys,
    @MissingExpectedGeographyKeys  AS MissingExpectedGeographyKeys,
    @InvalidCustomerKeys           AS InvalidCustomerKeys,
    @InvalidGeographyKeys          AS InvalidGeographyKeys,
    @InvalidDateKeys               AS InvalidDateKeys,
    @InvalidOrderCounts            AS InvalidOrderCounts,
    @SourceToTargetDifferences     AS SourceToTargetDifferences,
    @TargetToSourceDifferences     AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM dwh.FactOrder
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedFactOrder
)
    THROW 51000,
        'FactOrder validation failed: row count mismatch.',
        1;


IF EXISTS
(
    SELECT OrderID
    FROM dwh.FactOrder
    GROUP BY OrderID
    HAVING COUNT(*) > 1
)
    THROW 51001,
        'FactOrder validation failed: duplicate OrderID.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactOrder
    WHERE OrderID IS NULL
)
    THROW 51002,
        'FactOrder validation failed: NULL OrderID.',
        1;


IF EXISTS
(
    SELECT 1
    FROM #ExpectedFactOrder
    WHERE CustomerKey IS NULL
)
    THROW 51003,
        'FactOrder validation failed: customer did not resolve.',
        1;


IF EXISTS
(
    SELECT 1
    FROM #ExpectedFactOrder
    WHERE CustomerGeographyKey IS NULL
)
    THROW 51004,
        'FactOrder validation failed: customer geography did not resolve.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactOrder
    WHERE OrderCount <> 1
)
    THROW 51005,
        'FactOrder validation failed: invalid OrderCount.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM #ExpectedFactOrder

    EXCEPT

    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM dwh.FactOrder
)
    THROW 51006,
        'FactOrder validation failed: expected rows missing or different.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM dwh.FactOrder

    EXCEPT

    SELECT
        OrderID,
        CustomerKey,
        CustomerGeographyKey,
        PurchaseDateKey,
        ApprovedDateKey,
        CarrierDateKey,
        DeliveredDateKey,
        EstimatedDeliveryDateKey,
        OrderStatus,
        PurchaseTimestamp,
        ApprovedTimestamp,
        DeliveredCarrierTimestamp,
        DeliveredCustomerTimestamp,
        EstimatedDeliveryDate,
        OrderCount,
        CarrierBeforePurchaseFlag,
        CarrierBeforeApprovalFlag,
        DeliveredBeforeCarrierFlag,
        DeliveredLateFlag
    FROM #ExpectedFactOrder
)
    THROW 51007,
        'FactOrder validation failed: unexpected target rows.',
        1;


PRINT 'FACTORDER VALIDATION PASSED.';
GO