USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateDimProduct

   Purpose:
   - Single source of truth for DimProduct DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateDimProduct
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected DimProduct business rows
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedDimProduct;

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
            AS bit
        ) AS MissingSourceCategoryFlag,

        CAST(
            CASE
                WHEN p.product_name_lenght IS NULL
                  OR p.product_description_lenght IS NULL
                  OR p.product_photos_qty IS NULL
                THEN 1
                ELSE 0
            END
            AS bit
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
            AS bit
        ) AS MissingPhysicalAttributesFlag,

        CAST(
            CASE
                WHEN p.product_weight_g = 0
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS ZeroWeightFlag

    INTO #ExpectedDimProduct

    FROM stg.products AS p

    LEFT JOIN dwh.DimProductCategory AS pc
        ON CAST(p.product_category_name AS varchar(100))
           = pc.SourceCategoryName;


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @ExpectedBusinessRows                   bigint,
        @ExpectedUnknownCategoryRows            bigint,
        @ExpectedMissingSourceCategory          bigint,
        @ExpectedMissingDescriptiveAttributes   bigint,
        @ExpectedMissingPhysicalAttributes      bigint,
        @ExpectedZeroWeight                      bigint,

        @ActualTotalRows                        bigint,
        @ActualBusinessRows                     bigint,
        @DistinctBusinessProductIDs             bigint,
        @ActualUnknownCategoryRows              bigint,
        @ActualMissingSourceCategory            bigint,
        @ActualMissingDescriptiveAttributes      bigint,
        @ActualMissingPhysicalAttributes         bigint,
        @ActualZeroWeight                        bigint,

        @ValidUnknownRows                       bigint,
        @DuplicateProductIDs                    bigint,
        @NullBusinessProductIDs                 bigint,
        @InvalidCategoryKeys                    bigint,
        @UnresolvedCategories                   bigint,

        @SourceToTargetDifferences              bigint,
        @TargetToSourceDifferences              bigint;


    /* =====================================================
       Expected source metrics
       ===================================================== */

    SELECT
        @ExpectedBusinessRows = COUNT_BIG(*),

        @ExpectedUnknownCategoryRows =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductCategoryKey = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedMissingSourceCategory =
            COALESCE(
                SUM(
                    CASE
                        WHEN MissingSourceCategoryFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedMissingDescriptiveAttributes =
            COALESCE(
                SUM(
                    CASE
                        WHEN MissingDescriptiveAttributesFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedMissingPhysicalAttributes =
            COALESCE(
                SUM(
                    CASE
                        WHEN MissingPhysicalAttributesFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedZeroWeight =
            COALESCE(
                SUM(
                    CASE
                        WHEN ZeroWeightFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedDimProduct;


    /* =====================================================
       Target metrics
       ===================================================== */

    SELECT
        @ActualTotalRows = COUNT_BIG(*),

        @ActualBusinessRows =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductKey <> 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualUnknownCategoryRows =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductKey <> 0
                         AND ProductCategoryKey = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualMissingSourceCategory =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductKey <> 0
                         AND MissingSourceCategoryFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualMissingDescriptiveAttributes =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductKey <> 0
                         AND MissingDescriptiveAttributesFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualMissingPhysicalAttributes =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductKey <> 0
                         AND MissingPhysicalAttributesFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualZeroWeight =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductKey <> 0
                         AND ZeroWeightFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.DimProduct;


    SELECT
        @DistinctBusinessProductIDs =
            COUNT_BIG(DISTINCT ProductID)

    FROM dwh.DimProduct

    WHERE ProductKey <> 0;


    /* =====================================================
       Unknown member validation
       ===================================================== */

    SELECT
        @ValidUnknownRows = COUNT_BIG(*)

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


    /* =====================================================
       Product business-key validation
       ===================================================== */

    SELECT
        @DuplicateProductIDs = COUNT_BIG(*)

    FROM
    (
        SELECT ProductID

        FROM dwh.DimProduct

        WHERE ProductKey <> 0

        GROUP BY ProductID

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullBusinessProductIDs = COUNT_BIG(*)

    FROM dwh.DimProduct

    WHERE ProductKey <> 0
      AND ProductID IS NULL;


    /* =====================================================
       ProductCategory integrity
       ===================================================== */

    SELECT
        @InvalidCategoryKeys = COUNT_BIG(*)

    FROM dwh.DimProduct AS p

    LEFT JOIN dwh.DimProductCategory AS c
        ON p.ProductCategoryKey = c.ProductCategoryKey

    WHERE p.ProductKey <> 0
      AND c.ProductCategoryKey IS NULL;


    SELECT
        @UnresolvedCategories = COUNT_BIG(*)

    FROM stg.products AS p

    LEFT JOIN dwh.DimProductCategory AS c
        ON CAST(p.product_category_name AS varchar(100))
           = c.SourceCategoryName

    WHERE p.product_category_name IS NOT NULL
      AND c.ProductCategoryKey IS NULL;


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Diagnostic summary
       ===================================================== */

    SELECT
        @ExpectedBusinessRows
            AS ExpectedBusinessRows,

        @ActualTotalRows
            AS ActualTotalRows,

        @ActualBusinessRows
            AS ActualBusinessRows,

        @DistinctBusinessProductIDs
            AS DistinctBusinessProductIDs,

        @ValidUnknownRows
            AS ValidUnknownRows,

        @DuplicateProductIDs
            AS DuplicateProductIDs,

        @NullBusinessProductIDs
            AS NullBusinessProductIDs,

        @InvalidCategoryKeys
            AS InvalidCategoryKeys,

        @UnresolvedCategories
            AS UnresolvedCategories,

        @ExpectedUnknownCategoryRows
            AS ExpectedUnknownCategoryRows,

        @ActualUnknownCategoryRows
            AS ActualUnknownCategoryRows,

        @ExpectedMissingSourceCategory
            AS ExpectedMissingSourceCategory,

        @ActualMissingSourceCategory
            AS ActualMissingSourceCategory,

        @ExpectedMissingDescriptiveAttributes
            AS ExpectedMissingDescriptiveAttributes,

        @ActualMissingDescriptiveAttributes
            AS ActualMissingDescriptiveAttributes,

        @ExpectedMissingPhysicalAttributes
            AS ExpectedMissingPhysicalAttributes,

        @ActualMissingPhysicalAttributes
            AS ActualMissingPhysicalAttributes,

        @ExpectedZeroWeight
            AS ExpectedZeroWeight,

        @ActualZeroWeight
            AS ActualZeroWeight,

        @SourceToTargetDifferences
            AS SourceToTargetDifferences,

        @TargetToSourceDifferences
            AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @ExpectedBusinessRows <> 32951
    BEGIN
        THROW 51200,
            'DimProduct validation failed: staging Product baseline row count changed.',
            1;
    END;


    IF @ActualBusinessRows <> @ExpectedBusinessRows
       OR @ActualTotalRows <> @ExpectedBusinessRows + 1
    BEGIN
        THROW 51201,
            'DimProduct validation failed: row count mismatch.',
            1;
    END;


    IF @ValidUnknownRows <> 1
    BEGIN
        THROW 51202,
            'DimProduct validation failed: invalid Unknown member.',
            1;
    END;


    IF @DistinctBusinessProductIDs <> @ExpectedBusinessRows
       OR @DuplicateProductIDs <> 0
       OR @NullBusinessProductIDs <> 0
    BEGIN
        THROW 51203,
            'DimProduct validation failed: invalid ProductID business-key grain.',
            1;
    END;


    IF @InvalidCategoryKeys <> 0
    BEGIN
        THROW 51204,
            'DimProduct validation failed: invalid ProductCategoryKey detected.',
            1;
    END;


    IF @UnresolvedCategories <> 0
    BEGIN
        THROW 51205,
            'DimProduct validation failed: non-null source category did not resolve.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51206,
            'DimProduct validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51207,
            'DimProduct validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist product profile
       ===================================================== */

    IF @ExpectedUnknownCategoryRows <> 610
       OR @ActualUnknownCategoryRows <> 610
    BEGIN
        THROW 51208,
            'DimProduct validation failed: unexpected Unknown-category profile.',
            1;
    END;


    IF @ExpectedMissingSourceCategory <> 610
       OR @ActualMissingSourceCategory <> 610
    BEGIN
        THROW 51209,
            'DimProduct validation failed: unexpected missing-source-category profile.',
            1;
    END;


    IF @ExpectedMissingDescriptiveAttributes <> 610
       OR @ActualMissingDescriptiveAttributes <> 610
    BEGIN
        THROW 51210,
            'DimProduct validation failed: unexpected missing-descriptive-attributes profile.',
            1;
    END;


    IF @ExpectedMissingPhysicalAttributes <> 2
       OR @ActualMissingPhysicalAttributes <> 2
    BEGIN
        THROW 51211,
            'DimProduct validation failed: unexpected missing-physical-attributes profile.',
            1;
    END;


    IF @ExpectedZeroWeight <> 4
       OR @ActualZeroWeight <> 4
    BEGIN
        THROW 51212,
            'DimProduct validation failed: unexpected zero-weight profile.',
            1;
    END;


    PRINT 'DIM PRODUCT VALIDATION PASSED.';
END;
GO