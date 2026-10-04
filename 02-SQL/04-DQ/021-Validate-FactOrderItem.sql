USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedFactOrderItem;
GO


/* =========================================================
   Build expected FactOrderItem rows
   ========================================================= */

SELECT
    oi.order_id AS OrderID,
    oi.order_item_id AS OrderItemID,

    dc.CustomerKey,
    dg.GeographyKey AS CustomerGeographyKey,
    dp.ProductKey,
    ds.SellerKey,

    CONVERT(
        INT,
        CONVERT(
            CHAR(8),
            CAST(o.order_purchase_timestamp AS DATE),
            112
        )
    ) AS PurchaseDateKey,

    CONVERT(
        INT,
        CONVERT(
            CHAR(8),
            CAST(oi.shipping_limit_date AS DATE),
            112
        )
    ) AS ShippingLimitDateKey,

    o.order_status AS OrderStatus,

    CAST(oi.shipping_limit_date AS DATETIME2(0))
        AS ShippingLimitTimestamp,

    CAST(oi.price AS DECIMAL(18,2))
        AS PriceAmount,

    CAST(oi.freight_value AS DECIMAL(18,2))
        AS FreightAmount,

    CAST(1 AS TINYINT)
        AS OrderItemCount

INTO #ExpectedFactOrderItem

FROM stg.order_items AS oi

INNER JOIN stg.orders AS o
    ON oi.order_id = o.order_id

INNER JOIN stg.customers AS c
    ON o.customer_id = c.customer_id

LEFT JOIN dwh.DimProduct AS dp
    ON oi.product_id = dp.ProductID

LEFT JOIN dwh.DimSeller AS ds
    ON oi.seller_id = ds.SellerID

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

    SUM(OrderItemCount)
        AS ExpectedOrderItemCount,

    SUM(PriceAmount)
        AS ExpectedPriceAmount,

    SUM(FreightAmount)
        AS ExpectedFreightAmount,

    SUM(
        CASE
            WHEN PriceAmount = 0
            THEN 1 ELSE 0
        END
    ) AS ExpectedZeroPriceRows,

    SUM(
        CASE
            WHEN FreightAmount = 0
            THEN 1 ELSE 0
        END
    ) AS ExpectedZeroFreightRows

FROM #ExpectedFactOrderItem;
GO


/* =========================================================
   Actual summary
   ========================================================= */

SELECT
    COUNT(*) AS [FactOrderItemRows],

    SUM(OrderItemCount)
        AS TotalOrderItemCount,

    SUM(PriceAmount)
        AS TotalPriceAmount,

    SUM(FreightAmount)
        AS TotalFreightAmount,

    SUM(
        CASE
            WHEN PriceAmount = 0
            THEN 1 ELSE 0
        END
    ) AS ZeroPriceRows,

    SUM(
        CASE
            WHEN FreightAmount = 0
            THEN 1 ELSE 0
        END
    ) AS ZeroFreightRows

FROM dwh.FactOrderItem;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedRows                   INT,
    @ActualRows                     INT,
    @DuplicateNaturalGrain          INT,
    @NullOrderIDs                   INT,
    @InvalidOrderItemIDs            INT,
    @MissingExpectedProductKeys     INT,
    @MissingExpectedSellerKeys      INT,
    @MissingExpectedCustomerKeys    INT,
    @MissingExpectedGeographyKeys   INT,
    @InvalidProductKeys             INT,
    @InvalidSellerKeys              INT,
    @InvalidCustomerKeys            INT,
    @InvalidGeographyKeys           INT,
    @InvalidDateKeys                INT,
    @InvalidOrderItemCounts         INT,
    @MissingFactOrderMatches        INT,
    @SourceToTargetDifferences      INT,
    @TargetToSourceDifferences      INT;


SELECT
    @ExpectedRows = COUNT(*)
FROM #ExpectedFactOrderItem;


SELECT
    @ActualRows = COUNT(*)
FROM dwh.FactOrderItem;


SELECT
    @DuplicateNaturalGrain = COUNT(*)
