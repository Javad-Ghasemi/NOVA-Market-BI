USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateFactOrderItem

   Purpose:
   - Single source of truth for FactOrderItem DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateFactOrderItem
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected FactOrderItem rows
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedFactOrderItem;

    SELECT
        oi.order_id AS OrderID,
        oi.order_item_id AS OrderItemID,

        dc.CustomerKey,
        dg.GeographyKey AS CustomerGeographyKey,
        dp.ProductKey,
        ds.SellerKey,

        CONVERT
        (
            int,
            CONVERT
            (
                char(8),
                CAST(o.order_purchase_timestamp AS date),
                112
            )
        ) AS PurchaseDateKey,

        CONVERT
        (
            int,
            CONVERT
            (
                char(8),
                CAST(oi.shipping_limit_date AS date),
                112
            )
        ) AS ShippingLimitDateKey,

        o.order_status AS OrderStatus,

        CAST(oi.shipping_limit_date AS datetime2(0))
            AS ShippingLimitTimestamp,

        CAST(oi.price AS decimal(18,2))
            AS PriceAmount,

        CAST(oi.freight_value AS decimal(18,2))
            AS FreightAmount,

        CAST(1 AS tinyint)
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


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @SourceRows                         bigint,
        @ExpectedRows                       bigint,
        @ActualRows                         bigint,

        @DuplicateNaturalGrain              bigint,
        @NullOrderIDs                       bigint,
        @InvalidOrderItemIDs                bigint,

        @MissingExpectedProductKeys         bigint,
        @MissingExpectedSellerKeys          bigint,
        @MissingExpectedCustomerKeys        bigint,
        @MissingExpectedGeographyKeys       bigint,

        @InvalidProductKeys                 bigint,
        @InvalidSellerKeys                  bigint,
        @InvalidCustomerKeys                bigint,
        @InvalidGeographyKeys               bigint,
        @InvalidDateKeys                    bigint,

        @InvalidOrderItemCounts             bigint,
        @MissingFactOrderMatches            bigint,

        @ExpectedPriceAmount                decimal(38,2),
        @ActualPriceAmount                  decimal(38,2),

        @ExpectedFreightAmount              decimal(38,2),
        @ActualFreightAmount                decimal(38,2),

        @ExpectedZeroPriceRows              bigint,
        @ActualZeroPriceRows                bigint,

        @ExpectedZeroFreightRows            bigint,
        @ActualZeroFreightRows              bigint,

        @SourceToTargetDifferences          bigint,
        @TargetToSourceDifferences          bigint;


    /* =====================================================
       Source / expected metrics
       ===================================================== */

    SELECT
        @SourceRows = COUNT_BIG(*)
    FROM stg.order_items;


    SELECT
        @ExpectedRows = COUNT_BIG(*),

        @ExpectedPriceAmount =
            COALESCE(SUM(CAST(PriceAmount AS decimal(38,2))), 0),

        @ExpectedFreightAmount =
            COALESCE(SUM(CAST(FreightAmount AS decimal(38,2))), 0),

        @ExpectedZeroPriceRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN PriceAmount = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedZeroFreightRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN FreightAmount = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedFactOrderItem;


    /* =====================================================
       Actual metrics
       ===================================================== */

    SELECT
        @ActualRows = COUNT_BIG(*),

        @ActualPriceAmount =
            COALESCE(SUM(CAST(PriceAmount AS decimal(38,2))), 0),

        @ActualFreightAmount =
            COALESCE(SUM(CAST(FreightAmount AS decimal(38,2))), 0),

        @ActualZeroPriceRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN PriceAmount = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualZeroFreightRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN FreightAmount = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.FactOrderItem;


    /* =====================================================
       Natural grain
       ===================================================== */

    SELECT
        @DuplicateNaturalGrain = COUNT_BIG(*)

    FROM
    (
        SELECT
            OrderID,
            OrderItemID

        FROM dwh.FactOrderItem

        GROUP BY
            OrderID,
            OrderItemID

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullOrderIDs = COUNT_BIG(*)

    FROM dwh.FactOrderItem

    WHERE OrderID IS NULL;


    SELECT
        @InvalidOrderItemIDs = COUNT_BIG(*)

    FROM dwh.FactOrderItem

    WHERE OrderItemID IS NULL
       OR OrderItemID < 1;


    /* =====================================================
       Expected dimension resolution
       ===================================================== */

    SELECT
        @MissingExpectedProductKeys = COUNT_BIG(*)
    FROM #ExpectedFactOrderItem
    WHERE ProductKey IS NULL;


    SELECT
        @MissingExpectedSellerKeys = COUNT_BIG(*)
    FROM #ExpectedFactOrderItem
    WHERE SellerKey IS NULL;


    SELECT
        @MissingExpectedCustomerKeys = COUNT_BIG(*)
    FROM #ExpectedFactOrderItem
    WHERE CustomerKey IS NULL;


    SELECT
        @MissingExpectedGeographyKeys = COUNT_BIG(*)
    FROM #ExpectedFactOrderItem
    WHERE CustomerGeographyKey IS NULL;


    /* =====================================================
       Actual dimension-key integrity

       All four keys are mandatory for FactOrderItem.
       Unknown key 0 is therefore invalid here.
       ===================================================== */

    SELECT
        @InvalidProductKeys = COUNT_BIG(*)

    FROM dwh.FactOrderItem AS f

    LEFT JOIN dwh.DimProduct AS d
        ON f.ProductKey = d.ProductKey

    WHERE f.ProductKey = 0
       OR d.ProductKey IS NULL;


    SELECT
        @InvalidSellerKeys = COUNT_BIG(*)

    FROM dwh.FactOrderItem AS f

    LEFT JOIN dwh.DimSeller AS d
        ON f.SellerKey = d.SellerKey

    WHERE f.SellerKey = 0
       OR d.SellerKey IS NULL;


    SELECT
        @InvalidCustomerKeys = COUNT_BIG(*)

    FROM dwh.FactOrderItem AS f

    LEFT JOIN dwh.DimCustomer AS d
        ON f.CustomerKey = d.CustomerKey

    WHERE f.CustomerKey = 0
       OR d.CustomerKey IS NULL;


    SELECT
        @InvalidGeographyKeys = COUNT_BIG(*)

    FROM dwh.FactOrderItem AS f

    LEFT JOIN dwh.DimGeography AS d
        ON f.CustomerGeographyKey = d.GeographyKey

    WHERE f.CustomerGeographyKey = 0
       OR d.GeographyKey IS NULL;


    /* =====================================================
       Date-key integrity

       Purchase and ShippingLimit dates are mandatory for
       FactOrderItem, so DateKey 0 is invalid for these roles.
       ===================================================== */

    SELECT
        @InvalidDateKeys = COUNT_BIG(*)

    FROM dwh.FactOrderItem AS f

    LEFT JOIN dwh.DimDate AS dp
        ON f.PurchaseDateKey = dp.DateKey

    LEFT JOIN dwh.DimDate AS ds
        ON f.ShippingLimitDateKey = ds.DateKey

    WHERE f.PurchaseDateKey = 0
       OR f.ShippingLimitDateKey = 0
       OR dp.DateKey IS NULL
       OR ds.DateKey IS NULL;


    /* =====================================================
       Additive counter
       ===================================================== */

    SELECT
        @InvalidOrderItemCounts = COUNT_BIG(*)

    FROM dwh.FactOrderItem

    WHERE OrderItemCount <> 1;


    /* =====================================================
       FactOrder coverage
       ===================================================== */

    SELECT
        @MissingFactOrderMatches = COUNT_BIG(*)

    FROM dwh.FactOrderItem AS i

    LEFT JOIN dwh.FactOrder AS o
        ON i.OrderID = o.OrderID

    WHERE o.OrderID IS NULL;


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Diagnostic summary
       ===================================================== */

    SELECT
        @SourceRows
            AS SourceRows,

        @ExpectedRows
            AS ExpectedRows,

        @ActualRows
            AS ActualRows,

        @DuplicateNaturalGrain
            AS DuplicateNaturalGrain,

        @NullOrderIDs
            AS NullOrderIDs,

        @InvalidOrderItemIDs
            AS InvalidOrderItemIDs,

        @MissingExpectedProductKeys
            AS MissingExpectedProductKeys,

        @MissingExpectedSellerKeys
            AS MissingExpectedSellerKeys,

        @MissingExpectedCustomerKeys
            AS MissingExpectedCustomerKeys,

        @MissingExpectedGeographyKeys
            AS MissingExpectedGeographyKeys,

        @InvalidProductKeys
            AS InvalidProductKeys,

        @InvalidSellerKeys
            AS InvalidSellerKeys,

        @InvalidCustomerKeys
            AS InvalidCustomerKeys,

        @InvalidGeographyKeys
            AS InvalidGeographyKeys,

        @InvalidDateKeys
            AS InvalidDateKeys,

        @InvalidOrderItemCounts
            AS InvalidOrderItemCounts,

        @MissingFactOrderMatches
            AS MissingFactOrderMatches,

        @ExpectedPriceAmount
            AS ExpectedPriceAmount,

        @ActualPriceAmount
            AS ActualPriceAmount,

        @ExpectedFreightAmount
            AS ExpectedFreightAmount,

        @ActualFreightAmount
            AS ActualFreightAmount,

        @ExpectedZeroPriceRows
            AS ExpectedZeroPriceRows,

        @ActualZeroPriceRows
            AS ActualZeroPriceRows,

        @ExpectedZeroFreightRows
            AS ExpectedZeroFreightRows,

        @ActualZeroFreightRows
            AS ActualZeroFreightRows,

        @SourceToTargetDifferences
            AS SourceToTargetDifferences,

        @TargetToSourceDifferences
            AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @SourceRows <> 112650
    BEGIN
        THROW 51240,
            'FactOrderItem validation failed: staging order-item baseline row count changed.',
            1;
    END;


    IF @ExpectedRows <> @SourceRows
    BEGIN
        THROW 51241,
            'FactOrderItem validation failed: expected-row construction lost or duplicated source rows.',
            1;
    END;


    IF @ActualRows <> @ExpectedRows
    BEGIN
        THROW 51242,
            'FactOrderItem validation failed: row count mismatch.',
            1;
    END;


    IF @DuplicateNaturalGrain <> 0
       OR @NullOrderIDs <> 0
       OR @InvalidOrderItemIDs <> 0
    BEGIN
        THROW 51243,
            'FactOrderItem validation failed: invalid natural grain.',
            1;
    END;


    IF @MissingExpectedProductKeys <> 0
       OR @MissingExpectedSellerKeys <> 0
       OR @MissingExpectedCustomerKeys <> 0
       OR @MissingExpectedGeographyKeys <> 0
    BEGIN
        THROW 51244,
            'FactOrderItem validation failed: expected dimension resolution failure.',
            1;
    END;


    IF @InvalidProductKeys <> 0
       OR @InvalidSellerKeys <> 0
       OR @InvalidCustomerKeys <> 0
       OR @InvalidGeographyKeys <> 0
    BEGIN
        THROW 51245,
            'FactOrderItem validation failed: invalid dimension key detected.',
            1;
    END;


    IF @InvalidDateKeys <> 0
    BEGIN
        THROW 51246,
            'FactOrderItem validation failed: invalid DateKey detected.',
            1;
    END;


    IF @InvalidOrderItemCounts <> 0
    BEGIN
        THROW 51247,
            'FactOrderItem validation failed: invalid OrderItemCount.',
            1;
    END;


    IF @MissingFactOrderMatches <> 0
    BEGIN
        THROW 51248,
            'FactOrderItem validation failed: OrderID missing from FactOrder.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51249,
            'FactOrderItem validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51250,
            'FactOrderItem validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist monetary profile
       ===================================================== */

    IF @ExpectedPriceAmount <> CAST(13591643.70 AS decimal(38,2))
       OR @ActualPriceAmount <> CAST(13591643.70 AS decimal(38,2))
    BEGIN
        THROW 51251,
            'FactOrderItem validation failed: unexpected total price profile.',
            1;
    END;


    IF @ExpectedFreightAmount <> CAST(2251909.54 AS decimal(38,2))
       OR @ActualFreightAmount <> CAST(2251909.54 AS decimal(38,2))
    BEGIN
        THROW 51252,
            'FactOrderItem validation failed: unexpected total freight profile.',
            1;
    END;


    IF @ExpectedZeroFreightRows <> 383
       OR @ActualZeroFreightRows <> 383
    BEGIN
        THROW 51253,
            'FactOrderItem validation failed: unexpected zero-freight profile.',
            1;
    END;


    IF @ExpectedZeroPriceRows <> @ActualZeroPriceRows
    BEGIN
        THROW 51254,
            'FactOrderItem validation failed: zero-price profile differs between source and target.',
            1;
    END;


    PRINT 'FACT ORDER ITEM VALIDATION PASSED.';
END;
GO