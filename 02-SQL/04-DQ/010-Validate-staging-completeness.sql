USE NOVA_Market;
GO

/* =========================================================
   Final Staging Completeness Validation

   Purpose:
   Verify that all Olist source datasets were loaded into
   SQL Server staging with the expected row counts.

   This is a pipeline-level smoke test.
   Detailed dataset-specific checks remain in:
   001 ... 009 validation scripts.
   ========================================================= */

SELECT
    DatasetName,
    ActualRows,
    ExpectedRows,
    CASE
        WHEN ActualRows = ExpectedRows THEN 'PASS'
        ELSE 'FAIL'
    END AS ValidationStatus
FROM
(
    SELECT
        'orders' AS DatasetName,
        COUNT(*) AS ActualRows,
        99441 AS ExpectedRows
    FROM stg.orders

    UNION ALL

    SELECT
        'order_items',
        COUNT(*),
        112650
    FROM stg.order_items

    UNION ALL

    SELECT
        'products',
        COUNT(*),
        32951
    FROM stg.products

    UNION ALL

    SELECT
        'category_translation',
        COUNT(*),
        71
    FROM stg.category_translation

    UNION ALL

    SELECT
        'customers',
        COUNT(*),
        99441
    FROM stg.customers

    UNION ALL

    SELECT
        'sellers',
        COUNT(*),
        3095
    FROM stg.sellers

    UNION ALL

    SELECT
        'payments',
        COUNT(*),
        103886
    FROM stg.payments

    UNION ALL

    SELECT
        'reviews',
        COUNT(*),
        99224
    FROM stg.reviews

    UNION ALL

    SELECT
        'geolocation',
        COUNT(*),
        1000163
    FROM stg.geolocation
) x
ORDER BY DatasetName;
GO


/* =========================================================
   Overall Staging Status
   ========================================================= */

WITH Validation AS
(
    SELECT COUNT(*) AS ActualRows, 99441 AS ExpectedRows
    FROM stg.orders

    UNION ALL

    SELECT COUNT(*), 112650
    FROM stg.order_items

    UNION ALL

    SELECT COUNT(*), 32951
    FROM stg.products

    UNION ALL

    SELECT COUNT(*), 71
    FROM stg.category_translation

    UNION ALL

    SELECT COUNT(*), 99441
    FROM stg.customers

    UNION ALL

    SELECT COUNT(*), 3095
    FROM stg.sellers

    UNION ALL

    SELECT COUNT(*), 103886
    FROM stg.payments

    UNION ALL

    SELECT COUNT(*), 99224
    FROM stg.reviews

    UNION ALL

    SELECT COUNT(*), 1000163
    FROM stg.geolocation
)
SELECT
    CASE
        WHEN SUM(
            CASE
                WHEN ActualRows = ExpectedRows THEN 0
                ELSE 1
            END
        ) = 0
        THEN 'STAGING VALIDATION PASSED'
        ELSE 'STAGING VALIDATION FAILED'
    END AS StagingValidationStatus
FROM Validation;
GO