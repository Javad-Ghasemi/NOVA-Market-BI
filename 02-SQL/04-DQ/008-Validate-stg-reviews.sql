USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.reviews
   Source: Olist order reviews dataset
   Grain : one source review row

   Staging Key:
   (review_id, order_id)

   Important Source Characteristic:
   review_id alone is NOT unique.
   The composite key (review_id, order_id) is unique.

   Future DWH target:
   FactReview
   Grain = one row per review record
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.reviews;

-- Expected: 99,224


------------------------------------------------------------
-- 2. Duplicate Composite Key
--    (review_id, order_id)
------------------------------------------------------------
SELECT
    review_id,
    order_id,
    COUNT(*) AS DuplicateCount
FROM stg.reviews
GROUP BY
    review_id,
    order_id
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 3. NULL Audit
------------------------------------------------------------
SELECT
    SUM(CASE WHEN review_id IS NULL THEN 1 ELSE 0 END)
        AS ReviewIdNulls,

    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END)
        AS OrderIdNulls,

    SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END)
        AS ReviewScoreNulls,

    SUM(CASE WHEN review_comment_title IS NULL THEN 1 ELSE 0 END)
        AS ReviewCommentTitleNulls,

    SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END)
        AS ReviewCommentMessageNulls,

    SUM(CASE WHEN review_creation_date IS NULL THEN 1 ELSE 0 END)
        AS ReviewCreationDateNulls,

    SUM(CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END)
        AS ReviewAnswerTimestampNulls

FROM stg.reviews;

-- Known source values:
-- review_id                = 0
-- order_id                 = 0
-- review_score             = 0
-- review_comment_title     = 87,656
-- review_comment_message   = 58,247
-- review_creation_date     = 0
-- review_answer_timestamp  = 0


------------------------------------------------------------
-- 4. Blank Comment Titles
------------------------------------------------------------
SELECT
    COUNT(*) AS BlankReviewTitleRows
FROM stg.reviews
WHERE review_comment_title IS NOT NULL
  AND LTRIM(RTRIM(review_comment_title)) = '';

-- Informational


------------------------------------------------------------
-- 5. Blank Comment Messages
------------------------------------------------------------
SELECT
    COUNT(*) AS BlankReviewMessageRows
FROM stg.reviews
WHERE review_comment_message IS NOT NULL
  AND LTRIM(RTRIM(review_comment_message)) = '';

-- Informational


------------------------------------------------------------
-- 6. Referential Integrity:
--    reviews -> orders
------------------------------------------------------------
SELECT
    COUNT(*) AS OrphanReviews
FROM stg.reviews r
LEFT JOIN stg.orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Expected: 0 if source relationships are complete


------------------------------------------------------------
-- 7. Orders Without Review Records
------------------------------------------------------------
SELECT
    COUNT(*) AS OrdersWithoutReviews
FROM stg.orders o
LEFT JOIN stg.reviews r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL;

-- Informational


------------------------------------------------------------
-- 8. Distinct Orders Represented in Reviews
------------------------------------------------------------
SELECT
    COUNT(DISTINCT order_id) AS OrdersWithReviews
FROM stg.reviews;

-- Informational


------------------------------------------------------------
-- 9. Orders With Multiple Review Rows
------------------------------------------------------------
SELECT
    COUNT(*) AS OrdersWithMultipleReviews
