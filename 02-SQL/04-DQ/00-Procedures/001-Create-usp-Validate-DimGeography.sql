USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateDimGeography

   Purpose:
   - Single source of truth for DimGeography DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateDimGeography
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Expected source representation
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedGeography;

    SELECT
        ZipCodePrefix,
        CityName,
        StateCode,
        RepresentativeLatitude,
        RepresentativeLongitude,

        CAST(
            CASE
                WHEN RepresentativeLatitude IS NOT NULL
                 AND RepresentativeLongitude IS NOT NULL
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS HasCoordinates,

        MissingFromGeolocationFlag,
        StateConflictFlag,
        StateAmbiguousFlag,
        StateResolvedByReferenceFlag,
        CityAmbiguousFlag,
        CityResolvedByReferenceFlag,
        ReferenceFallbackFlag

    INTO #ExpectedGeography
    FROM conformed.Geography;


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @ExpectedBusinessRows             bigint,
        @ActualTotalRows                  bigint,
        @ActualBusinessRows               bigint,
        @DistinctBusinessZIPs             bigint,
        @UnknownRows                      bigint,
        @ValidUnknownRows                 bigint,
        @DuplicateBusinessZIPGroups       bigint,
        @MissingConformedZIPs             bigint,
        @SourceToTargetDifferences        bigint,
        @TargetToSourceDifferences        bigint,

        @NullCities                       bigint,
        @ZIPsWithoutCoordinates           bigint,
        @MissingFromGeolocation           bigint,
        @StateConflicts                   bigint,
        @StateAmbiguous                   bigint,
        @CityAmbiguous                    bigint,
        @CitiesResolvedByReference        bigint,
        @ReferenceFallbackZIPs            bigint;


    SELECT
        @ExpectedBusinessRows = COUNT_BIG(*)
    FROM #ExpectedGeography;


    SELECT
        @ActualTotalRows = COUNT_BIG(*),

        @ActualBusinessRows =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @UnknownRows =
            SUM(
                CASE
                    WHEN GeographyKey = 0
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @NullCities =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND CityName IS NULL
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @ZIPsWithoutCoordinates =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND HasCoordinates = 0
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @MissingFromGeolocation =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND MissingFromGeolocationFlag = 1
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @StateConflicts =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND StateConflictFlag = 1
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @StateAmbiguous =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND StateAmbiguousFlag = 1
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @CityAmbiguous =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND CityAmbiguousFlag = 1
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @CitiesResolvedByReference =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND CityResolvedByReferenceFlag = 1
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            ),

        @ReferenceFallbackZIPs =
            SUM(
                CASE
                    WHEN GeographyKey <> 0
                     AND ReferenceFallbackFlag = 1
                    THEN CAST(1 AS bigint)
                    ELSE CAST(0 AS bigint)
                END
            )

    FROM dwh.DimGeography;


    SELECT
        @DistinctBusinessZIPs =
            COUNT_BIG(DISTINCT ZipCodePrefix)
    FROM dwh.DimGeography
    WHERE GeographyKey <> 0;


    /* =====================================================
       Unknown member validation
       ===================================================== */

    SELECT
        @ValidUnknownRows = COUNT_BIG(*)
    FROM dwh.DimGeography
    WHERE GeographyKey = 0
      AND ZipCodePrefix IS NULL
      AND CityName = N'Unknown'
      AND StateCode IS NULL
      AND RepresentativeLatitude IS NULL
      AND RepresentativeLongitude IS NULL
      AND HasCoordinates = 0
      AND MissingFromGeolocationFlag = 0
      AND StateConflictFlag = 0
      AND StateAmbiguousFlag = 0
      AND StateResolvedByReferenceFlag = 0
      AND CityAmbiguousFlag = 0
      AND CityResolvedByReferenceFlag = 0
      AND ReferenceFallbackFlag = 0;


    /* =====================================================
       Business-key uniqueness
       ===================================================== */

    SELECT
        @DuplicateBusinessZIPGroups = COUNT_BIG(*)
    FROM
    (
        SELECT ZipCodePrefix
        FROM dwh.DimGeography
        WHERE GeographyKey <> 0
        GROUP BY ZipCodePrefix
        HAVING COUNT_BIG(*) > 1
    ) AS d;


    /* =====================================================
       Conformed ZIP coverage
       ===================================================== */

    SELECT
        @MissingConformedZIPs = COUNT_BIG(*)
    FROM #ExpectedGeography AS c
    LEFT JOIN dwh.DimGeography AS d
        ON c.ZipCodePrefix = d.ZipCodePrefix
       AND d.GeographyKey <> 0
    WHERE d.GeographyKey IS NULL;


    /* =====================================================
       Source -> Target exact comparison
       ===================================================== */

    SELECT
        @SourceToTargetDifferences = COUNT_BIG(*)
    FROM
    (
        SELECT
            ZipCodePrefix,
            CityName,
            StateCode,
            RepresentativeLatitude,
            RepresentativeLongitude,
            HasCoordinates,
            MissingFromGeolocationFlag,
            StateConflictFlag,
            StateAmbiguousFlag,
            StateResolvedByReferenceFlag,
            CityAmbiguousFlag,
            CityResolvedByReferenceFlag,
            ReferenceFallbackFlag
        FROM #ExpectedGeography

        EXCEPT

        SELECT
            ZipCodePrefix,
            CityName,
            StateCode,
            RepresentativeLatitude,
            RepresentativeLongitude,
            HasCoordinates,
            MissingFromGeolocationFlag,
            StateConflictFlag,
            StateAmbiguousFlag,
            StateResolvedByReferenceFlag,
            CityAmbiguousFlag,
            CityResolvedByReferenceFlag,
            ReferenceFallbackFlag
        FROM dwh.DimGeography
        WHERE GeographyKey <> 0
    ) AS x;


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)
    FROM
    (
        SELECT
            ZipCodePrefix,
            CityName,
            StateCode,
            RepresentativeLatitude,
            RepresentativeLongitude,
            HasCoordinates,
            MissingFromGeolocationFlag,
            StateConflictFlag,
            StateAmbiguousFlag,
            StateResolvedByReferenceFlag,
            CityAmbiguousFlag,
            CityResolvedByReferenceFlag,
            ReferenceFallbackFlag
        FROM dwh.DimGeography
        WHERE GeographyKey <> 0

        EXCEPT

        SELECT
            ZipCodePrefix,
            CityName,
            StateCode,
            RepresentativeLatitude,
            RepresentativeLongitude,
            HasCoordinates,
            MissingFromGeolocationFlag,
            StateConflictFlag,
            StateAmbiguousFlag,
            StateResolvedByReferenceFlag,
            CityAmbiguousFlag,
            CityResolvedByReferenceFlag,
            ReferenceFallbackFlag
        FROM #ExpectedGeography
    ) AS x;


    /* =====================================================
       Diagnostic summary
       ===================================================== */

    SELECT
        @ExpectedBusinessRows          AS ExpectedBusinessRows,
        @ActualTotalRows               AS ActualTotalRows,
        @ActualBusinessRows            AS ActualBusinessRows,
        @DistinctBusinessZIPs          AS DistinctBusinessZIPs,
        @UnknownRows                   AS UnknownRows,
        @ValidUnknownRows              AS ValidUnknownRows,

        @DuplicateBusinessZIPGroups    AS DuplicateBusinessZIPGroups,
        @MissingConformedZIPs          AS MissingConformedZIPs,

        @NullCities                    AS NullCities,
        @ZIPsWithoutCoordinates        AS ZIPsWithoutCoordinates,
        @MissingFromGeolocation        AS MissingFromGeolocation,
        @StateConflicts                AS StateConflicts,
        @StateAmbiguous                AS StateAmbiguous,
        @CityAmbiguous                 AS CityAmbiguous,
        @CitiesResolvedByReference     AS CitiesResolvedByReference,
        @ReferenceFallbackZIPs         AS ReferenceFallbackZIPs,

        @SourceToTargetDifferences     AS SourceToTargetDifferences,
        @TargetToSourceDifferences     AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @ExpectedBusinessRows <> 19177
    BEGIN
        THROW 51120,
            'DimGeography validation failed: conformed Geography baseline row count changed.',
            1;
    END;


    IF @ActualBusinessRows <> @ExpectedBusinessRows
       OR @ActualTotalRows <> @ExpectedBusinessRows + 1
    BEGIN
        THROW 51121,
            'DimGeography validation failed: row count mismatch.',
            1;
    END;


    IF @UnknownRows <> 1
       OR @ValidUnknownRows <> 1
    BEGIN
        THROW 51122,
            'DimGeography validation failed: invalid Unknown member.',
            1;
    END;


    IF @DistinctBusinessZIPs <> @ExpectedBusinessRows
       OR @DuplicateBusinessZIPGroups <> 0
    BEGIN
        THROW 51123,
            'DimGeography validation failed: duplicate or invalid business ZIP grain.',
            1;
    END;


    IF @MissingConformedZIPs <> 0
    BEGIN
        THROW 51124,
            'DimGeography validation failed: one or more conformed ZIPs are missing.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51125,
            'DimGeography validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51126,
            'DimGeography validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected source anomaly profile

       These values document the validated Olist/conformed
       geography characteristics and must remain stable for
       the current project dataset.
       ===================================================== */

    IF @NullCities <> 20
    BEGIN
        THROW 51127,
            'DimGeography validation failed: unexpected NULL city count.',
            1;
    END;


    IF @ZIPsWithoutCoordinates <> 162
       OR @MissingFromGeolocation <> 162
    BEGIN
        THROW 51128,
            'DimGeography validation failed: unexpected missing-coordinate profile.',
            1;
    END;


    IF @StateConflicts <> 8
       OR @StateAmbiguous <> 0
    BEGIN
        THROW 51129,
            'DimGeography validation failed: unexpected state-resolution profile.',
            1;
    END;


    IF @CityAmbiguous <> 20
       OR @CitiesResolvedByReference <> 12
    BEGIN
        THROW 51130,
            'DimGeography validation failed: unexpected city-resolution profile.',
            1;
    END;


    IF @ReferenceFallbackZIPs <> 162
    BEGIN
        THROW 51131,
            'DimGeography validation failed: unexpected reference-fallback count.',
            1;
    END;


    PRINT 'DIM GEOGRAPHY VALIDATION PASSED.';
END;
GO