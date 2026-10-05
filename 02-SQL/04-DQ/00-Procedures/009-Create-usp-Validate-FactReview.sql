USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateFactReview

   Purpose:
   - Single source of truth for FactReview DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure

   Grain:
   ReviewID + OrderID

   Important:
   - ReviewID alone is not unique in the Olist source.
   - Duplicate ReviewID values are preserved and flagged.
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateFactReview
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected FactReview rows
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedFactReview;

    WITH ReviewProfile AS
    (
        SELECT
            r.review_id,
            r.order_id,
            r.review_score,
            r.review_comment_title,
            r.review_comment_message,
            r.review_creation_date,
            r.review_answer_timestamp,

            COUNT(*) OVER
            (
                PARTITION BY r.review_id
            ) AS ReviewIDRowCount

        FROM stg.reviews AS r
    )
    SELECT
        r.review_id AS ReviewID,
        r.order_id AS OrderID,

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

        CONVERT
        (
            int,
            CONVERT
            (
                char(8),
                CAST(r.review_creation_date AS date),
                112
            )
        ) AS ReviewCreationDateKey,

        CONVERT
        (
            int,
            CONVERT
            (
                char(8),
                CAST(r.review_answer_timestamp AS date),
                112
            )
        ) AS ReviewAnswerDateKey,

        o.order_status AS OrderStatus,

        r.review_score AS ReviewScore,

        r.review_comment_title AS ReviewCommentTitle,
        r.review_comment_message AS ReviewCommentMessage,

        r.review_creation_date AS ReviewCreationTimestamp,
        r.review_answer_timestamp AS ReviewAnswerTimestamp,

        CAST(1 AS tinyint) AS ReviewCount,

        CAST
        (
            CASE
                WHEN r.ReviewIDRowCount > 1
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS DuplicateReviewIDFlag,

        /* Creation date behaves as a business date. */
        CAST
        (
            CASE
                WHEN CAST(r.review_creation_date AS date)
                     < CAST(o.order_purchase_timestamp AS date)
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS ReviewCreatedBeforePurchaseFlag,

        /*
           NULL means delivery did not occur, so the
           delivery-relative condition cannot be evaluated.
        */
        CAST
        (
            CASE
                WHEN o.order_delivered_customer_date IS NULL
                    THEN NULL

                WHEN CAST(r.review_creation_date AS date)
                     < CAST(o.order_delivered_customer_date AS date)
                    THEN 1

                ELSE 0
            END
            AS bit
        ) AS ReviewCreatedBeforeDeliveryFlag,

        /* Answer timestamp preserves time-of-day semantics. */
        CAST
        (
            CASE
                WHEN r.review_answer_timestamp
                     < o.order_purchase_timestamp
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS ReviewAnsweredBeforePurchaseFlag,

        CAST
        (
            CASE
                WHEN o.order_delivered_customer_date IS NULL
                    THEN NULL

                WHEN r.review_answer_timestamp
                     < o.order_delivered_customer_date
                    THEN 1

                ELSE 0
            END
            AS bit
        ) AS ReviewAnsweredBeforeDeliveryFlag,

        CAST
        (
            CASE
                WHEN r.review_answer_timestamp
                     < r.review_creation_date
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS ReviewAnsweredBeforeCreationFlag

    INTO #ExpectedFactReview

    FROM ReviewProfile AS r

    INNER JOIN stg.orders AS o
        ON r.order_id = o.order_id

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
        @SourceRows                            bigint,
        @ExpectedRows                          bigint,
        @ActualRows                            bigint,

        @ExpectedDistinctOrders                bigint,
        @ActualDistinctOrders                  bigint,

        @DuplicateNaturalGrain                 bigint,
        @NullReviewIDs                         bigint,
        @NullOrderIDs                          bigint,

        @InvalidReviewScores                   bigint,
        @InvalidReviewCounts                   bigint,

        @MissingExpectedCustomerKeys           bigint,
        @MissingExpectedGeographyKeys          bigint,
        @MissingExpectedDateKeys               bigint,

        @InvalidCustomerKeys                   bigint,
        @InvalidGeographyKeys                  bigint,
        @InvalidDateKeys                       bigint,

        @MissingFactOrderMatches               bigint,
        @InvalidDeliveryFlagNullSemantics      bigint,

        @SourceOrdersWithoutReviews            bigint,
        @FactOrdersWithoutReviews              bigint,
        @SourceNoReviewToWarehouseDiff         bigint,
        @WarehouseNoReviewToSourceDiff         bigint,

        @ExpectedReviewScore                   bigint,
        @ActualReviewScore                     bigint,

        @ExpectedDuplicateReviewIDGroups       bigint,
        @ActualDuplicateReviewIDGroups         bigint,

        @ExpectedDuplicateReviewIDRows         bigint,
        @ActualDuplicateReviewIDRows           bigint,

        @ExpectedCreatedBeforePurchase         bigint,
        @ActualCreatedBeforePurchase           bigint,

        @ExpectedCreatedBeforeDelivery         bigint,
        @ActualCreatedBeforeDelivery           bigint,

        @ExpectedCreatedBeforeDeliveryNull     bigint,
        @ActualCreatedBeforeDeliveryNull       bigint,

        @ExpectedAnsweredBeforePurchase        bigint,
        @ActualAnsweredBeforePurchase          bigint,

        @ExpectedAnsweredBeforeDelivery        bigint,
        @ActualAnsweredBeforeDelivery          bigint,

        @ExpectedAnsweredBeforeDeliveryNull    bigint,
        @ActualAnsweredBeforeDeliveryNull      bigint,

        @ExpectedAnsweredBeforeCreation        bigint,
        @ActualAnsweredBeforeCreation          bigint,

        @SourceToTargetDifferences             bigint,
        @TargetToSourceDifferences             bigint;


    /* =====================================================
       Source / expected metrics
       ===================================================== */

    SELECT
        @SourceRows = COUNT_BIG(*)
    FROM stg.reviews;


    SELECT
        @ExpectedRows = COUNT_BIG(*),

        @ExpectedDistinctOrders =
            COUNT_BIG(DISTINCT OrderID),

        @ExpectedReviewScore =
            COALESCE(SUM(CAST(ReviewScore AS bigint)), 0),

        @ExpectedDuplicateReviewIDRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DuplicateReviewIDFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedCreatedBeforePurchase =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewCreatedBeforePurchaseFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedCreatedBeforeDelivery =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewCreatedBeforeDeliveryFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedCreatedBeforeDeliveryNull =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewCreatedBeforeDeliveryFlag IS NULL
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedAnsweredBeforePurchase =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforePurchaseFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedAnsweredBeforeDelivery =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforeDeliveryFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedAnsweredBeforeDeliveryNull =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforeDeliveryFlag IS NULL
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedAnsweredBeforeCreation =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforeCreationFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedFactReview;


    SELECT
        @ExpectedDuplicateReviewIDGroups = COUNT_BIG(*)

    FROM
    (
        SELECT ReviewID

        FROM #ExpectedFactReview

        GROUP BY ReviewID

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    /* =====================================================
       Actual metrics
       ===================================================== */

    SELECT
        @ActualRows = COUNT_BIG(*),

        @ActualDistinctOrders =
            COUNT_BIG(DISTINCT OrderID),

        @ActualReviewScore =
            COALESCE(SUM(CAST(ReviewScore AS bigint)), 0),

        @ActualDuplicateReviewIDRows =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN DuplicateReviewIDFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualCreatedBeforePurchase =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewCreatedBeforePurchaseFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualCreatedBeforeDelivery =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewCreatedBeforeDeliveryFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualCreatedBeforeDeliveryNull =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewCreatedBeforeDeliveryFlag IS NULL
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualAnsweredBeforePurchase =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforePurchaseFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualAnsweredBeforeDelivery =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforeDeliveryFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualAnsweredBeforeDeliveryNull =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforeDeliveryFlag IS NULL
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualAnsweredBeforeCreation =
            COALESCE
            (
                SUM
                (
                    CASE
                        WHEN ReviewAnsweredBeforeCreationFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.FactReview;


    SELECT
        @ActualDuplicateReviewIDGroups = COUNT_BIG(*)

    FROM
    (
        SELECT ReviewID

        FROM dwh.FactReview

        GROUP BY ReviewID

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    /* =====================================================
       Natural grain

       ReviewID alone may repeat.
       ReviewID + OrderID must remain unique.
       ===================================================== */

    SELECT
        @DuplicateNaturalGrain = COUNT_BIG(*)

    FROM
    (
        SELECT
            ReviewID,
            OrderID

        FROM dwh.FactReview

        GROUP BY
            ReviewID,
            OrderID

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullReviewIDs = COUNT_BIG(*)

    FROM dwh.FactReview

    WHERE ReviewID IS NULL;


    SELECT
        @NullOrderIDs = COUNT_BIG(*)

    FROM dwh.FactReview

    WHERE OrderID IS NULL;


    /* =====================================================
       Review domain / counter
       ===================================================== */

    SELECT
        @InvalidReviewScores = COUNT_BIG(*)

    FROM dwh.FactReview

    WHERE ReviewScore IS NULL
       OR ReviewScore < 1
       OR ReviewScore > 5;


    SELECT
        @InvalidReviewCounts = COUNT_BIG(*)

    FROM dwh.FactReview

    WHERE ReviewCount IS NULL
       OR ReviewCount <> 1;


    /* =====================================================
       Expected dimension resolution
       ===================================================== */

    SELECT
        @MissingExpectedCustomerKeys = COUNT_BIG(*)

    FROM #ExpectedFactReview

    WHERE CustomerKey IS NULL;


    SELECT
        @MissingExpectedGeographyKeys = COUNT_BIG(*)

    FROM #ExpectedFactReview

    WHERE CustomerGeographyKey IS NULL;


    /* =====================================================
       Expected DateKey coverage

       All three date roles are mandatory for FactReview.
       ===================================================== */

    SELECT
        @MissingExpectedDateKeys = COUNT_BIG(*)

    FROM #ExpectedFactReview AS e

    LEFT JOIN dwh.DimDate AS dp
        ON e.PurchaseDateKey = dp.DateKey
       AND dp.DateKey <> 0

    LEFT JOIN dwh.DimDate AS dc
        ON e.ReviewCreationDateKey = dc.DateKey
       AND dc.DateKey <> 0

    LEFT JOIN dwh.DimDate AS da
        ON e.ReviewAnswerDateKey = da.DateKey
       AND da.DateKey <> 0

    WHERE dp.DateKey IS NULL
       OR dc.DateKey IS NULL
       OR da.DateKey IS NULL;


    /* =====================================================
       Actual surrogate-key integrity
       ===================================================== */

    SELECT
        @InvalidCustomerKeys = COUNT_BIG(*)

    FROM dwh.FactReview AS f

    LEFT JOIN dwh.DimCustomer AS d
        ON f.CustomerKey = d.CustomerKey
       AND d.CustomerKey <> 0

    WHERE d.CustomerKey IS NULL;


    SELECT
        @InvalidGeographyKeys = COUNT_BIG(*)

    FROM dwh.FactReview AS f

    LEFT JOIN dwh.DimGeography AS d
        ON f.CustomerGeographyKey = d.GeographyKey
       AND d.GeographyKey <> 0

    WHERE d.GeographyKey IS NULL;


    SELECT
        @InvalidDateKeys = COUNT_BIG(*)

    FROM dwh.FactReview AS f

    LEFT JOIN dwh.DimDate AS dp
        ON f.PurchaseDateKey = dp.DateKey
       AND dp.DateKey <> 0

    LEFT JOIN dwh.DimDate AS dc
        ON f.ReviewCreationDateKey = dc.DateKey
       AND dc.DateKey <> 0

    LEFT JOIN dwh.DimDate AS da
        ON f.ReviewAnswerDateKey = da.DateKey
       AND da.DateKey <> 0

    WHERE dp.DateKey IS NULL
       OR dc.DateKey IS NULL
       OR da.DateKey IS NULL;


    /* =====================================================
       FactOrder coverage
       ===================================================== */

    SELECT
        @MissingFactOrderMatches = COUNT_BIG(*)

    FROM dwh.FactReview AS r

    LEFT JOIN dwh.FactOrder AS o
        ON r.OrderID = o.OrderID

    WHERE o.OrderID IS NULL;


    /* =====================================================
       Delivery-relative NULL semantics
       ===================================================== */

    SELECT
        @InvalidDeliveryFlagNullSemantics = COUNT_BIG(*)

    FROM dwh.FactReview AS r

    INNER JOIN stg.orders AS o
        ON r.OrderID = o.order_id

    WHERE
        (
            o.order_delivered_customer_date IS NULL
            AND
            (
                r.ReviewCreatedBeforeDeliveryFlag IS NOT NULL
                OR
                r.ReviewAnsweredBeforeDeliveryFlag IS NOT NULL
            )
        )
        OR
        (
            o.order_delivered_customer_date IS NOT NULL
            AND
            (
                r.ReviewCreatedBeforeDeliveryFlag IS NULL
                OR
                r.ReviewAnsweredBeforeDeliveryFlag IS NULL
            )
        );


    /* =====================================================
       Orders without reviews
       ===================================================== */

    SELECT
        @SourceOrdersWithoutReviews = COUNT_BIG(*)

    FROM stg.orders AS o

    LEFT JOIN stg.reviews AS r
        ON o.order_id = r.order_id

    WHERE r.order_id IS NULL;


    SELECT
        @FactOrdersWithoutReviews = COUNT_BIG(*)

    FROM dwh.FactOrder AS o

    LEFT JOIN dwh.FactReview AS r
        ON o.OrderID = r.OrderID

    WHERE r.OrderID IS NULL;


    SELECT
        @SourceNoReviewToWarehouseDiff = COUNT_BIG(*)

    FROM
    (
        SELECT o.order_id AS OrderID

        FROM stg.orders AS o

        LEFT JOIN stg.reviews AS r
            ON o.order_id = r.order_id

        WHERE r.order_id IS NULL

        EXCEPT

        SELECT o.OrderID

        FROM dwh.FactOrder AS o

        LEFT JOIN dwh.FactReview AS r
            ON o.OrderID = r.OrderID

        WHERE r.OrderID IS NULL
    ) AS x;


    SELECT
        @WarehouseNoReviewToSourceDiff = COUNT_BIG(*)

    FROM
    (
        SELECT o.OrderID

        FROM dwh.FactOrder AS o

        LEFT JOIN dwh.FactReview AS r
            ON o.OrderID = r.OrderID

        WHERE r.OrderID IS NULL

        EXCEPT

        SELECT o.order_id AS OrderID

        FROM stg.orders AS o

        LEFT JOIN stg.reviews AS r
            ON o.order_id = r.order_id

        WHERE r.order_id IS NULL
    ) AS x;


    /* =====================================================
       Expected -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

    FROM
    (
        SELECT
            ReviewID,
            OrderID,
            CustomerKey,
            CustomerGeographyKey,
            PurchaseDateKey,
            ReviewCreationDateKey,
            ReviewAnswerDateKey,
            OrderStatus,
            ReviewScore,
            ReviewCommentTitle,
            ReviewCommentMessage,
            ReviewCreationTimestamp,
            ReviewAnswerTimestamp,
            ReviewCount,
            DuplicateReviewIDFlag,
            ReviewCreatedBeforePurchaseFlag,
            ReviewCreatedBeforeDeliveryFlag,
            ReviewAnsweredBeforePurchaseFlag,
            ReviewAnsweredBeforeDeliveryFlag,
            ReviewAnsweredBeforeCreationFlag

        FROM #ExpectedFactReview

        EXCEPT

        SELECT
            ReviewID,
            OrderID,
            CustomerKey,
            CustomerGeographyKey,
            PurchaseDateKey,
            ReviewCreationDateKey,
            ReviewAnswerDateKey,
            OrderStatus,
            ReviewScore,
            ReviewCommentTitle,
            ReviewCommentMessage,
            ReviewCreationTimestamp,
            ReviewAnswerTimestamp,
            ReviewCount,
            DuplicateReviewIDFlag,
            ReviewCreatedBeforePurchaseFlag,
            ReviewCreatedBeforeDeliveryFlag,
            ReviewAnsweredBeforePurchaseFlag,
            ReviewAnsweredBeforeDeliveryFlag,
            ReviewAnsweredBeforeCreationFlag

        FROM dwh.FactReview
    ) AS x;


    /* =====================================================
       Target -> Expected exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

    FROM
    (
        SELECT
            ReviewID,
            OrderID,
            CustomerKey,
            CustomerGeographyKey,
            PurchaseDateKey,
            ReviewCreationDateKey,
            ReviewAnswerDateKey,
            OrderStatus,
            ReviewScore,
            ReviewCommentTitle,
            ReviewCommentMessage,
            ReviewCreationTimestamp,
            ReviewAnswerTimestamp,
            ReviewCount,
            DuplicateReviewIDFlag,
            ReviewCreatedBeforePurchaseFlag,
            ReviewCreatedBeforeDeliveryFlag,
            ReviewAnsweredBeforePurchaseFlag,
            ReviewAnsweredBeforeDeliveryFlag,
            ReviewAnsweredBeforeCreationFlag

        FROM dwh.FactReview

        EXCEPT

        SELECT
            ReviewID,
            OrderID,
            CustomerKey,
            CustomerGeographyKey,
            PurchaseDateKey,
            ReviewCreationDateKey,
            ReviewAnswerDateKey,
            OrderStatus,
            ReviewScore,
            ReviewCommentTitle,
            ReviewCommentMessage,
            ReviewCreationTimestamp,
            ReviewAnswerTimestamp,
            ReviewCount,
            DuplicateReviewIDFlag,
            ReviewCreatedBeforePurchaseFlag,
            ReviewCreatedBeforeDeliveryFlag,
            ReviewAnsweredBeforePurchaseFlag,
            ReviewAnsweredBeforeDeliveryFlag,
            ReviewAnsweredBeforeCreationFlag

        FROM #ExpectedFactReview
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

        @NullReviewIDs
            AS NullReviewIDs,

        @NullOrderIDs
            AS NullOrderIDs,

        @InvalidReviewScores
            AS InvalidReviewScores,

        @InvalidReviewCounts
            AS InvalidReviewCounts,

        @MissingExpectedCustomerKeys
            AS MissingExpectedCustomerKeys,

        @MissingExpectedGeographyKeys
            AS MissingExpectedGeographyKeys,

        @MissingExpectedDateKeys
            AS MissingExpectedDateKeys,

        @InvalidCustomerKeys
            AS InvalidCustomerKeys,

        @InvalidGeographyKeys
            AS InvalidGeographyKeys,

        @InvalidDateKeys
            AS InvalidDateKeys,

        @MissingFactOrderMatches
            AS MissingFactOrderMatches,

        @InvalidDeliveryFlagNullSemantics
            AS InvalidDeliveryFlagNullSemantics,

        @SourceOrdersWithoutReviews
            AS SourceOrdersWithoutReviews,

        @FactOrdersWithoutReviews
            AS FactOrdersWithoutReviews,

        @SourceNoReviewToWarehouseDiff
            AS SourceNoReviewToWarehouseDiff,

        @WarehouseNoReviewToSourceDiff
            AS WarehouseNoReviewToSourceDiff,

        @ExpectedReviewScore
            AS ExpectedReviewScore,

        @ActualReviewScore
            AS ActualReviewScore,

        @ExpectedDuplicateReviewIDGroups
            AS ExpectedDuplicateReviewIDGroups,

        @ActualDuplicateReviewIDGroups
            AS ActualDuplicateReviewIDGroups,

        @ExpectedDuplicateReviewIDRows
            AS ExpectedDuplicateReviewIDRows,

        @ActualDuplicateReviewIDRows
            AS ActualDuplicateReviewIDRows,

        @ExpectedCreatedBeforePurchase
            AS ExpectedCreatedBeforePurchase,

        @ActualCreatedBeforePurchase
            AS ActualCreatedBeforePurchase,

        @ExpectedCreatedBeforeDelivery
            AS ExpectedCreatedBeforeDelivery,

        @ActualCreatedBeforeDelivery
            AS ActualCreatedBeforeDelivery,

        @ExpectedCreatedBeforeDeliveryNull
            AS ExpectedCreatedBeforeDeliveryNull,

        @ActualCreatedBeforeDeliveryNull
            AS ActualCreatedBeforeDeliveryNull,

        @ExpectedAnsweredBeforePurchase
            AS ExpectedAnsweredBeforePurchase,

        @ActualAnsweredBeforePurchase
            AS ActualAnsweredBeforePurchase,

        @ExpectedAnsweredBeforeDelivery
            AS ExpectedAnsweredBeforeDelivery,

        @ActualAnsweredBeforeDelivery
            AS ActualAnsweredBeforeDelivery,

        @ExpectedAnsweredBeforeDeliveryNull
            AS ExpectedAnsweredBeforeDeliveryNull,

        @ActualAnsweredBeforeDeliveryNull
            AS ActualAnsweredBeforeDeliveryNull,

        @ExpectedAnsweredBeforeCreation
            AS ExpectedAnsweredBeforeCreation,

        @ActualAnsweredBeforeCreation
            AS ActualAnsweredBeforeCreation,

        @SourceToTargetDifferences
            AS SourceToTargetDifferences,

        @TargetToSourceDifferences
            AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @SourceRows <> 99224
    BEGIN
        THROW 51300,
            'FactReview validation failed: staging review baseline row count changed.',
            1;
    END;


    IF @ExpectedRows <> @SourceRows
    BEGIN
        THROW 51301,
            'FactReview validation failed: expected-row construction lost or duplicated source rows.',
            1;
    END;


    IF @ActualRows <> @ExpectedRows
    BEGIN
        THROW 51302,
            'FactReview validation failed: row count mismatch.',
            1;
    END;


    IF @ExpectedDistinctOrders <> 98673
       OR @ActualDistinctOrders <> 98673
    BEGIN
        THROW 51303,
            'FactReview validation failed: unexpected distinct-order count.',
            1;
    END;


    IF @DuplicateNaturalGrain <> 0
       OR @NullReviewIDs <> 0
       OR @NullOrderIDs <> 0
    BEGIN
        THROW 51304,
            'FactReview validation failed: invalid ReviewID + OrderID grain.',
            1;
    END;


    IF @InvalidReviewScores <> 0
    BEGIN
        THROW 51305,
            'FactReview validation failed: invalid review score.',
            1;
    END;


    IF @InvalidReviewCounts <> 0
    BEGIN
        THROW 51306,
            'FactReview validation failed: invalid ReviewCount.',
            1;
    END;


    IF @MissingExpectedCustomerKeys <> 0
       OR @MissingExpectedGeographyKeys <> 0
    BEGIN
        THROW 51307,
            'FactReview validation failed: expected dimension resolution failure.',
            1;
    END;


    IF @MissingExpectedDateKeys <> 0
    BEGIN
        THROW 51308,
            'FactReview validation failed: source review date missing from DimDate.',
            1;
    END;


    IF @InvalidCustomerKeys <> 0
       OR @InvalidGeographyKeys <> 0
       OR @InvalidDateKeys <> 0
    BEGIN
        THROW 51309,
            'FactReview validation failed: invalid dimension surrogate key detected.',
            1;
    END;


    IF @MissingFactOrderMatches <> 0
    BEGIN
        THROW 51310,
            'FactReview validation failed: OrderID missing from FactOrder.',
            1;
    END;


    IF @InvalidDeliveryFlagNullSemantics <> 0
    BEGIN
        THROW 51311,
            'FactReview validation failed: invalid delivery-relative NULL semantics.',
            1;
    END;


    IF @SourceOrdersWithoutReviews <> 768
       OR @FactOrdersWithoutReviews <> 768
       OR @SourceNoReviewToWarehouseDiff <> 0
       OR @WarehouseNoReviewToSourceDiff <> 0
    BEGIN
        THROW 51312,
            'FactReview validation failed: no-review order set differs from source.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51313,
            'FactReview validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51314,
            'FactReview validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist review profile
       ===================================================== */

    IF @ExpectedReviewScore <> 405471
       OR @ActualReviewScore <> 405471
    BEGIN
        THROW 51315,
            'FactReview validation failed: unexpected total review-score profile.',
            1;
    END;


    IF @ExpectedDuplicateReviewIDGroups <> 789
       OR @ActualDuplicateReviewIDGroups <> 789
       OR @ExpectedDuplicateReviewIDRows <> 1603
       OR @ActualDuplicateReviewIDRows <> 1603
    BEGIN
        THROW 51316,
            'FactReview validation failed: unexpected duplicate ReviewID profile.',
            1;
    END;


    IF @ExpectedCreatedBeforePurchase <> 64
       OR @ActualCreatedBeforePurchase <> 64

       OR @ExpectedCreatedBeforeDelivery <> 5127
       OR @ActualCreatedBeforeDelivery <> 5127

       OR @ExpectedCreatedBeforeDeliveryNull <> 2865
       OR @ActualCreatedBeforeDeliveryNull <> 2865
    BEGIN
        THROW 51317,
            'FactReview validation failed: unexpected review-creation temporal profile.',
            1;
    END;


    IF @ExpectedAnsweredBeforePurchase <> 63
       OR @ActualAnsweredBeforePurchase <> 63

       OR @ExpectedAnsweredBeforeDelivery <> 4795
       OR @ActualAnsweredBeforeDelivery <> 4795

       OR @ExpectedAnsweredBeforeDeliveryNull <> 2865
       OR @ActualAnsweredBeforeDeliveryNull <> 2865

       OR @ExpectedAnsweredBeforeCreation <> 0
       OR @ActualAnsweredBeforeCreation <> 0
    BEGIN
        THROW 51318,
            'FactReview validation failed: unexpected review-answer temporal profile.',
            1;
    END;


    PRINT 'FACT REVIEW VALIDATION PASSED.';
END;
GO