FROM
(
    SELECT
        OrderID,
        OrderItemID
    FROM dwh.FactOrderItem
    GROUP BY
        OrderID,
        OrderItemID
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullOrderIDs = COUNT(*)
FROM dwh.FactOrderItem
WHERE OrderID IS NULL;


SELECT
    @InvalidOrderItemIDs = COUNT(*)
FROM dwh.FactOrderItem
WHERE OrderItemID IS NULL
   OR OrderItemID < 1;


SELECT
    @MissingExpectedProductKeys = COUNT(*)
FROM #ExpectedFactOrderItem
WHERE ProductKey IS NULL;


SELECT
    @MissingExpectedSellerKeys = COUNT(*)
FROM #ExpectedFactOrderItem
WHERE SellerKey IS NULL;


SELECT
    @MissingExpectedCustomerKeys = COUNT(*)
FROM #ExpectedFactOrderItem
WHERE CustomerKey IS NULL;


SELECT
    @MissingExpectedGeographyKeys = COUNT(*)
FROM #ExpectedFactOrderItem
WHERE CustomerGeographyKey IS NULL;


SELECT
    @InvalidProductKeys = COUNT(*)
FROM dwh.FactOrderItem AS f
LEFT JOIN dwh.DimProduct AS d
    ON f.ProductKey = d.ProductKey
WHERE d.ProductKey IS NULL;


SELECT
    @InvalidSellerKeys = COUNT(*)
FROM dwh.FactOrderItem AS f
LEFT JOIN dwh.DimSeller AS d
    ON f.SellerKey = d.SellerKey
WHERE d.SellerKey IS NULL;


SELECT
    @InvalidCustomerKeys = COUNT(*)
FROM dwh.FactOrderItem AS f
LEFT JOIN dwh.DimCustomer AS d
    ON f.CustomerKey = d.CustomerKey
WHERE d.CustomerKey IS NULL;


SELECT
    @InvalidGeographyKeys = COUNT(*)
FROM dwh.FactOrderItem AS f
LEFT JOIN dwh.DimGeography AS d
    ON f.CustomerGeographyKey = d.GeographyKey
WHERE d.GeographyKey IS NULL;


SELECT
    @InvalidDateKeys = COUNT(*)
FROM dwh.FactOrderItem AS f

LEFT JOIN dwh.DimDate AS dp
    ON f.PurchaseDateKey = dp.DateKey

LEFT JOIN dwh.DimDate AS ds
    ON f.ShippingLimitDateKey = ds.DateKey

WHERE dp.DateKey IS NULL
   OR ds.DateKey IS NULL;


SELECT
    @InvalidOrderItemCounts = COUNT(*)
FROM dwh.FactOrderItem
WHERE OrderItemCount <> 1;


SELECT
    @MissingFactOrderMatches = COUNT(*)
FROM dwh.FactOrderItem AS i
LEFT JOIN dwh.FactOrder AS o
    ON i.OrderID = o.OrderID
WHERE o.OrderID IS NULL;


SELECT
    @SourceToTargetDifferences = COUNT(*)
FROM
(
    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM #ExpectedFactOrderItem

    EXCEPT

    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM dwh.FactOrderItem
) AS x;


SELECT
    @TargetToSourceDifferences = COUNT(*)
FROM
(
    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM dwh.FactOrderItem

    EXCEPT

    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM #ExpectedFactOrderItem
) AS x;


SELECT
    @ExpectedRows                  AS ExpectedRows,
    @ActualRows                    AS ActualRows,
    @DuplicateNaturalGrain         AS DuplicateNaturalGrain,
    @NullOrderIDs                  AS NullOrderIDs,
    @InvalidOrderItemIDs           AS InvalidOrderItemIDs,
    @MissingExpectedProductKeys    AS MissingExpectedProductKeys,
    @MissingExpectedSellerKeys     AS MissingExpectedSellerKeys,
    @MissingExpectedCustomerKeys   AS MissingExpectedCustomerKeys,
    @MissingExpectedGeographyKeys  AS MissingExpectedGeographyKeys,
    @InvalidProductKeys            AS InvalidProductKeys,
    @InvalidSellerKeys             AS InvalidSellerKeys,
    @InvalidCustomerKeys           AS InvalidCustomerKeys,
    @InvalidGeographyKeys          AS InvalidGeographyKeys,
    @InvalidDateKeys               AS InvalidDateKeys,
    @InvalidOrderItemCounts        AS InvalidOrderItemCounts,
    @MissingFactOrderMatches       AS MissingFactOrderMatches,
    @SourceToTargetDifferences     AS SourceToTargetDifferences,
    @TargetToSourceDifferences     AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM dwh.FactOrderItem
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedFactOrderItem
)
    THROW 51000,
        'FactOrderItem validation failed: row count mismatch.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        OrderItemID
    FROM dwh.FactOrderItem
    GROUP BY
        OrderID,
        OrderItemID
    HAVING COUNT(*) > 1
)
    THROW 51001,
        'FactOrderItem validation failed: duplicate natural grain.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactOrderItem
    WHERE OrderID IS NULL
       OR OrderItemID IS NULL
       OR OrderItemID < 1
)
    THROW 51002,
        'FactOrderItem validation failed: invalid natural key.',
        1;


IF EXISTS
(
    SELECT 1
    FROM #ExpectedFactOrderItem
    WHERE ProductKey IS NULL
       OR SellerKey IS NULL
       OR CustomerKey IS NULL
       OR CustomerGeographyKey IS NULL
)
    THROW 51003,
        'FactOrderItem validation failed: dimension resolution failure.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactOrderItem
    WHERE OrderItemCount <> 1
)
    THROW 51004,
        'FactOrderItem validation failed: invalid OrderItemCount.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.FactOrderItem AS i
    LEFT JOIN dwh.FactOrder AS o
        ON i.OrderID = o.OrderID
    WHERE o.OrderID IS NULL
)
    THROW 51005,
        'FactOrderItem validation failed: OrderID missing from FactOrder.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM #ExpectedFactOrderItem

    EXCEPT

    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM dwh.FactOrderItem
)
    THROW 51006,
        'FactOrderItem validation failed: expected rows missing or different.',
        1;


IF EXISTS
(
    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM dwh.FactOrderItem

    EXCEPT

    SELECT
        OrderID,
        OrderItemID,
        CustomerKey,
        CustomerGeographyKey,
        ProductKey,
        SellerKey,
        PurchaseDateKey,
        ShippingLimitDateKey,
        OrderStatus,
        ShippingLimitTimestamp,
        PriceAmount,
        FreightAmount,
        OrderItemCount
    FROM #ExpectedFactOrderItem
)
    THROW 51007,
        'FactOrderItem validation failed: unexpected target rows.',
        1;


PRINT 'FACTORDERITEM VALIDATION PASSED.';
GO