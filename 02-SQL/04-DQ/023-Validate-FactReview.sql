USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedFactReview;
GO


/* =========================================================
   Build expected FactReview rows
   ========================================================= */

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
            CAST(r.review_creation_date AS DATE),
            112
        )
    ) AS ReviewCreationDateKey,

    CONVERT(
        INT,
        CONVERT(
            CHAR(8),
            CAST(r.review_answer_timestamp AS DATE),
            112
        )
    ) AS ReviewAnswerDateKey,

    o.order_status AS OrderStatus,

    r.review_score AS ReviewScore,

    r.review_comment_title AS ReviewCommentTitle,
    r.review_comment_message AS ReviewCommentMessage,

    r.review_creation_date AS ReviewCreationTimestamp,
    r.review_answer_timestamp AS ReviewAnswerTimestamp,

    CAST(1 AS TINYINT) AS ReviewCount,

    CAST(
        CASE
            WHEN r.ReviewIDRowCount > 1
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS DuplicateReviewIDFlag,

    /*
        review_creation_date behaves primarily as a business date,
        so creation-vs-order comparisons use DATE semantics.
    */
    CAST(
        CASE
            WHEN CAST(r.review_creation_date AS DATE)
               < CAST(o.order_purchase_timestamp AS DATE)
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS ReviewCreatedBeforePurchaseFlag,

    /*
        NULL means delivery did not occur and therefore the
        delivery-relative condition cannot be evaluated.
    */
    CAST(
        CASE
            WHEN o.order_delivered_customer_date IS NULL
            THEN NULL

            WHEN CAST(r.review_creation_date AS DATE)
               < CAST(o.order_delivered_customer_date AS DATE)
            THEN 1

            ELSE 0
        END
        AS BIT
    ) AS ReviewCreatedBeforeDeliveryFlag,

    /*
        review_answer_timestamp contains meaningful time-of-day,
        so timestamp semantics are preserved.
    */
    CAST(
        CASE
            WHEN r.review_answer_timestamp
               < o.order_purchase_timestamp
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS ReviewAnsweredBeforePurchaseFlag,

    CAST(
        CASE
            WHEN o.order_delivered_customer_date IS NULL
            THEN NULL

            WHEN r.review_answer_timestamp
               < o.order_delivered_customer_date
            THEN 1

            ELSE 0
        END
        AS BIT
    ) AS ReviewAnsweredBeforeDeliveryFlag,

    CAST(
        CASE
            WHEN r.review_answer_timestamp
               < r.review_creation_date
            THEN 1
            ELSE 0
        END
        AS BIT
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
GO


/* =========================================================
   Expected summary
   ========================================================= */

SELECT
    COUNT(*) AS ExpectedRows,

    COUNT(DISTINCT OrderID)
        AS ExpectedDistinctOrders,

    SUM(ReviewCount)
        AS ExpectedReviewCount,

    SUM(ReviewScore)
        AS ExpectedReviewScore,

    SUM(
        CASE
            WHEN DuplicateReviewIDFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ExpectedDuplicateReviewIDRows,

    SUM(
        CASE
            WHEN ReviewCreatedBeforePurchaseFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ExpectedCreatedBeforePurchaseRows,

    SUM(
        CASE
            WHEN ReviewCreatedBeforeDeliveryFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ExpectedCreatedBeforeDeliveryRows,

    SUM(
        CASE
            WHEN ReviewCreatedBeforeDeliveryFlag IS NULL
            THEN 1
            ELSE 0
        END
    ) AS ExpectedCreatedBeforeDeliveryNullRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforePurchaseFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ExpectedAnsweredBeforePurchaseRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforeDeliveryFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ExpectedAnsweredBeforeDeliveryRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforeDeliveryFlag IS NULL
            THEN 1
            ELSE 0
        END
    ) AS ExpectedAnsweredBeforeDeliveryNullRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforeCreationFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ExpectedAnsweredBeforeCreationRows

FROM #ExpectedFactReview;
GO


/* =========================================================
   Actual summary
   ========================================================= */

SELECT
    COUNT(*) AS FactReviewRows,

    COUNT(DISTINCT OrderID)
        AS DistinctOrders,

    SUM(ReviewCount)
        AS TotalReviewCount,

    SUM(ReviewScore)
        AS TotalReviewScore,

    SUM(
        CASE
            WHEN DuplicateReviewIDFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS DuplicateReviewIDRows,

    SUM(
        CASE
            WHEN ReviewCreatedBeforePurchaseFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS CreatedBeforePurchaseRows,

    SUM(
        CASE
            WHEN ReviewCreatedBeforeDeliveryFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS CreatedBeforeDeliveryRows,

    SUM(
        CASE
            WHEN ReviewCreatedBeforeDeliveryFlag IS NULL
            THEN 1
            ELSE 0
        END
    ) AS CreatedBeforeDeliveryNullRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforePurchaseFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS AnsweredBeforePurchaseRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforeDeliveryFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS AnsweredBeforeDeliveryRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforeDeliveryFlag IS NULL
            THEN 1
            ELSE 0
        END
    ) AS AnsweredBeforeDeliveryNullRows,

    SUM(
        CASE
            WHEN ReviewAnsweredBeforeCreationFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS AnsweredBeforeCreationRows

FROM dwh.FactReview;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedRows                      INT,
    @ActualRows                        INT,

    @DuplicateNaturalGrain             INT,
    @InvalidReviewScores               INT,
    @InvalidReviewCounts               INT,

    @MissingExpectedCustomerKeys       INT,
    @MissingExpectedGeographyKeys      INT,
    @MissingExpectedDateKeys           INT,

    @InvalidCustomerKeys               INT,
    @InvalidGeographyKeys              INT,
    @InvalidDateKeys                   INT,

    @MissingFactOrderMatches           INT,

    @InvalidDeliveryFlagNullSemantics  INT,

    @SourceOrdersWithoutReviews        INT,
    @FactOrdersWithoutReviews          INT,

    @SourceToTargetDifferences         INT,
    @TargetToSourceDifferences         INT;


/* Row counts */
SELECT
    @ExpectedRows = COUNT(*)
FROM #ExpectedFactReview;


SELECT
    @ActualRows = COUNT(*)
FROM dwh.FactReview;


/* =========================================================
   Natural grain validation
   ========================================================= */

SELECT
    @DuplicateNaturalGrain = COUNT(*)
FROM
(
    SELECT
        ReviewID,
        OrderID
    FROM dwh.FactReview
    GROUP BY
        ReviewID,
        OrderID
    HAVING COUNT(*) > 1
) AS d;


/* =========================================================
   Review score / counter validation
   ========================================================= */

SELECT
    @InvalidReviewScores = COUNT(*)
FROM dwh.FactReview
WHERE ReviewScore < 1
   OR ReviewScore > 5;


SELECT
    @InvalidReviewCounts = COUNT(*)
FROM dwh.FactReview
WHERE ReviewCount <> 1;


/* =========================================================
   Expected dimension resolution
   ========================================================= */

SELECT
    @MissingExpectedCustomerKeys = COUNT(*)
FROM #ExpectedFactReview
WHERE CustomerKey IS NULL;


SELECT
    @MissingExpectedGeographyKeys = COUNT(*)
FROM #ExpectedFactReview
WHERE CustomerGeographyKey IS NULL;


/* =========================================================
   Expected DateKey coverage
   ========================================================= */

SELECT
    @MissingExpectedDateKeys = COUNT(*)
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


/* =========================================================
   Actual surrogate-key validation
   ========================================================= */

SELECT
    @InvalidCustomerKeys = COUNT(*)
FROM dwh.FactReview AS f

LEFT JOIN dwh.DimCustomer AS d
    ON f.CustomerKey = d.CustomerKey
   AND d.CustomerKey <> 0

WHERE d.CustomerKey IS NULL;


SELECT
    @InvalidGeographyKeys = COUNT(*)
FROM dwh.FactReview AS f

LEFT JOIN dwh.DimGeography AS d
    ON f.CustomerGeographyKey = d.GeographyKey
   AND d.GeographyKey <> 0

WHERE d.GeographyKey IS NULL;


SELECT
    @InvalidDateKeys = COUNT(*)
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


/* =========================================================
   FactOrder coverage
   ========================================================= */

SELECT
    @MissingFactOrderMatches = COUNT(*)
FROM dwh.FactReview AS r

LEFT JOIN dwh.FactOrder AS o
    ON r.OrderID = o.OrderID

WHERE o.OrderID IS NULL;


/* =========================================================
   Delivery-relative NULL semantics

   These flags must be NULL exactly when the SOURCE order
   has no delivered-customer timestamp.
   ========================================================= */

SELECT
    @InvalidDeliveryFlagNullSemantics = COUNT(*)
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


/* =========================================================
   Orders without reviews
   ========================================================= */

/* Source */
SELECT
    @SourceOrdersWithoutReviews = COUNT(*)
FROM stg.orders AS o

LEFT JOIN stg.reviews AS r
    ON o.order_id = r.order_id

WHERE r.order_id IS NULL;


/* Warehouse */
SELECT
    @FactOrdersWithoutReviews = COUNT(*)
FROM dwh.FactOrder AS o

LEFT JOIN dwh.FactReview AS r
    ON o.OrderID = r.OrderID

WHERE r.OrderID IS NULL;


/* =========================================================
   Exact source-to-target comparison
   ========================================================= */

SELECT
    @SourceToTargetDifferences = COUNT(*)
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


SELECT
    @TargetToSourceDifferences = COUNT(*)
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


/* =========================================================
   Validation summary
   ========================================================= */

SELECT
    @ExpectedRows
        AS ExpectedRows,

    @ActualRows
        AS ActualRows,

    @DuplicateNaturalGrain
        AS DuplicateNaturalGrain,

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

    @SourceToTargetDifferences
        AS SourceToTargetDifferences,

    @TargetToSourceDifferences
        AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

/* Row count */
IF
(
    SELECT COUNT(*)
    FROM dwh.FactReview
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedFactReview
)
    THROW 51020,
        'FactReview validation failed: row count mismatch.',
        1;


/* Natural grain */
IF EXISTS
(
    SELECT
        ReviewID,
        OrderID
    FROM dwh.FactReview
    GROUP BY
        ReviewID,
        OrderID
    HAVING COUNT(*) > 1
)
    THROW 51021,
        'FactReview validation failed: duplicate natural grain.',
        1;


/* Review score domain */
IF EXISTS
(
    SELECT 1
    FROM dwh.FactReview
    WHERE ReviewScore < 1
       OR ReviewScore > 5
)
    THROW 51022,
        'FactReview validation failed: invalid review score.',
        1;


/* ReviewCount */
IF EXISTS
(
    SELECT 1
    FROM dwh.FactReview
    WHERE ReviewCount <> 1
)
    THROW 51023,
        'FactReview validation failed: invalid ReviewCount.',
        1;


/* Expected dimension resolution */
IF EXISTS
(
    SELECT 1
    FROM #ExpectedFactReview
    WHERE CustomerKey IS NULL
       OR CustomerGeographyKey IS NULL
)
    THROW 51024,
        'FactReview validation failed: dimension resolution failure.',
        1;


/* Expected DimDate coverage */
IF EXISTS
(
    SELECT 1
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
       OR da.DateKey IS NULL
)
    THROW 51025,
        'FactReview validation failed: source date missing from DimDate.',
        1;


/* Actual surrogate-key integrity */
IF EXISTS
(
    SELECT 1
    FROM dwh.FactReview AS f

    LEFT JOIN dwh.DimCustomer AS c
        ON f.CustomerKey = c.CustomerKey
       AND c.CustomerKey <> 0

    LEFT JOIN dwh.DimGeography AS g
        ON f.CustomerGeographyKey = g.GeographyKey
       AND g.GeographyKey <> 0

    LEFT JOIN dwh.DimDate AS dp
        ON f.PurchaseDateKey = dp.DateKey
       AND dp.DateKey <> 0

    LEFT JOIN dwh.DimDate AS dc
        ON f.ReviewCreationDateKey = dc.DateKey
       AND dc.DateKey <> 0

    LEFT JOIN dwh.DimDate AS da
        ON f.ReviewAnswerDateKey = da.DateKey
       AND da.DateKey <> 0

    WHERE c.CustomerKey IS NULL
       OR g.GeographyKey IS NULL
       OR dp.DateKey IS NULL
       OR dc.DateKey IS NULL
       OR da.DateKey IS NULL
)
    THROW 51026,
        'FactReview validation failed: invalid dimension surrogate key.',
        1;


/* FactOrder relationship */
IF EXISTS
(
    SELECT 1
    FROM dwh.FactReview AS r

    LEFT JOIN dwh.FactOrder AS o
        ON r.OrderID = o.OrderID

    WHERE o.OrderID IS NULL
)
    THROW 51027,
        'FactReview validation failed: OrderID missing from FactOrder.',
        1;


/* Delivery-relative NULL semantics */
IF EXISTS
(
    SELECT 1
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
        )
)
    THROW 51028,
        'FactReview validation failed: invalid delivery-relative NULL semantics.',
        1;


/* =========================================================
   No-review order set must remain unchanged
   ========================================================= */

IF EXISTS
(
    SELECT
        o.order_id
    FROM stg.orders AS o

    LEFT JOIN stg.reviews AS r
        ON o.order_id = r.order_id

    WHERE r.order_id IS NULL

    EXCEPT

    SELECT
        o.OrderID
    FROM dwh.FactOrder AS o

    LEFT JOIN dwh.FactReview AS r
        ON o.OrderID = r.OrderID

    WHERE r.OrderID IS NULL
)
    THROW 51029,
        'FactReview validation failed: source no-review orders differ from warehouse.',
        1;


IF EXISTS
(
    SELECT
        o.OrderID
    FROM dwh.FactOrder AS o

    LEFT JOIN dwh.FactReview AS r
        ON o.OrderID = r.OrderID

    WHERE r.OrderID IS NULL

    EXCEPT

    SELECT
        o.order_id
    FROM stg.orders AS o

    LEFT JOIN stg.reviews AS r
        ON o.order_id = r.order_id

    WHERE r.order_id IS NULL
)
    THROW 51030,
        'FactReview validation failed: unexpected warehouse no-review orders.',
        1;


/* =========================================================
   Expected -> Target exact comparison
   ========================================================= */

IF EXISTS
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
)
    THROW 51031,
        'FactReview validation failed: expected rows missing or different.',
        1;


/* =========================================================
   Target -> Expected exact comparison
   ========================================================= */

IF EXISTS
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
)
    THROW 51032,
        'FactReview validation failed: unexpected target rows.',
        1;


/* =========================================================
   Success
   ========================================================= */

PRINT 'FACTREVIEW VALIDATION PASSED.';
GO