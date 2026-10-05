USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateDimProductCategory

   Purpose:
   - Single source of truth for DimProductCategory DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateDimProductCategory
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected business rows
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedDimProductCategory;

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
            AS bit
        ) AS MissingPersianLocalizationFlag

    INTO #ExpectedDimProductCategory

    FROM conformed.ProductCategory AS c

    LEFT JOIN meta.ProductCategoryLocalization AS l
        ON c.SourceCategoryName = l.SourceCategoryName;


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @ExpectedBusinessRows                bigint,
        @ExpectedMissingEnglishTranslations  bigint,
        @ExpectedMissingPersianLocalizations bigint,

        @ActualTotalRows                     bigint,
        @ActualBusinessRows                  bigint,
        @ActualMissingEnglishTranslations    bigint,
        @ActualMissingPersianLocalizations   bigint,

        @ValidUnknownRows                    bigint,
        @DuplicateSourceCategories           bigint,
        @NullBusinessCategories              bigint,
        @MissingPersianNames                 bigint,

        @InvalidEnglishFlags                 bigint,
        @InvalidPersianFlags                 bigint,

        @SourceToTargetDifferences           bigint,
        @TargetToSourceDifferences           bigint;


    /* =====================================================
       Expected source metrics
       ===================================================== */

    SELECT
        @ExpectedBusinessRows = COUNT_BIG(*),

        @ExpectedMissingEnglishTranslations =
            COALESCE(
                SUM(
                    CASE
                        WHEN MissingEnglishTranslationFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedMissingPersianLocalizations =
            COALESCE(
                SUM(
                    CASE
                        WHEN MissingPersianLocalizationFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedDimProductCategory;


    /* =====================================================
       Target metrics
       ===================================================== */

    SELECT
        @ActualTotalRows = COUNT_BIG(*),

        @ActualBusinessRows =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductCategoryKey <> 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualMissingEnglishTranslations =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductCategoryKey <> 0
                         AND MissingEnglishTranslationFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualMissingPersianLocalizations =
            COALESCE(
                SUM(
                    CASE
                        WHEN ProductCategoryKey <> 0
                         AND MissingPersianLocalizationFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.DimProductCategory;


    /* =====================================================
       Unknown member validation
       ===================================================== */

    SELECT
        @ValidUnknownRows = COUNT_BIG(*)

    FROM dwh.DimProductCategory

    WHERE ProductCategoryKey = 0
      AND SourceCategoryName IS NULL
      AND EnglishCategoryName = N'Unknown'
      AND PersianCategoryName = N'نامشخص'
      AND MissingEnglishTranslationFlag = 0
      AND MissingPersianLocalizationFlag = 0;


    /* =====================================================
       Business-key validation
       ===================================================== */

    SELECT
        @DuplicateSourceCategories = COUNT_BIG(*)

    FROM
    (
        SELECT SourceCategoryName

        FROM dwh.DimProductCategory

        WHERE ProductCategoryKey <> 0

        GROUP BY SourceCategoryName

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullBusinessCategories = COUNT_BIG(*)

    FROM dwh.DimProductCategory

    WHERE ProductCategoryKey <> 0
      AND SourceCategoryName IS NULL;


    /* =====================================================
       Localization validation
       ===================================================== */

    SELECT
        @MissingPersianNames = COUNT_BIG(*)

    FROM dwh.DimProductCategory

    WHERE ProductCategoryKey <> 0
      AND
      (
           PersianCategoryName IS NULL
        OR LTRIM(RTRIM(PersianCategoryName)) = N''
      );


    SELECT
        @InvalidEnglishFlags = COUNT_BIG(*)

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
        @InvalidPersianFlags = COUNT_BIG(*)

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


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

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


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

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

        @ValidUnknownRows
            AS ValidUnknownRows,

        @DuplicateSourceCategories
            AS DuplicateSourceCategories,

        @NullBusinessCategories
            AS NullBusinessCategories,

        @ExpectedMissingEnglishTranslations
            AS ExpectedMissingEnglishTranslations,

        @ActualMissingEnglishTranslations
            AS ActualMissingEnglishTranslations,

        @ExpectedMissingPersianLocalizations
            AS ExpectedMissingPersianLocalizations,

        @ActualMissingPersianLocalizations
            AS ActualMissingPersianLocalizations,

        @MissingPersianNames
            AS MissingPersianNames,

        @InvalidEnglishFlags
            AS InvalidEnglishFlags,

        @InvalidPersianFlags
            AS InvalidPersianFlags,

        @SourceToTargetDifferences
            AS SourceToTargetDifferences,

        @TargetToSourceDifferences
            AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @ExpectedBusinessRows <> 73
    BEGIN
        THROW 51180,
            'DimProductCategory validation failed: conformed category baseline row count changed.',
            1;
    END;


    IF @ActualBusinessRows <> @ExpectedBusinessRows
       OR @ActualTotalRows <> @ExpectedBusinessRows + 1
    BEGIN
        THROW 51181,
            'DimProductCategory validation failed: row count mismatch.',
            1;
    END;


    IF @ValidUnknownRows <> 1
    BEGIN
        THROW 51182,
            'DimProductCategory validation failed: invalid Unknown member.',
            1;
    END;


    IF @DuplicateSourceCategories <> 0
       OR @NullBusinessCategories <> 0
    BEGIN
        THROW 51183,
            'DimProductCategory validation failed: invalid source-category business-key grain.',
            1;
    END;


    IF @InvalidEnglishFlags <> 0
    BEGIN
        THROW 51184,
            'DimProductCategory validation failed: invalid English translation flags.',
            1;
    END;


    IF @InvalidPersianFlags <> 0
    BEGIN
        THROW 51185,
            'DimProductCategory validation failed: invalid Persian localization flags.',
            1;
    END;


    IF @MissingPersianNames <> 0
    BEGIN
        THROW 51186,
            'DimProductCategory validation failed: missing Persian category name.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51187,
            'DimProductCategory validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51188,
            'DimProductCategory validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist category profile
       ===================================================== */

    IF @ExpectedMissingEnglishTranslations <> 2
       OR @ActualMissingEnglishTranslations <> 2
    BEGIN
        THROW 51189,
            'DimProductCategory validation failed: unexpected missing-English-translation profile.',
            1;
    END;


    IF @ExpectedMissingPersianLocalizations <> 0
       OR @ActualMissingPersianLocalizations <> 0
    BEGIN
        THROW 51190,
            'DimProductCategory validation failed: unexpected Persian-localization profile.',
            1;
    END;


    PRINT 'DIM PRODUCT CATEGORY VALIDATION PASSED.';
END;
GO