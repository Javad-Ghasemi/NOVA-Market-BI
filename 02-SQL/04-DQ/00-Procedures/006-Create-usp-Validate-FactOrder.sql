USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateFactOrder

   Purpose:
   - Single source of truth for FactOrder DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateFactOrder
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected FactOrder rows
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedFactOrder;

    SELECT
        o.order_id AS OrderID,

        dc.CustomerKey,
        dg.GeographyKey AS CustomerGeographyKey,

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

        CASE
            WHEN o.order_approved_at IS NULL
                THEN 0
            ELSE
                CONVERT
                (
                    int,
                    CONVERT
                    (
                        char(8),
                        CAST(o.order_approved_at AS date),
                        112
                    )
                )
        END AS ApprovedDateKey,

        CASE
            WHEN o.order_delivered_carrier_date IS NULL
                THEN 0
            ELSE
                CONVERT
                (
                    int,
                    CONVERT
                    (
                        char(8),
                        CAST(o.order_delivered_carrier_date AS date),
                        112
                    )
                )
        END AS CarrierDateKey,

        CASE
            WHEN o.order_delivered_customer_date IS NULL
                THEN 0
            ELSE
                CONVERT
                (
                    int,
                    CONVERT
                    (
                        char(8),
                        CAST(o.order_delivered_customer_date AS date),
                        112
                    )
                )
        END AS DeliveredDateKey,

        CASE
            WHEN o.order_estimated_delivery_date IS NULL
                THEN 0
            ELSE
                CONVERT
                (
                    int,
                    CONVERT
                    (
                        char(8),
                        o.order_estimated_delivery_date,
                        112
                    )
                )
        END AS EstimatedDeliveryDateKey,

        o.order_status AS OrderStatus,

        CAST(o.order_purchase_timestamp AS datetime2(0))
            AS PurchaseTimestamp,

        CAST(o.order_approved_at AS datetime2(0))
            AS ApprovedTimestamp,

        CAST(o.order_delivered_carrier_date AS datetime2(0))
            AS DeliveredCarrierTimestamp,

        CAST(o.order_delivered_customer_date AS datetime2(0))
            AS DeliveredCustomerTimestamp,

        o.order_estimated_delivery_date
            AS EstimatedDeliveryDate,

        CAST(1 AS tinyint)
            AS OrderCount,

        CAST
        (
            CASE
                WHEN o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_delivered_carrier_date
                     < o.order_purchase_timestamp
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS CarrierBeforePurchaseFlag,

        CAST
        (
            CASE
                WHEN o.order_approved_at IS NOT NULL
                 AND o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_delivered_carrier_date
                     < o.order_approved_at
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS CarrierBeforeApprovalFlag,

        CAST
        (
            CASE
                WHEN o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_delivered_customer_date IS NOT NULL
                 AND o.order_delivered_customer_date
                     < o.order_delivered_carrier_date
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS DeliveredBeforeCarrierFlag,

        CAST
        (
            CASE
                WHEN o.order_delivered_customer_date IS NULL
                    THEN NULL

                WHEN CAST(o.order_delivered_customer_date AS date)
                     > o.order_estimated_delivery_date
                    THEN 1

                ELSE 0
            END
            AS bit
        ) AS DeliveredLateFlag

    INTO #ExpectedFactOrder

    FROM stg.orders AS o

    INNER JOIN stg.customers AS c
        ON o.customer_id = c.customer_id

    LEFT JOIN dwh.DimCustomer AS dc
        ON c.customer_unique_id = dc.CustomerUniqueID

    LEFT JOIN dwh.DimGeography AS dg
        ON c.customer_zip_code_prefix = dg.ZipCodePrefix;


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @SourceOrderRows                  bigint,
        @ExpectedRows                     bigint,
        @ActualRows                       bigint,
        @DistinctOrderIDs                 bigint,

        @DuplicateOrderIDs                bigint,
        @NullOrderIDs                     bigint,

        @MissingExpectedCustomerKeys      bigint,
        @MissingExpectedGeographyKeys     bigint,

        @InvalidCustomerKeys              bigint,
        @InvalidGeographyKeys             bigint,
        @InvalidDateKeys                  bigint,
        @InvalidOrderCounts               bigint,

        @ExpectedCarrierBeforePurchase    bigint,
        @ActualCarrierBeforePurchase      bigint,

        @ExpectedCarrierBeforeApproval    bigint,
        @ActualCarrierBeforeApproval      bigint,

        @ExpectedDeliveredBeforeCarrier   bigint,
        @ActualDeliveredBeforeCarrier     bigint,

        @ExpectedDeliveredLate            bigint,
        @ActualDeliveredLate              bigint,

        @ExpectedUndeliveredLateStatus    bigint,
        @ActualUndeliveredLateStatus      bigint,

        @SourceToTargetDifferences        bigint,
        @TargetToSourceDifferences        bigint;


    /* =====================================================
       Source / target row counts
       ===================================================== */

    SELECT
        @SourceOrderRows = COUNT_BIG(*)
    FROM stg.orders;


    SELECT
        @ExpectedRows = COUNT_BIG(*),

        @ExpectedCarrierBeforePurchase =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN CarrierBeforePurchaseFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedCarrierBeforeApproval =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN CarrierBeforeApprovalFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedDeliveredBeforeCarrier =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DeliveredBeforeCarrierFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedDeliveredLate =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DeliveredLateFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedUndeliveredLateStatus =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DeliveredLateFlag IS NULL
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedFactOrder;


    SELECT
        @ActualRows = COUNT_BIG(*),

        @ActualCarrierBeforePurchase =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN CarrierBeforePurchaseFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualCarrierBeforeApproval =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN CarrierBeforeApprovalFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualDeliveredBeforeCarrier =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DeliveredBeforeCarrierFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualDeliveredLate =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DeliveredLateFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualUndeliveredLateStatus =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DeliveredLateFlag IS NULL
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.FactOrder;


    SELECT
        @DistinctOrderIDs =
            COUNT_BIG(DISTINCT OrderID)
    FROM dwh.FactOrder;


    /* =====================================================
       Fact grain
       ===================================================== */

    SELECT
        @DuplicateOrderIDs = COUNT_BIG(*)
    FROM
    (
        SELECT OrderID
        FROM dwh.FactOrder
        GROUP BY OrderID
        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullOrderIDs = COUNT_BIG(*)
    FROM dwh.FactOrder
    WHERE OrderID IS NULL;


    /* =====================================================
       Expected dimension resolution
       ===================================================== */

    SELECT
        @MissingExpectedCustomerKeys = COUNT_BIG(*)
    FROM #ExpectedFactOrder
    WHERE CustomerKey IS NULL;


    SELECT
        @MissingExpectedGeographyKeys = COUNT_BIG(*)
    FROM #ExpectedFactOrder
    WHERE CustomerGeographyKey IS NULL;


    /* =====================================================
       Actual dimension-key integrity
       ===================================================== */

    SELECT
        @InvalidCustomerKeys = COUNT_BIG(*)

    FROM dwh.FactOrder AS f

    LEFT JOIN dwh.DimCustomer AS c
        ON f.CustomerKey = c.CustomerKey

    WHERE f.CustomerKey = 0
       OR c.CustomerKey IS NULL;


    SELECT
        @InvalidGeographyKeys = COUNT_BIG(*)

    FROM dwh.FactOrder AS f

    LEFT JOIN dwh.DimGeography AS g
        ON f.CustomerGeographyKey = g.GeographyKey

    WHERE f.CustomerGeographyKey = 0
       OR g.GeographyKey IS NULL;


    /* =====================================================
       Date-key integrity

       DateKey = 0 is valid for nullable date roles because
       DimDate contains the Unknown member.
       ===================================================== */

    SELECT
        @InvalidDateKeys = COUNT_BIG(*)

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


    /* =====================================================
       Additive counter integrity
       ===================================================== */

    SELECT
        @InvalidOrderCounts = COUNT_BIG(*)

    FROM dwh.FactOrder

    WHERE OrderCount <> 1;


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Diagnostic summary
       ===================================================== */

    SELECT
        @SourceOrderRows
            AS SourceOrderRows,

        @ExpectedRows
            AS ExpectedRows,

        @ActualRows
            AS ActualRows,

        @DistinctOrderIDs
            AS DistinctOrderIDs,

        @DuplicateOrderIDs
            AS DuplicateOrderIDs,

        @NullOrderIDs
            AS NullOrderIDs,

        @MissingExpectedCustomerKeys
            AS MissingExpectedCustomerKeys,

        @MissingExpectedGeographyKeys
            AS MissingExpectedGeographyKeys,

        @InvalidCustomerKeys
            AS InvalidCustomerKeys,

        @InvalidGeographyKeys
            AS InvalidGeographyKeys,

        @InvalidDateKeys
            AS InvalidDateKeys,

        @InvalidOrderCounts
            AS InvalidOrderCounts,

        @ExpectedCarrierBeforePurchase
            AS ExpectedCarrierBeforePurchase,

        @ActualCarrierBeforePurchase
            AS ActualCarrierBeforePurchase,

        @ExpectedCarrierBeforeApproval
            AS ExpectedCarrierBeforeApproval,

        @ActualCarrierBeforeApproval
            AS ActualCarrierBeforeApproval,

        @ExpectedDeliveredBeforeCarrier
            AS ExpectedDeliveredBeforeCarrier,

        @ActualDeliveredBeforeCarrier
            AS ActualDeliveredBeforeCarrier,

        @ExpectedDeliveredLate
            AS ExpectedDeliveredLate,

        @ActualDeliveredLate
            AS ActualDeliveredLate,

        @ExpectedUndeliveredLateStatus
            AS ExpectedUndeliveredLateStatus,

        @ActualUndeliveredLateStatus
            AS ActualUndeliveredLateStatus,

        @SourceToTargetDifferences
            AS SourceToTargetDifferences,

        @TargetToSourceDifferences
            AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @SourceOrderRows <> 99441
    BEGIN
        THROW 51220,
            'FactOrder validation failed: staging Order baseline row count changed.',
            1;
    END;


    IF @ExpectedRows <> @SourceOrderRows
    BEGIN
        THROW 51221,
            'FactOrder validation failed: expected-row construction lost or duplicated source orders.',
            1;
    END;


    IF @ActualRows <> @ExpectedRows
    BEGIN
        THROW 51222,
            'FactOrder validation failed: row count mismatch.',
            1;
    END;


    IF @DistinctOrderIDs <> @ExpectedRows
       OR @DuplicateOrderIDs <> 0
       OR @NullOrderIDs <> 0
    BEGIN
        THROW 51223,
            'FactOrder validation failed: invalid OrderID grain.',
            1;
    END;


    IF @MissingExpectedCustomerKeys <> 0
    BEGIN
        THROW 51224,
            'FactOrder validation failed: expected customer did not resolve.',
            1;
    END;


    IF @MissingExpectedGeographyKeys <> 0
    BEGIN
        THROW 51225,
            'FactOrder validation failed: expected customer geography did not resolve.',
            1;
    END;


    IF @InvalidCustomerKeys <> 0
    BEGIN
        THROW 51226,
            'FactOrder validation failed: invalid CustomerKey detected.',
            1;
    END;


    IF @InvalidGeographyKeys <> 0
    BEGIN
        THROW 51227,
            'FactOrder validation failed: invalid CustomerGeographyKey detected.',
            1;
    END;


    IF @InvalidDateKeys <> 0
    BEGIN
        THROW 51228,
            'FactOrder validation failed: invalid DateKey detected.',
            1;
    END;


    IF @InvalidOrderCounts <> 0
    BEGIN
        THROW 51229,
            'FactOrder validation failed: invalid OrderCount.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51230,
            'FactOrder validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51231,
            'FactOrder validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist temporal anomaly profile
       ===================================================== */

    IF @ExpectedCarrierBeforePurchase <> 166
       OR @ActualCarrierBeforePurchase <> 166
    BEGIN
        THROW 51232,
            'FactOrder validation failed: unexpected carrier-before-purchase profile.',
            1;
    END;


    IF @ExpectedCarrierBeforeApproval <> 1359
       OR @ActualCarrierBeforeApproval <> 1359
    BEGIN
        THROW 51233,
            'FactOrder validation failed: unexpected carrier-before-approval profile.',
            1;
    END;


    IF @ExpectedDeliveredBeforeCarrier <> 23
       OR @ActualDeliveredBeforeCarrier <> 23
    BEGIN
        THROW 51234,
            'FactOrder validation failed: unexpected delivered-before-carrier profile.',
            1;
    END;


    IF @ExpectedDeliveredLate <> 6535
       OR @ActualDeliveredLate <> 6535
    BEGIN
        THROW 51235,
            'FactOrder validation failed: unexpected delivered-late profile.',
            1;
    END;


    IF @ExpectedUndeliveredLateStatus <> 2965
       OR @ActualUndeliveredLateStatus <> 2965
    BEGIN
        THROW 51236,
            'FactOrder validation failed: unexpected undelivered late-status profile.',
            1;
    END;


    PRINT 'FACT ORDER VALIDATION PASSED.';
END;
GO