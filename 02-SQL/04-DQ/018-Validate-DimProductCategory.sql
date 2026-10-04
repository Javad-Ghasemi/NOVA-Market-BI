USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedDimProductCategory;
GO


/* =========================================================
   Build expected business rows
   ========================================================= */

SELECT
    c.SourceCategoryName,
    c.EnglishCategoryName,
    l.PersianCategoryName,
    c.MissingEnglishTranslationFlag,

    CAST(
        CASE
            WHEN l.PersianCategoryName IS NULL
              OR LTRIM(RTRIM(l.PersianCategoryName)) = N''
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS MissingPersianLocalizationFlag

INTO #ExpectedDimProductCategory

FROM conformed.ProductCategory AS c

LEFT JOIN meta.ProductCategoryLocalization AS l
    ON c.SourceCategoryName = l.SourceCategoryName;
GO


/* =========================================================
   Summary
   ========================================================= */

SELECT
    COUNT(*) AS ExpectedBusinessRows,

    SUM(
        CASE
            WHEN MissingEnglishTranslationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedMissingEnglishTranslations,

    SUM(
        CASE
            WHEN MissingPersianLocalizationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedMissingPersianLocalizations

FROM #ExpectedDimProductCategory;
GO


SELECT
    COUNT(*) AS [DimProductCategoryRows],

    SUM(
        CASE
            WHEN ProductCategoryKey <> 0
            THEN 1 ELSE 0
        END
    ) AS BusinessRows,

    SUM(
        CASE
            WHEN ProductCategoryKey = 0
            THEN 1 ELSE 0
        END
    ) AS UnknownRows,

    SUM(
        CASE
            WHEN ProductCategoryKey <> 0
             AND MissingEnglishTranslationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingEnglishTranslations,

    SUM(
        CASE
            WHEN ProductCategoryKey <> 0
             AND MissingPersianLocalizationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingPersianLocalizations

FROM dwh.DimProductCategory;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedBusinessRows        INT,
    @ActualBusinessRows          INT,
    @ValidUnknownRows            INT,
    @DuplicateSourceCategories   INT,
    @NullBusinessCategories      INT,
    @MissingPersianNames         INT,
    @InvalidEnglishFlags         INT,
    @InvalidPersianFlags         INT,
    @SourceToTargetDifferences   INT,
    @TargetToSourceDifferences   INT;


SELECT
    @ExpectedBusinessRows = COUNT(*)
FROM #ExpectedDimProductCategory;


SELECT
    @ActualBusinessRows = COUNT(*)
FROM dwh.DimProductCategory
WHERE ProductCategoryKey <> 0;


SELECT
    @ValidUnknownRows = COUNT(*)
FROM dwh.DimProductCategory
WHERE ProductCategoryKey = 0
  AND SourceCategoryName IS NULL
  AND EnglishCategoryName = 'Unknown'
  AND PersianCategoryName = N'نامشخص'
  AND MissingEnglishTranslationFlag = 0
  AND MissingPersianLocalizationFlag = 0;


SELECT
    @DuplicateSourceCategories = COUNT(*)
FROM
(
    SELECT
        SourceCategoryName
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
    GROUP BY SourceCategoryName
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullBusinessCategories = COUNT(*)
FROM dwh.DimProductCategory
WHERE ProductCategoryKey <> 0
  AND SourceCategoryName IS NULL;


SELECT
    @MissingPersianNames = COUNT(*)
FROM dwh.DimProductCategory
WHERE ProductCategoryKey <> 0
  AND
  (
      PersianCategoryName IS NULL
      OR LTRIM(RTRIM(PersianCategoryName)) = N''
  );


SELECT
    @InvalidEnglishFlags = COUNT(*)
FROM dwh.DimProductCategory
WHERE ProductCategoryKey <> 0
  AND
  (
         (
             EnglishCategoryName IS NULL
             AND MissingEnglishTranslationFlag <> 1
         )
      OR (
             EnglishCategoryName IS NOT NULL
             AND MissingEnglishTranslationFlag <> 0
         )
  );


SELECT
    @InvalidPersianFlags = COUNT(*)
FROM dwh.DimProductCategory
WHERE ProductCategoryKey <> 0
  AND
  (
         (
             (
                 PersianCategoryName IS NULL
                 OR LTRIM(RTRIM(PersianCategoryName)) = N''
             )
             AND MissingPersianLocalizationFlag <> 1
         )
      OR (
             PersianCategoryName IS NOT NULL
             AND LTRIM(RTRIM(PersianCategoryName)) <> N''
             AND MissingPersianLocalizationFlag <> 0
         )
  );


SELECT
    @SourceToTargetDifferences = COUNT(*)
FROM
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM #ExpectedDimProductCategory

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
) AS x;


SELECT
    @TargetToSourceDifferences = COUNT(*)
FROM
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM #ExpectedDimProductCategory
) AS x;


SELECT
    @ExpectedBusinessRows       AS ExpectedBusinessRows,
    @ActualBusinessRows         AS ActualBusinessRows,
    @ValidUnknownRows           AS ValidUnknownRows,
    @DuplicateSourceCategories  AS DuplicateSourceCategories,
    @NullBusinessCategories     AS NullBusinessCategories,
    @MissingPersianNames        AS MissingPersianNames,
    @InvalidEnglishFlags        AS InvalidEnglishFlags,
    @InvalidPersianFlags        AS InvalidPersianFlags,
    @SourceToTargetDifferences  AS SourceToTargetDifferences,
    @TargetToSourceDifferences  AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedDimProductCategory
)
    THROW 51000,
        'DimProductCategory validation failed: business row count mismatch.',
        1;


IF
(
    SELECT COUNT(*)
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey = 0
      AND SourceCategoryName IS NULL
      AND EnglishCategoryName = 'Unknown'
      AND PersianCategoryName = N'نامشخص'
      AND MissingEnglishTranslationFlag = 0
      AND MissingPersianLocalizationFlag = 0
) <> 1
    THROW 51001,
        'DimProductCategory validation failed: invalid Unknown member.',
        1;


IF EXISTS
(
    SELECT SourceCategoryName
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
    GROUP BY SourceCategoryName
    HAVING COUNT(*) > 1
)
    THROW 51002,
        'DimProductCategory validation failed: duplicate source category.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
      AND SourceCategoryName IS NULL
)
    THROW 51003,
        'DimProductCategory validation failed: NULL business source category.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
      AND
      (
          PersianCategoryName IS NULL
          OR LTRIM(RTRIM(PersianCategoryName)) = N''
      )
)
    THROW 51004,
        'DimProductCategory validation failed: missing Persian category name.',
        1;


IF EXISTS
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM #ExpectedDimProductCategory

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0
)
    THROW 51005,
        'DimProductCategory validation failed: expected rows missing or different.',
        1;


IF EXISTS
(
    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM dwh.DimProductCategory
    WHERE ProductCategoryKey <> 0

    EXCEPT

    SELECT
        SourceCategoryName,
        EnglishCategoryName,
        PersianCategoryName,
        MissingEnglishTranslationFlag,
        MissingPersianLocalizationFlag
    FROM #ExpectedDimProductCategory
)
    THROW 51006,
        'DimProductCategory validation failed: unexpected target rows.',
        1;


PRINT 'DIMPRODUCTCATEGORY VALIDATION PASSED.';
GO