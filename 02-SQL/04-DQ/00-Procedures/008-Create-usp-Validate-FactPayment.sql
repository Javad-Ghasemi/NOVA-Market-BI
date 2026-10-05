USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateFactPayment

   Purpose:
   - Single source of truth for FactPayment DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateFactPayment
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected FactPayment rows
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedFactPayment;

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

        o.order_status AS OrderStatus,

        p.payment_type AS PaymentType,
        p.payment_installments AS PaymentInstallments,

        CAST(p.payment_value AS decimal(18,2))
            AS PaymentAmount,

        CAST(1 AS tinyint)
            AS PaymentCount,

        CAST
        (
            CASE
                WHEN p.MinPaymentSequence <> 1
                  OR p.MaxPaymentSequence <> p.PaymentRowsPerOrder
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS PaymentSequenceAnomalyFlag,

        CAST
        (
            CASE
                WHEN p.payment_type = N'not_defined'
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS UndefinedPaymentTypeFlag,

        CAST
        (
            CASE
                WHEN p.payment_installments = 0
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS ZeroInstallmentFlag,

        CAST
        (
            CASE
                WHEN p.payment_value = 0
                THEN 1
                ELSE 0
            END
            AS bit
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


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @SourceRows                        bigint,
        @ExpectedRows                      bigint,
        @ActualRows                        bigint,

        @ExpectedDistinctOrders            bigint,
        @ActualDistinctOrders              bigint,

        @DuplicateNaturalGrain             bigint,
        @NullOrderIDs                      bigint,
        @InvalidPaymentSequential          bigint,

        @MissingExpectedCustomerKeys       bigint,
        @MissingExpectedGeographyKeys      bigint,

        @InvalidCustomerKeys               bigint,
        @InvalidGeographyKeys              bigint,
        @InvalidDateKeys                   bigint,
        @InvalidPaymentCounts              bigint,

        @MissingFactOrderMatches           bigint,

        @SourceOrdersWithoutPayments       bigint,
        @FactOrdersWithoutPayments         bigint,
        @SourceNoPaymentToWarehouseDiff    bigint,
        @WarehouseNoPaymentToSourceDiff    bigint,

        @ExpectedPaymentAmount             decimal(38,2),
        @ActualPaymentAmount               decimal(38,2),

        @ExpectedSequenceAnomalyOrders     bigint,
        @ActualSequenceAnomalyOrders       bigint,

        @ExpectedSequenceAnomalyRows       bigint,
        @ActualSequenceAnomalyRows         bigint,

        @ExpectedUndefinedPaymentTypes     bigint,
        @ActualUndefinedPaymentTypes       bigint,

        @ExpectedZeroInstallments          bigint,
        @ActualZeroInstallments            bigint,

        @ExpectedZeroPaymentValues         bigint,
        @ActualZeroPaymentValues           bigint,

        @SourceToTargetDifferences         bigint,
        @TargetToSourceDifferences         bigint;


    /* =====================================================
       Source / expected metrics
       ===================================================== */

    SELECT
        @SourceRows = COUNT_BIG(*)
    FROM stg.payments;


    SELECT
        @ExpectedRows = COUNT_BIG(*),

        @ExpectedDistinctOrders =
            COUNT_BIG(DISTINCT OrderID),

        @ExpectedPaymentAmount =
            COALESCE
            (
                SUM(CAST(PaymentAmount AS decimal(38,2))),
                0
            ),

        @ExpectedSequenceAnomalyRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN PaymentSequenceAnomalyFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedUndefinedPaymentTypes =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN UndefinedPaymentTypeFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedZeroInstallments =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ZeroInstallmentFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedZeroPaymentValues =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ZeroPaymentValueFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedFactPayment;


    SELECT
        @ExpectedSequenceAnomalyOrders = COUNT_BIG(*)
    FROM
    (
        SELECT OrderID

        FROM #ExpectedFactPayment

        WHERE PaymentSequenceAnomalyFlag = 1

        GROUP BY OrderID
    ) AS a;


    /* =====================================================
       Actual metrics
       ===================================================== */

    SELECT
        @ActualRows = COUNT_BIG(*),

        @ActualDistinctOrders =
            COUNT_BIG(DISTINCT OrderID),

        @ActualPaymentAmount =
            COALESCE
            (
                SUM(CAST(PaymentAmount AS decimal(38,2))),
                0
            ),

        @ActualSequenceAnomalyRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN PaymentSequenceAnomalyFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualUndefinedPaymentTypes =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN UndefinedPaymentTypeFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualZeroInstallments =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ZeroInstallmentFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualZeroPaymentValues =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ZeroPaymentValueFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.FactPayment;


    SELECT
        @ActualSequenceAnomalyOrders = COUNT_BIG(*)
    FROM
    (
        SELECT OrderID

        FROM dwh.FactPayment

        WHERE PaymentSequenceAnomalyFlag = 1

        GROUP BY OrderID
    ) AS a;


    /* =====================================================
       Natural grain
       ===================================================== */

    SELECT
        @DuplicateNaturalGrain = COUNT_BIG(*)

    FROM
    (
        SELECT
            OrderID,
            PaymentSequential

        FROM dwh.FactPayment

        GROUP BY
            OrderID,
            PaymentSequential

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullOrderIDs = COUNT_BIG(*)

    FROM dwh.FactPayment

    WHERE OrderID IS NULL;


    SELECT
        @InvalidPaymentSequential = COUNT_BIG(*)

    FROM dwh.FactPayment

    WHERE PaymentSequential IS NULL
       OR PaymentSequential < 1;


    /* =====================================================
       Expected dimension resolution
       ===================================================== */

    SELECT
        @MissingExpectedCustomerKeys = COUNT_BIG(*)

    FROM #ExpectedFactPayment

    WHERE CustomerKey IS NULL;


    SELECT
        @MissingExpectedGeographyKeys = COUNT_BIG(*)

    FROM #ExpectedFactPayment

    WHERE CustomerGeographyKey IS NULL;


    /* =====================================================
       Actual dimension-key integrity

       Customer, geography and purchase date are mandatory
       for every FactPayment row. Key 0 is invalid here.
       ===================================================== */

    SELECT
        @InvalidCustomerKeys = COUNT_BIG(*)

    FROM dwh.FactPayment AS f

    LEFT JOIN dwh.DimCustomer AS d
        ON f.CustomerKey = d.CustomerKey

    WHERE f.CustomerKey = 0
       OR d.CustomerKey IS NULL;


    SELECT
        @InvalidGeographyKeys = COUNT_BIG(*)

    FROM dwh.FactPayment AS f

    LEFT JOIN dwh.DimGeography AS d
        ON f.CustomerGeographyKey = d.GeographyKey

    WHERE f.CustomerGeographyKey = 0
       OR d.GeographyKey IS NULL;


    SELECT
        @InvalidDateKeys = COUNT_BIG(*)

    FROM dwh.FactPayment AS f

    LEFT JOIN dwh.DimDate AS d
        ON f.PurchaseDateKey = d.DateKey

    WHERE f.PurchaseDateKey = 0
       OR d.DateKey IS NULL;


    /* =====================================================
       Additive counter
       ===================================================== */

    SELECT
        @InvalidPaymentCounts = COUNT_BIG(*)

    FROM dwh.FactPayment

    WHERE PaymentCount <> 1;


    /* =====================================================
       FactOrder coverage
       ===================================================== */

    SELECT
        @MissingFactOrderMatches = COUNT_BIG(*)

    FROM dwh.FactPayment AS p

    LEFT JOIN dwh.FactOrder AS o
        ON p.OrderID = o.OrderID

    WHERE o.OrderID IS NULL;


    /* =====================================================
       Orders genuinely without payments
       ===================================================== */

    SELECT
        @SourceOrdersWithoutPayments = COUNT_BIG(*)

    FROM stg.orders AS o

    LEFT JOIN stg.payments AS p
        ON o.order_id = p.order_id

    WHERE p.order_id IS NULL;


    SELECT
        @FactOrdersWithoutPayments = COUNT_BIG(*)

    FROM dwh.FactOrder AS o

    LEFT JOIN dwh.FactPayment AS p
        ON o.OrderID = p.OrderID

    WHERE p.OrderID IS NULL;


    SELECT
        @SourceNoPaymentToWarehouseDiff = COUNT_BIG(*)

    FROM
    (
        SELECT o.order_id AS OrderID

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
    ) AS x;


    SELECT
        @WarehouseNoPaymentToSourceDiff = COUNT_BIG(*)

    FROM
    (
        SELECT o.OrderID

        FROM dwh.FactOrder AS o

        LEFT JOIN dwh.FactPayment AS p
            ON o.OrderID = p.OrderID

        WHERE p.OrderID IS NULL

        EXCEPT

        SELECT o.order_id AS OrderID

        FROM stg.orders AS o

        LEFT JOIN stg.payments AS p
            ON o.order_id = p.order_id

        WHERE p.order_id IS NULL
    ) AS x;


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

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

        @ExpectedDistinctOrders
            AS ExpectedDistinctOrders,

        @ActualDistinctOrders
            AS ActualDistinctOrders,

        @DuplicateNaturalGrain
            AS DuplicateNaturalGrain,

        @NullOrderIDs
            AS NullOrderIDs,

        @InvalidPaymentSequential
            AS InvalidPaymentSequential,

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

        @InvalidPaymentCounts
            AS InvalidPaymentCounts,

        @MissingFactOrderMatches
            AS MissingFactOrderMatches,

        @SourceOrdersWithoutPayments
            AS SourceOrdersWithoutPayments,

        @FactOrdersWithoutPayments
            AS FactOrdersWithoutPayments,

        @SourceNoPaymentToWarehouseDiff
            AS SourceNoPaymentToWarehouseDiff,

        @WarehouseNoPaymentToSourceDiff
            AS WarehouseNoPaymentToSourceDiff,

        @ExpectedPaymentAmount
            AS ExpectedPaymentAmount,

        @ActualPaymentAmount
            AS ActualPaymentAmount,

        @ExpectedSequenceAnomalyOrders
            AS ExpectedSequenceAnomalyOrders,

        @ActualSequenceAnomalyOrders
            AS ActualSequenceAnomalyOrders,

        @ExpectedSequenceAnomalyRows
            AS ExpectedSequenceAnomalyRows,

        @ActualSequenceAnomalyRows
            AS ActualSequenceAnomalyRows,

        @ExpectedUndefinedPaymentTypes
            AS ExpectedUndefinedPaymentTypes,

        @ActualUndefinedPaymentTypes
            AS ActualUndefinedPaymentTypes,

        @ExpectedZeroInstallments
            AS ExpectedZeroInstallments,

        @ActualZeroInstallments
            AS ActualZeroInstallments,

        @ExpectedZeroPaymentValues
            AS ExpectedZeroPaymentValues,

        @ActualZeroPaymentValues
            AS ActualZeroPaymentValues,

        @SourceToTargetDifferences
            AS SourceToTargetDifferences,

        @TargetToSourceDifferences
            AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @SourceRows <> 103886
    BEGIN
        THROW 51260,
            'FactPayment validation failed: staging payment baseline row count changed.',
            1;
    END;


    IF @ExpectedRows <> @SourceRows
    BEGIN
        THROW 51261,
            'FactPayment validation failed: expected-row construction lost or duplicated source rows.',
            1;
    END;


    IF @ActualRows <> @ExpectedRows
    BEGIN
        THROW 51262,
            'FactPayment validation failed: row count mismatch.',
            1;
    END;


    IF @ExpectedDistinctOrders <> 99440
       OR @ActualDistinctOrders <> 99440
    BEGIN
        THROW 51263,
            'FactPayment validation failed: unexpected distinct-order count.',
            1;
    END;


    IF @DuplicateNaturalGrain <> 0
       OR @NullOrderIDs <> 0
       OR @InvalidPaymentSequential <> 0
    BEGIN
        THROW 51264,
            'FactPayment validation failed: invalid payment natural grain.',
            1;
    END;


    IF @MissingExpectedCustomerKeys <> 0
       OR @MissingExpectedGeographyKeys <> 0
    BEGIN
        THROW 51265,
            'FactPayment validation failed: expected dimension resolution failure.',
            1;
    END;


    IF @InvalidCustomerKeys <> 0
       OR @InvalidGeographyKeys <> 0
       OR @InvalidDateKeys <> 0
    BEGIN
        THROW 51266,
            'FactPayment validation failed: invalid dimension surrogate key detected.',
            1;
    END;


    IF @InvalidPaymentCounts <> 0
    BEGIN
        THROW 51267,
            'FactPayment validation failed: invalid PaymentCount.',
            1;
    END;


    IF @MissingFactOrderMatches <> 0
    BEGIN
        THROW 51268,
            'FactPayment validation failed: OrderID missing from FactOrder.',
            1;
    END;


    IF @SourceOrdersWithoutPayments <> 1
       OR @FactOrdersWithoutPayments <> 1
       OR @SourceNoPaymentToWarehouseDiff <> 0
       OR @WarehouseNoPaymentToSourceDiff <> 0
    BEGIN
        THROW 51269,
            'FactPayment validation failed: no-payment order set differs from source.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51270,
            'FactPayment validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51271,
            'FactPayment validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist payment profile
       ===================================================== */

    IF @ExpectedPaymentAmount
           <> CAST(16008872.12 AS decimal(38,2))
       OR @ActualPaymentAmount
           <> CAST(16008872.12 AS decimal(38,2))
    BEGIN
        THROW 51272,
            'FactPayment validation failed: unexpected total payment amount.',
            1;
    END;


    IF @ExpectedSequenceAnomalyOrders <> 80
       OR @ActualSequenceAnomalyOrders <> 80
    BEGIN
        THROW 51273,
            'FactPayment validation failed: unexpected payment-sequence anomaly order count.',
            1;
    END;


    IF @ExpectedSequenceAnomalyRows <> 82
       OR @ActualSequenceAnomalyRows <> 82
    BEGIN
        THROW 51274,
            'FactPayment validation failed: unexpected payment-sequence anomaly row count.',
            1;
    END;


    IF @ExpectedUndefinedPaymentTypes <> 3
       OR @ActualUndefinedPaymentTypes <> 3
    BEGIN
        THROW 51275,
            'FactPayment validation failed: unexpected undefined-payment-type profile.',
            1;
    END;


    IF @ExpectedZeroInstallments <> 2
       OR @ActualZeroInstallments <> 2
    BEGIN
        THROW 51276,
            'FactPayment validation failed: unexpected zero-installment profile.',
            1;
    END;


    IF @ExpectedZeroPaymentValues <> 9
       OR @ActualZeroPaymentValues <> 9
    BEGIN
        THROW 51277,
            'FactPayment validation failed: unexpected zero-payment-value profile.',
            1;
    END;


    PRINT 'FACT PAYMENT VALIDATION PASSED.';
END;
GO