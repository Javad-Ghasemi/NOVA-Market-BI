USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateDimSeller

   Purpose:
   - Single source of truth for DimSeller DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateDimSeller
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Build expected DimSeller representation
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedDimSeller;

    SELECT
        s.seller_id AS SellerID,
        dg.GeographyKey,
        s.seller_zip_code_prefix AS SourceZipCodePrefix,
        s.seller_city AS SourceCityName,
        s.seller_state AS SourceStateCode,

        CAST(
            CASE
                WHEN cg.ZipCodePrefix IS NULL THEN 1
                WHEN cg.CityName IS NULL THEN 1

                WHEN
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                LOWER(LTRIM(RTRIM(s.seller_city)))
                                    COLLATE Latin1_General_100_CI_AI,
                                N' ',
                                N''
                            ),
                            N'-',
                            N''
                        ),
                        N'''',
                        N''
                    )
                    <>
                    REPLACE(
                        REPLACE(
                            REPLACE(
                                LOWER(LTRIM(RTRIM(cg.CityName)))
                                    COLLATE Latin1_General_100_CI_AI,
                                N' ',
                                N''
                            ),
                            N'-',
                            N''
                        ),
                        N'''',
                        N''
                    )
                THEN 1

                ELSE 0
            END
            AS bit
        ) AS CityMismatchFlag,

        CAST(
            CASE
                WHEN cg.ZipCodePrefix IS NULL THEN 1

                WHEN s.seller_state COLLATE Latin1_General_100_CI_AI
                     <> cg.StateCode COLLATE Latin1_General_100_CI_AI
                THEN 1

                ELSE 0
            END
            AS bit
        ) AS StateMismatchFlag

    INTO #ExpectedDimSeller

    FROM stg.sellers AS s

    LEFT JOIN conformed.Geography AS cg
        ON s.seller_zip_code_prefix = cg.ZipCodePrefix

    LEFT JOIN dwh.DimGeography AS dg
        ON s.seller_zip_code_prefix = dg.ZipCodePrefix
       AND dg.GeographyKey <> 0;


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @SourceSellerCount              bigint,
        @ExpectedCityMismatches         bigint,
        @ExpectedStateMismatches        bigint,

        @TargetTotalRows                bigint,
        @TargetBusinessCount            bigint,
        @DistinctBusinessSellerIDs      bigint,
        @ValidUnknownRows               bigint,

        @ActualCityMismatches           bigint,
        @ActualStateMismatches          bigint,

        @DuplicateSellerIDs             bigint,
        @NullBusinessSellerIDs          bigint,
        @MissingGeographyKeys           bigint,
        @InvalidGeographyKeys           bigint,

        @SourceToTargetDifferences      bigint,
        @TargetToSourceDifferences      bigint;


    /* =====================================================
       Expected source metrics
       ===================================================== */

    SELECT
        @SourceSellerCount = COUNT_BIG(*),

        @ExpectedCityMismatches =
            COALESCE(
                SUM(
                    CASE
                        WHEN CityMismatchFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ExpectedStateMismatches =
            COALESCE(
                SUM(
                    CASE
                        WHEN StateMismatchFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM #ExpectedDimSeller;


    /* =====================================================
       Target metrics
       ===================================================== */

    SELECT
        @TargetTotalRows =
            COUNT_BIG(*),

        @TargetBusinessCount =
            COALESCE(
                SUM(
                    CASE
                        WHEN SellerKey <> 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualCityMismatches =
            COALESCE(
                SUM(
                    CASE
                        WHEN SellerKey <> 0
                         AND CityMismatchFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ActualStateMismatches =
            COALESCE(
                SUM(
                    CASE
                        WHEN SellerKey <> 0
                         AND StateMismatchFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.DimSeller;


    SELECT
        @DistinctBusinessSellerIDs =
            COUNT_BIG(DISTINCT SellerID)
    FROM dwh.DimSeller
    WHERE SellerKey <> 0;


    /* =====================================================
       Unknown member validation
       ===================================================== */

    SELECT
        @ValidUnknownRows = COUNT_BIG(*)

    FROM dwh.DimSeller

    WHERE SellerKey = 0
      AND SellerID IS NULL
      AND GeographyKey = 0
      AND SourceZipCodePrefix IS NULL
      AND SourceCityName = N'Unknown'
      AND SourceStateCode IS NULL
      AND CityMismatchFlag = 0
      AND StateMismatchFlag = 0;


    /* =====================================================
       Business-key validation
       ===================================================== */

    SELECT
        @DuplicateSellerIDs = COUNT_BIG(*)

    FROM
    (
        SELECT SellerID

        FROM dwh.DimSeller

        WHERE SellerKey <> 0

        GROUP BY SellerID

        HAVING COUNT_BIG(*) > 1
    ) AS d;


    SELECT
        @NullBusinessSellerIDs = COUNT_BIG(*)

    FROM dwh.DimSeller

    WHERE SellerKey <> 0
      AND SellerID IS NULL;


    /* =====================================================
       Geography resolution
       ===================================================== */

    SELECT
        @MissingGeographyKeys = COUNT_BIG(*)

    FROM #ExpectedDimSeller

    WHERE GeographyKey IS NULL;


    SELECT
        @InvalidGeographyKeys = COUNT_BIG(*)

    FROM dwh.DimSeller AS s

    LEFT JOIN dwh.DimGeography AS g
        ON s.GeographyKey = g.GeographyKey

    WHERE s.SellerKey <> 0
      AND
      (
           s.GeographyKey = 0
        OR g.GeographyKey IS NULL
      );


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)

    FROM
    (
        SELECT
            SellerID,
            GeographyKey,
            SourceZipCodePrefix,
            SourceCityName,
            SourceStateCode,
            CityMismatchFlag,
            StateMismatchFlag

        FROM #ExpectedDimSeller

        EXCEPT

        SELECT
            SellerID,
            GeographyKey,
            SourceZipCodePrefix,
            SourceCityName,
            SourceStateCode,
            CityMismatchFlag,
            StateMismatchFlag

        FROM dwh.DimSeller

        WHERE SellerKey <> 0
    ) AS x;


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

    FROM
    (
        SELECT
            SellerID,
            GeographyKey,
            SourceZipCodePrefix,
            SourceCityName,
            SourceStateCode,
            CityMismatchFlag,
            StateMismatchFlag

        FROM dwh.DimSeller

        WHERE SellerKey <> 0

        EXCEPT

        SELECT
            SellerID,
            GeographyKey,
            SourceZipCodePrefix,
            SourceCityName,
            SourceStateCode,
            CityMismatchFlag,
            StateMismatchFlag

        FROM #ExpectedDimSeller
    ) AS x;


    /* =====================================================
       Diagnostic summary
       ===================================================== */

    SELECT
        @SourceSellerCount             AS SourceSellerCount,
        @TargetTotalRows               AS TargetTotalRows,
        @TargetBusinessCount           AS TargetBusinessCount,
        @DistinctBusinessSellerIDs     AS DistinctBusinessSellerIDs,
        @ValidUnknownRows              AS ValidUnknownRows,

        @DuplicateSellerIDs            AS DuplicateSellerIDs,
        @NullBusinessSellerIDs         AS NullBusinessSellerIDs,

        @MissingGeographyKeys          AS MissingGeographyKeys,
        @InvalidGeographyKeys          AS InvalidGeographyKeys,

        @ExpectedCityMismatches        AS ExpectedCityMismatches,
        @ActualCityMismatches          AS ActualCityMismatches,

        @ExpectedStateMismatches       AS ExpectedStateMismatches,
        @ActualStateMismatches         AS ActualStateMismatches,

        @SourceToTargetDifferences     AS SourceToTargetDifferences,
        @TargetToSourceDifferences     AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @SourceSellerCount <> 3095
    BEGIN
        THROW 51160,
            'DimSeller validation failed: staging Seller baseline row count changed.',
            1;
    END;


    IF @TargetBusinessCount <> @SourceSellerCount
       OR @TargetTotalRows <> @SourceSellerCount + 1
    BEGIN
        THROW 51161,
            'DimSeller validation failed: row count mismatch.',
            1;
    END;


    IF @ValidUnknownRows <> 1
    BEGIN
        THROW 51162,
            'DimSeller validation failed: invalid Unknown member.',
            1;
    END;


    IF @DistinctBusinessSellerIDs <> @SourceSellerCount
       OR @DuplicateSellerIDs <> 0
       OR @NullBusinessSellerIDs <> 0
    BEGIN
        THROW 51163,
            'DimSeller validation failed: invalid SellerID business-key grain.',
            1;
    END;


    IF @MissingGeographyKeys <> 0
    BEGIN
        THROW 51164,
            'DimSeller validation failed: seller ZIP missing from DimGeography.',
            1;
    END;


    IF @InvalidGeographyKeys <> 0
    BEGIN
        THROW 51165,
            'DimSeller validation failed: invalid business GeographyKey detected.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51166,
            'DimSeller validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51167,
            'DimSeller validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected current Olist seller anomaly profile
       ===================================================== */

    IF @ExpectedCityMismatches <> 94
       OR @ActualCityMismatches <> 94
    BEGIN
        THROW 51168,
            'DimSeller validation failed: unexpected city-mismatch profile.',
            1;
    END;


    IF @ExpectedStateMismatches <> 35
       OR @ActualStateMismatches <> 35
    BEGIN
        THROW 51169,
            'DimSeller validation failed: unexpected state-mismatch profile.',
            1;
    END;


    PRINT 'DIM SELLER VALIDATION PASSED.';
END;
GO