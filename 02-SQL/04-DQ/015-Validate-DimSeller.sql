USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #ExpectedDimSeller;
GO


/* =========================================================
   Build expected DimSeller rows from trusted upstream layers
   ========================================================= */

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
        AS BIT
    ) AS CityMismatchFlag,

    CAST(
        CASE
            WHEN cg.ZipCodePrefix IS NULL THEN 1

            WHEN s.seller_state COLLATE Latin1_General_100_CI_AI
                 <> cg.StateCode COLLATE Latin1_General_100_CI_AI
            THEN 1

            ELSE 0
        END
        AS BIT
    ) AS StateMismatchFlag

INTO #ExpectedDimSeller

FROM stg.sellers AS s

LEFT JOIN conformed.Geography AS cg
    ON s.seller_zip_code_prefix = cg.ZipCodePrefix

LEFT JOIN dwh.DimGeography AS dg
    ON s.seller_zip_code_prefix = dg.ZipCodePrefix;
GO


/* =========================================================
   Summary
   ========================================================= */

SELECT
    COUNT(*) AS ExpectedBusinessRows,
    SUM(CASE WHEN CityMismatchFlag = 1 THEN 1 ELSE 0 END)
        AS ExpectedCityMismatches,
    SUM(CASE WHEN StateMismatchFlag = 1 THEN 1 ELSE 0 END)
        AS ExpectedStateMismatches
FROM #ExpectedDimSeller;

SELECT
    COUNT(*) AS [DimSellerRows],
    SUM(CASE WHEN SellerKey <> 0 THEN 1 ELSE 0 END)
        AS BusinessRows,
    SUM(CASE WHEN SellerKey = 0 THEN 1 ELSE 0 END)
        AS UnknownRows,
    SUM(
        CASE
            WHEN SellerKey <> 0
             AND CityMismatchFlag = 1
            THEN 1 ELSE 0
        END
    ) AS CityMismatches,
    SUM(
        CASE
            WHEN SellerKey <> 0
             AND StateMismatchFlag = 1
            THEN 1 ELSE 0
        END
    ) AS StateMismatches
FROM dwh.DimSeller;
GO


/* =========================================================
   Validation metrics
   ========================================================= */

DECLARE
    @SourceSellerCount          INT,
    @TargetBusinessCount       INT,
    @UnknownRowCount           INT,
    @DuplicateSellerIDs        INT,
    @NullBusinessSellerIDs     INT,
    @MissingGeographyKeys      INT,
    @InvalidGeographyKeys      INT,
    @SourceToTargetDifferences INT,
    @TargetToSourceDifferences INT;


SELECT
    @SourceSellerCount = COUNT(*)
FROM stg.sellers;


SELECT
    @TargetBusinessCount =
        COUNT(*)
FROM dwh.DimSeller
WHERE SellerKey <> 0;


SELECT
    @UnknownRowCount =
        COUNT(*)
FROM dwh.DimSeller
WHERE SellerKey = 0
  AND SellerID IS NULL
  AND GeographyKey = 0
  AND SourceZipCodePrefix IS NULL
  AND SourceCityName = N'Unknown'
  AND SourceStateCode IS NULL
  AND CityMismatchFlag = 0
  AND StateMismatchFlag = 0;


SELECT
    @DuplicateSellerIDs =
        COUNT(*)
FROM
(
    SELECT SellerID
    FROM dwh.DimSeller
    WHERE SellerKey <> 0
    GROUP BY SellerID
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @NullBusinessSellerIDs =
        COUNT(*)
FROM dwh.DimSeller
WHERE SellerKey <> 0
  AND SellerID IS NULL;


SELECT
    @MissingGeographyKeys =
        COUNT(*)
FROM #ExpectedDimSeller
WHERE GeographyKey IS NULL;


SELECT
    @InvalidGeographyKeys =
        COUNT(*)
FROM dwh.DimSeller AS s
LEFT JOIN dwh.DimGeography AS g
    ON s.GeographyKey = g.GeographyKey
WHERE s.SellerKey <> 0
  AND g.GeographyKey IS NULL;


SELECT
    @SourceToTargetDifferences =
        COUNT(*)
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


SELECT
    @TargetToSourceDifferences =
        COUNT(*)
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


SELECT
    @SourceSellerCount          AS SourceSellerCount,
    @TargetBusinessCount       AS TargetBusinessCount,
    @UnknownRowCount           AS ValidUnknownRows,
    @DuplicateSellerIDs        AS DuplicateSellerIDs,
    @NullBusinessSellerIDs     AS NullBusinessSellerIDs,
    @MissingGeographyKeys      AS MissingGeographyKeys,
    @InvalidGeographyKeys      AS InvalidGeographyKeys,
    @SourceToTargetDifferences AS SourceToTargetDifferences,
    @TargetToSourceDifferences AS TargetToSourceDifferences;
GO


/* =========================================================
   Pass / fail
   ========================================================= */

IF
(
    SELECT COUNT(*)
    FROM dwh.DimSeller
    WHERE SellerKey <> 0
)
<>
(
    SELECT COUNT(*)
    FROM stg.sellers
)
    THROW 51000, 'DimSeller validation failed: business row count mismatch.', 1;


IF
(
    SELECT COUNT(*)
    FROM dwh.DimSeller
    WHERE SellerKey = 0
      AND SellerID IS NULL
      AND GeographyKey = 0
      AND SourceZipCodePrefix IS NULL
      AND SourceCityName = N'Unknown'
      AND SourceStateCode IS NULL
      AND CityMismatchFlag = 0
      AND StateMismatchFlag = 0
) <> 1
    THROW 51001, 'DimSeller validation failed: invalid Unknown member.', 1;


IF EXISTS
(
    SELECT SellerID
    FROM dwh.DimSeller
    WHERE SellerKey <> 0
    GROUP BY SellerID
    HAVING COUNT(*) > 1
)
    THROW 51002, 'DimSeller validation failed: duplicate SellerID.', 1;


IF EXISTS
(
    SELECT 1
    FROM dwh.DimSeller
    WHERE SellerKey <> 0
      AND SellerID IS NULL
)
    THROW 51003, 'DimSeller validation failed: NULL business SellerID.', 1;


IF EXISTS
(
    SELECT 1
    FROM #ExpectedDimSeller
    WHERE GeographyKey IS NULL
)
    THROW 51004, 'DimSeller validation failed: seller ZIP missing from DimGeography.', 1;


IF EXISTS
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
)
    THROW 51005, 'DimSeller validation failed: expected rows missing or different.', 1;


IF EXISTS
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
)
    THROW 51006, 'DimSeller validation failed: unexpected target rows.', 1;


PRINT 'DIMSELLER VALIDATION PASSED.';
GO