FROM
(
    SELECT
        order_id
    FROM stg.reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x;

-- Expected: 547


------------------------------------------------------------
-- 10. Maximum Review Rows per Order
------------------------------------------------------------
SELECT
    MAX(x.ReviewRowCount) AS MaxReviewsPerOrder
FROM
(
    SELECT
        order_id,
        COUNT(*) AS ReviewRowCount
    FROM stg.reviews
    GROUP BY order_id
) x;

-- Expected: 3


------------------------------------------------------------
-- 11. Review Row Distribution per Order
------------------------------------------------------------
SELECT
    ReviewRowCount,
    COUNT(*) AS OrderCount
FROM
(
    SELECT
        order_id,
        COUNT(*) AS ReviewRowCount
    FROM stg.reviews
    GROUP BY order_id
) x
GROUP BY ReviewRowCount
ORDER BY ReviewRowCount;

-- Informational


------------------------------------------------------------
-- 12. Duplicate review_id Groups
--
-- review_id alone is not a valid unique key in this source.
------------------------------------------------------------
SELECT
    COUNT(*) AS DuplicateReviewIdGroups
FROM
(
    SELECT
        review_id
    FROM stg.reviews
    GROUP BY review_id
    HAVING COUNT(*) > 1
) x;

-- Expected: 789


------------------------------------------------------------
-- 13. Duplicate review_id Detail
------------------------------------------------------------
SELECT TOP (100)
    review_id,
    COUNT(*) AS ReviewRowCount,
    COUNT(DISTINCT order_id) AS DistinctOrderCount
FROM stg.reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY
    ReviewRowCount DESC,
    review_id;

-- Diagnostic / informational


------------------------------------------------------------
-- 14. Review Score Domain Validation
------------------------------------------------------------
SELECT
    review_score,
    COUNT(*) AS ReviewCount
FROM stg.reviews
GROUP BY review_score
ORDER BY review_score;

-- Expected score domain:
-- 1, 2, 3, 4, 5


------------------------------------------------------------
-- 15. Invalid Review Scores
------------------------------------------------------------
SELECT
    COUNT(*) AS InvalidReviewScoreRows
FROM stg.reviews
WHERE review_score NOT BETWEEN 1 AND 5;

-- Expected: 0


------------------------------------------------------------
-- 16. Comment Length Validation
------------------------------------------------------------
SELECT
    MAX(LEN(review_comment_title)) AS MaxReviewTitleLength,
    MAX(LEN(review_comment_message)) AS MaxReviewMessageLength
FROM stg.reviews;

-- Known source maximums:
-- Title   = 26
-- Message = 208


------------------------------------------------------------
-- 17. Review Creation Date Range
------------------------------------------------------------
SELECT
    MIN(review_creation_date) AS MinReviewCreationDate,
    MAX(review_creation_date) AS MaxReviewCreationDate
FROM stg.reviews;

-- Informational


------------------------------------------------------------
-- 18. Review Answer Timestamp Range
------------------------------------------------------------
SELECT
    MIN(review_answer_timestamp) AS MinReviewAnswerTimestamp,
    MAX(review_answer_timestamp) AS MaxReviewAnswerTimestamp
FROM stg.reviews;

-- Informational


------------------------------------------------------------
-- 19. Review Answer Earlier Than Creation
------------------------------------------------------------
SELECT
    COUNT(*) AS AnswerBeforeCreationRows
FROM stg.reviews
WHERE review_answer_timestamp < review_creation_date;

-- Investigate if greater than 0


------------------------------------------------------------
-- 20. Review Creation Before Order Purchase
------------------------------------------------------------
SELECT
    COUNT(*) AS ReviewBeforeOrderPurchaseRows
FROM stg.reviews r
INNER JOIN stg.orders o
    ON r.order_id = o.order_id
WHERE r.review_creation_date < o.order_purchase_timestamp;

-- Investigate if greater than 0


------------------------------------------------------------
-- 21. Review Creation Before Customer Delivery
--
-- This is informational because some order statuses may not have
-- a delivered timestamp and source timestamps can reflect system
-- workflow behavior.
------------------------------------------------------------
SELECT
    COUNT(*) AS ReviewBeforeDeliveryRows
FROM stg.reviews r
INNER JOIN stg.orders o
    ON r.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
  AND r.review_creation_date < o.order_delivered_customer_date;

-- Informational / investigate


------------------------------------------------------------
-- 22. Review Score Summary
------------------------------------------------------------
SELECT
    COUNT(*) AS ReviewRows,
    CAST(AVG(CAST(review_score AS DECIMAL(10,2))) AS DECIMAL(10,2))
        AS AverageReviewScore,
    MIN(review_score) AS MinReviewScore,
    MAX(review_score) AS MaxReviewScore
FROM stg.reviews;

-- Informational


------------------------------------------------------------
-- 23. Review Text Coverage
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN review_comment_title IS NOT NULL
             AND LTRIM(RTRIM(review_comment_title)) <> ''
            THEN 1 ELSE 0
        END
    ) AS ReviewsWithTitle,

    SUM(
        CASE
            WHEN review_comment_message IS NOT NULL
             AND LTRIM(RTRIM(review_comment_message)) <> ''
            THEN 1 ELSE 0
        END
    ) AS ReviewsWithMessage,

    SUM(
        CASE
            WHEN review_comment_title IS NULL
             AND review_comment_message IS NULL
            THEN 1 ELSE 0
        END
    ) AS ReviewsWithoutTitleOrMessage

FROM stg.reviews;

-- Informational


------------------------------------------------------------
-- 24. Review Counts by Order Status
------------------------------------------------------------
SELECT
    o.order_status,
    COUNT(*) AS ReviewCount
FROM stg.reviews r
INNER JOIN stg.orders o
    ON r.order_id = o.order_id
GROUP BY o.order_status
ORDER BY ReviewCount DESC;

-- Informational


------------------------------------------------------------
-- 25. Source Grain Validation Summary
--
-- Expected staging model:
--
-- Grain:
--   1 row = 1 source review row
--
-- Valid staging key:
--   (review_id, order_id)
--
-- review_id alone:
--   NOT UNIQUE
--
-- order_id alone:
--   NOT UNIQUE
--
-- No deduplication should be applied in staging because the
-- source contains legitimate multiple review rows per order
-- and repeated review_id values across different orders.
------------------------------------------------------------

-- Known Source Temporal Characteristics
--
-- Temporal validation identified the following source behavior:
--
-- Review creation before order purchase:
--   Total     = 74
--   Canceled  = 67
--   Delivered = 6
--   Shipped   = 1
--
-- Review answer timestamp before recorded customer delivery:
--   Total = 4,795
--
-- Severe cases where the review was answered 31+ days before
-- the recorded customer delivery:
--   Total = 256
--
-- Of those severe cases:
--   252 orders were delivered after the estimated delivery date.
--   4 orders were delivered on or before the estimated date.
--
-- Among the 4 residual severe cases:
--   3 also have review creation timestamps before order purchase.
--   1 remains an unexplained source timing inconsistency.
--
-- Interpretation:
-- These records are preserved exactly as provided by the source.
-- No review, order, or timestamp is deleted, shifted, or corrected.
--
-- Review timestamps and logistics timestamps should therefore
-- not be assumed to represent a perfectly synchronized workflow.
------------------------------------------------------------