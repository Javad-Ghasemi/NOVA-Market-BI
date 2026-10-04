USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedDimProduct;
GO


/* =========================================================
   Build expected DimProduct business rows
   ========================================================= */

SELECT
    p.product_id AS ProductID,

    COALESCE(pc.ProductCategoryKey, 0)
        AS ProductCategoryKey,

    p.product_name_lenght
        AS ProductNameLength,

    p.product_description_lenght
        AS ProductDescriptionLength,

    p.product_photos_qty
        AS ProductPhotosQty,

    p.product_weight_g
        AS ProductWeightG,

    p.product_length_cm
        AS ProductLengthCm,

    p.product_height_cm
        AS ProductHeightCm,

    p.product_width_cm
        AS ProductWidthCm,

    CAST(
        CASE
            WHEN p.product_category_name IS NULL
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS MissingSourceCategoryFlag,

    CAST(
        CASE
            WHEN p.product_name_lenght IS NULL
              OR p.product_description_lenght IS NULL
              OR p.product_photos_qty IS NULL
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS MissingDescriptiveAttributesFlag,

    CAST(
        CASE
            WHEN p.product_weight_g IS NULL
              OR p.product_length_cm IS NULL
              OR p.product_height_cm IS NULL
              OR p.product_width_cm IS NULL
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS MissingPhysicalAttributesFlag,

    CAST(
        CASE
            WHEN p.product_weight_g = 0
            THEN 1
            ELSE 0
        END
        AS BIT
    ) AS ZeroWeightFlag

INTO #ExpectedDimProduct

FROM stg.products AS p

LEFT JOIN dwh.DimProductCategory AS pc
    ON CAST(p.product_category_name AS VARCHAR(100))
       = pc.SourceCategoryName;
GO


/* =========================================================
   Summary
   ========================================================= */

SELECT
    COUNT(*) AS ExpectedBusinessRows,

    SUM(
        CASE
            WHEN ProductCategoryKey = 0
            THEN 1 ELSE 0
        END
    ) AS ExpectedUnknownCategoryRows,

    SUM(
        CASE
            WHEN MissingSourceCategoryFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedMissingSourceCategory,

    SUM(
        CASE
            WHEN MissingDescriptiveAttributesFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedMissingDescriptiveAttributes,

    SUM(
        CASE
            WHEN MissingPhysicalAttributesFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedMissingPhysicalAttributes,

    SUM(
        CASE
            WHEN ZeroWeightFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ExpectedZeroWeight

FROM #ExpectedDimProduct;
GO


SELECT
    COUNT(*) AS [DimProductRows],

    SUM(
        CASE
            WHEN ProductKey <> 0
            THEN 1 ELSE 0
        END
    ) AS BusinessRows,

    SUM(
        CASE
            WHEN ProductKey = 0
            THEN 1 ELSE 0
        END
    ) AS UnknownRows,

    SUM(
        CASE
            WHEN ProductKey <> 0
             AND ProductCategoryKey = 0
            THEN 1 ELSE 0
        END
    ) AS UnknownCategoryRows,

    SUM(
        CASE
            WHEN ProductKey <> 0
             AND MissingSourceCategoryFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingSourceCategory,

    SUM(
        CASE
            WHEN ProductKey <> 0
             AND MissingDescriptiveAttributesFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingDescriptiveAttributes,

    SUM(
        CASE
            WHEN ProductKey <> 0
             AND MissingPhysicalAttributesFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingPhysicalAttributes,

    SUM(
        CASE
            WHEN ProductKey <> 0
             AND ZeroWeightFlag = 1
            THEN 1 ELSE 0
        END
    ) AS ZeroWeight

FROM dwh.DimProduct;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @ExpectedBusinessRows       INT,
    @ActualBusinessRows         INT,
    @ValidUnknownRows           INT,
    @DuplicateProductIDs        INT,
    @NullBusinessProductIDs     INT,
    @InvalidCategoryKeys        INT,
    @UnresolvedCategories       INT,
    @SourceToTargetDifferences  INT,
    @TargetToSourceDifferences  INT;


SELECT
    @ExpectedBusinessRows = COUNT(*)
FROM #ExpectedDimProduct;


SELECT
    @ActualBusinessRows = COUNT(*)
FROM dwh.DimProduct
WHERE ProductKey <> 0;


SELECT
    @ValidUnknownRows = COUNT(*)
FROM dwh.DimProduct
WHERE ProductKey = 0
  AND ProductID IS NULL
  AND ProductCategoryKey = 0
  AND ProductNameLength IS NULL
  AND ProductDescriptionLength IS NULL
  AND ProductPhotosQty IS NULL
  AND ProductWeightG IS NULL
  AND ProductLengthCm IS NULL
  AND ProductHeightCm IS NULL
  AND ProductWidthCm IS NULL
  AND MissingSourceCategoryFlag = 0
  AND MissingDescriptiveAttributesFlag = 0
  AND MissingPhysicalAttributesFlag = 0
  AND ZeroWeightFlag = 0;


SELECT
    @DuplicateProductIDs = COUNT(*)
FROM
(
    SELECT
        ProductID
    FROM dwh.DimProduct
    WHERE ProductKey <> 0
    GROUP BY ProductID
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullBusinessProductIDs = COUNT(*)
FROM dwh.DimProduct
WHERE ProductKey <> 0
  AND ProductID IS NULL;


SELECT
    @InvalidCategoryKeys = COUNT(*)
FROM dwh.DimProduct AS p
LEFT JOIN dwh.DimProductCategory AS c
    ON p.ProductCategoryKey = c.ProductCategoryKey
WHERE p.ProductKey <> 0
  AND c.ProductCategoryKey IS NULL;


SELECT
    @UnresolvedCategories = COUNT(*)
FROM stg.products AS p
LEFT JOIN dwh.DimProductCategory AS c
    ON CAST(p.product_category_name AS VARCHAR(100))
       = c.SourceCategoryName
WHERE p.product_category_name IS NOT NULL
  AND c.ProductCategoryKey IS NULL;


SELECT
    @SourceToTargetDifferences = COUNT(*)
FROM
(
    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM #ExpectedDimProduct

    EXCEPT

    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM dwh.DimProduct
    WHERE ProductKey <> 0
) AS x;


SELECT
    @TargetToSourceDifferences = COUNT(*)
FROM
(
    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM dwh.DimProduct
    WHERE ProductKey <> 0

    EXCEPT

    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM #ExpectedDimProduct
) AS x;


SELECT
    @ExpectedBusinessRows      AS ExpectedBusinessRows,
    @ActualBusinessRows        AS ActualBusinessRows,
    @ValidUnknownRows          AS ValidUnknownRows,
    @DuplicateProductIDs       AS DuplicateProductIDs,
    @NullBusinessProductIDs    AS NullBusinessProductIDs,
    @InvalidCategoryKeys       AS InvalidCategoryKeys,
    @UnresolvedCategories      AS UnresolvedCategories,
    @SourceToTargetDifferences AS SourceToTargetDifferences,
    @TargetToSourceDifferences AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM dwh.DimProduct
    WHERE ProductKey <> 0
)
<>
(
    SELECT COUNT(*)
    FROM #ExpectedDimProduct
)
    THROW 51000,
        'DimProduct validation failed: business row count mismatch.',
        1;


IF
(
    SELECT COUNT(*)
    FROM dwh.DimProduct
    WHERE ProductKey = 0
      AND ProductID IS NULL
      AND ProductCategoryKey = 0
      AND ProductNameLength IS NULL
      AND ProductDescriptionLength IS NULL
      AND ProductPhotosQty IS NULL
      AND ProductWeightG IS NULL
      AND ProductLengthCm IS NULL
      AND ProductHeightCm IS NULL
      AND ProductWidthCm IS NULL
      AND MissingSourceCategoryFlag = 0
      AND MissingDescriptiveAttributesFlag = 0
      AND MissingPhysicalAttributesFlag = 0
      AND ZeroWeightFlag = 0
) <> 1
    THROW 51001,
        'DimProduct validation failed: invalid Unknown member.',
        1;


IF EXISTS
(
    SELECT ProductID
    FROM dwh.DimProduct
    WHERE ProductKey <> 0
    GROUP BY ProductID
    HAVING COUNT(*) > 1
)
    THROW 51002,
        'DimProduct validation failed: duplicate ProductID.',
        1;


IF EXISTS
(
    SELECT 1
    FROM dwh.DimProduct
    WHERE ProductKey <> 0
      AND ProductID IS NULL
)
    THROW 51003,
        'DimProduct validation failed: NULL business ProductID.',
        1;


IF EXISTS
(
    SELECT 1
    FROM stg.products AS p
    LEFT JOIN dwh.DimProductCategory AS c
        ON CAST(p.product_category_name AS VARCHAR(100))
           = c.SourceCategoryName
    WHERE p.product_category_name IS NOT NULL
      AND c.ProductCategoryKey IS NULL
)
    THROW 51004,
        'DimProduct validation failed: non-null source category did not resolve.',
        1;


IF EXISTS
(
    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM #ExpectedDimProduct

    EXCEPT

    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM dwh.DimProduct
    WHERE ProductKey <> 0
)
    THROW 51005,
        'DimProduct validation failed: expected rows missing or different.',
        1;


IF EXISTS
(
    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM dwh.DimProduct
    WHERE ProductKey <> 0

    EXCEPT

    SELECT
        ProductID,
        ProductCategoryKey,
        ProductNameLength,
        ProductDescriptionLength,
        ProductPhotosQty,
        ProductWeightG,
        ProductLengthCm,
        ProductHeightCm,
        ProductWidthCm,
        MissingSourceCategoryFlag,
        MissingDescriptiveAttributesFlag,
        MissingPhysicalAttributesFlag,
        ZeroWeightFlag
    FROM #ExpectedDimProduct
)
    THROW 51006,
        'DimProduct validation failed: unexpected target rows.',
        1;


PRINT 'DIMPRODUCT VALIDATION PASSED.';
GO