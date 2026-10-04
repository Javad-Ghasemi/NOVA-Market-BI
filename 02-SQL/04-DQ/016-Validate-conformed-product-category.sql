USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedProductCategory;
GO


/* =========================================================
   Expected conformed product categories from staging
   ========================================================= */

SELECT
    p.product_category_name AS SourceCategoryName,
    t.product_category_name_english AS EnglishCategoryName,

    CAST(
        CASE
            WHEN t.product_category_name_english IS NULL
                THEN 1
            ELSE 0
        END
        AS BIT
    ) AS MissingEnglishTranslationFlag

INTO #ExpectedProductCategory

FROM
(
    SELECT DISTINCT
        product_category_name
    FROM stg.products
    WHERE product_category_name IS NOT NULL
) AS p

LEFT JOIN stg.category_translation AS t
    ON p.product_category_name = t.product_category_name;
GO


/* =========================================================
   Summary
   ========================================================= */

SELECT
    COUNT(*) AS ExpectedCategoryRows,

    SUM(
        CASE
            WHEN MissingEnglishTranslationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedMissingEnglishTranslations

FROM #ExpectedProductCategory;
GO


SELECT
    COUNT(*) AS ConformedCategoryRows,

    SUM(
        CASE
            WHEN MissingEnglishTranslationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingEnglishTranslations

FROM conformed.ProductCategory;
GO


SELECT
    COUNT(*) AS ProductsWithoutCategory
FROM stg.products
WHERE product_category_name IS NULL;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedRows                 INT,
    @ActualRows                   INT,
    @DuplicateSourceCategories    INT,
    @NullSourceCategories         INT,
    @InvalidMissingFlags          INT,
    @SourceToTargetDifferences    INT,
    @TargetToSourceDifferences    INT;


SELECT
    @ExpectedRows = COUNT(*)
FROM #ExpectedProductCategory;


SELECT
    @ActualRows = COUNT(*)
FROM conformed.ProductCategory;


SELECT
    @DuplicateSourceCategories = COUNT(*)
FROM
(
    SELECT
        SourceCategoryName
    FROM conformed.ProductCategory
    GROUP BY SourceCategoryName
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullSourceCategories = COUNT(*)
FROM conformed.ProductCategory
WHERE SourceCategoryName IS NULL;


SELECT
    @InvalidMissingFlags = COUNT(*)
FROM conformed.ProductCategory
WHERE
       (
           EnglishCategoryName IS NULL
           AND MissingEnglishTranslationFlag <> 1
       )
    OR (
           EnglishCategoryName IS NOT NULL
           AND MissingEnglishTranslationFlag <> 0
       );


SELECT
    @SourceToTargetDifferences = COUNT(*)
FROM
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM #ExpectedProductCategory

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM conformed.ProductCategory
) AS x;


SELECT
    @TargetToSourceDifferences = COUNT(*)
FROM
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM conformed.ProductCategory

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM #ExpectedProductCategory
) AS x;


SELECT
    @ExpectedRows              AS ExpectedRows,
    @ActualRows                AS ActualRows,
    @DuplicateSourceCategories AS DuplicateSourceCategories,
    @NullSourceCategories      AS NullSourceCategories,
    @InvalidMissingFlags       AS InvalidMissingFlags,
    @SourceToTargetDifferences AS SourceToTargetDifferences,
    @TargetToSourceDifferences AS TargetToSourceDifferences;
GO


/* =========================================================
   Missing translations
   ========================================================= */

SELECT
    SourceCategoryName,
    EnglishCategoryName,
    MissingEnglishTranslationFlag
FROM conformed.ProductCategory
WHERE MissingEnglishTranslationFlag = 1
ORDER BY SourceCategoryName;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM conformed.ProductCategory
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedProductCategory
)
    THROW 51000,
        'Conformed ProductCategory validation failed: row count mismatch.',
        1;


IF EXISTS
(
    SELECT SourceCategoryName
    FROM conformed.ProductCategory
    GROUP BY SourceCategoryName
    HAVING COUNT(*) > 1
)
    THROW 51001,
        'Conformed ProductCategory validation failed: duplicate source category.',
        1;


IF EXISTS
(
    SELECT 1
    FROM conformed.ProductCategory
    WHERE SourceCategoryName IS NULL
)
    THROW 51002,
        'Conformed ProductCategory validation failed: NULL source category.',
        1;


IF EXISTS
(
    SELECT 1
    FROM conformed.ProductCategory
    WHERE
           (
               EnglishCategoryName IS NULL
               AND MissingEnglishTranslationFlag <> 1
           )
        OR (
               EnglishCategoryName IS NOT NULL
               AND MissingEnglishTranslationFlag <> 0
           )
)
    THROW 51003,
        'Conformed ProductCategory validation failed: invalid missing-translation flag.',
        1;


IF EXISTS
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM #ExpectedProductCategory

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM conformed.ProductCategory
)
    THROW 51004,
        'Conformed ProductCategory validation failed: expected rows missing or different.',
        1;


IF EXISTS
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM conformed.ProductCategory

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        MissingEnglishTranslationFlag
    FROM #ExpectedProductCategory
)
    THROW 51005,
        'Conformed ProductCategory validation failed: unexpected target rows.',
        1;


PRINT 'CONFORMED PRODUCT CATEGORY VALIDATION PASSED.';
GO