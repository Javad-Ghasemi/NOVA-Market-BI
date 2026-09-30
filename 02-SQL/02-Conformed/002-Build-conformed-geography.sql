USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   Cleanup temporary objects from previous executions

   Allows the build script to be safely rerun in the same
   SQL Server session.
   ========================================================= */

DROP TABLE IF EXISTS #ReferenceObservation;
DROP TABLE IF EXISTS #ReferenceStateCount;
DROP TABLE IF EXISTS #ReferenceCityCount;
DROP TABLE IF EXISTS #ZipUniverse;
DROP TABLE IF EXISTS #GeoSummary;
DROP TABLE IF EXISTS #GeoStateCandidate;
DROP TABLE IF EXISTS #GeoStateRanked;
DROP TABLE IF EXISTS #GeoStateResolution;
DROP TABLE IF EXISTS #GeoCityCandidate;
DROP TABLE IF EXISTS #GeoCityCandidateWithSupport;
DROP TABLE IF EXISTS #GeoCityRanked;
DROP TABLE IF EXISTS #GeoCityResolutionKey;
DROP TABLE IF EXISTS #GeoCityDisplayCandidate;
DROP TABLE IF EXISTS #GeoCityDisplayRanked;
DROP TABLE IF EXISTS #GeoCityResolution;
DROP TABLE IF EXISTS #ReferenceFallback;
DROP TABLE IF EXISTS #RepresentativeCoordinates;
GO
/* =========================================================
   NOVA Market BI
   Conformed Geography

   Grain:
   1 row = 1 ZIP code prefix

   Sources:
   - stg.geolocation
   - stg.customers
   - stg.sellers

   Design rules:
   1. Preserve source rows in staging.
   2. Resolve one representative state per ZIP.
   3. Resolve city labels using normalized comparison.
   4. Use customer/seller observations only as tie-breakers
      or fallback when geolocation does not contain the ZIP.
   5. Do not fabricate coordinates.
   ========================================================= */


IF OBJECT_ID(N'conformed.Geography', N'U') IS NOT NULL
    DROP TABLE conformed.Geography;
GO


CREATE TABLE conformed.Geography
(
    ZipCodePrefix                       VARCHAR(5)      NOT NULL,

    CityName                            NVARCHAR(100)   NULL,
    StateCode                           CHAR(2)         NULL,

    RepresentativeLatitude             DECIMAL(28,20)  NULL,
    RepresentativeLongitude            DECIMAL(28,20)  NULL,

    GeolocationSourceRowCount           INT             NOT NULL,
    GeolocationDistinctStateCount       SMALLINT        NOT NULL,
    GeolocationDistinctCityLabelCount   INT             NOT NULL,

    MissingFromGeolocationFlag          BIT             NOT NULL,
    StateConflictFlag                   BIT             NOT NULL,
    StateAmbiguousFlag                  BIT             NOT NULL,
    StateResolvedByReferenceFlag        BIT             NOT NULL,

    CityAmbiguousFlag                   BIT             NOT NULL,
    CityResolvedByReferenceFlag         BIT             NOT NULL,

    ReferenceFallbackFlag               BIT             NOT NULL,

    CONSTRAINT PK_ConformedGeography
        PRIMARY KEY (ZipCodePrefix)
);
GO


/* =========================================================
   Reference observations from Customers and Sellers
   ========================================================= */

SELECT
    x.ZipCodePrefix,
    x.CityName,
    x.StateCode,

    REPLACE(
        REPLACE(
            REPLACE(
                LOWER(
                    LTRIM(
                        RTRIM(x.CityName)
                    )
                ) COLLATE Latin1_General_100_CI_AI,
                N' ',
                N''
            ),
            N'-',
            N''
        ),
        N'''',
        N''
    ) AS CityMatchKey

INTO #ReferenceObservation

FROM
(
    SELECT
        customer_zip_code_prefix AS ZipCodePrefix,
        customer_city AS CityName,
        customer_state AS StateCode
    FROM stg.customers

    UNION ALL

    SELECT
        seller_zip_code_prefix,
        seller_city,
        seller_state
    FROM stg.sellers
) x;
GO


/* =========================================================
   Reference support by State
   ========================================================= */

SELECT
    ZipCodePrefix,
    StateCode,
    COUNT(*) AS SupportRows

INTO #ReferenceStateCount

FROM #ReferenceObservation

GROUP BY
    ZipCodePrefix,
    StateCode;
GO


/* =========================================================
   Reference support by normalized City
   ========================================================= */

SELECT
    ZipCodePrefix,
    StateCode,
    CityMatchKey,
    COUNT(*) AS SupportRows

INTO #ReferenceCityCount

FROM #ReferenceObservation

GROUP BY
    ZipCodePrefix,
    StateCode,
    CityMatchKey;
GO


/* =========================================================
   ZIP Universe

   Includes every ZIP found in any source used by the DWH.
   ========================================================= */

SELECT
    ZipCodePrefix

INTO #ZipUniverse

FROM
(
    SELECT
        geolocation_zip_code_prefix AS ZipCodePrefix
    FROM stg.geolocation

    UNION

    SELECT
        customer_zip_code_prefix
    FROM stg.customers

    UNION

    SELECT
        seller_zip_code_prefix
    FROM stg.sellers
) x;
GO


/* =========================================================
   Geolocation source statistics
   ========================================================= */

SELECT
    geolocation_zip_code_prefix AS ZipCodePrefix,

    COUNT(*) AS SourceRowCount,

    COUNT(
        DISTINCT geolocation_state
    ) AS DistinctStateCount,

    COUNT(
        DISTINCT geolocation_city
    ) AS DistinctCityLabelCount

INTO #GeoSummary

FROM stg.geolocation

GROUP BY
    geolocation_zip_code_prefix;
GO


/* =========================================================
   State candidates

   Primary rule:
   Highest geolocation frequency.

   Tie-breaker:
   Customer / Seller support.
   ========================================================= */

SELECT
    g.geolocation_zip_code_prefix AS ZipCodePrefix,
    g.geolocation_state AS StateCode,

    COUNT(*) AS GeoRows,

    ISNULL(
        r.SupportRows,
        0
    ) AS ReferenceSupportRows

INTO #GeoStateCandidate

FROM stg.geolocation g

LEFT JOIN #ReferenceStateCount r
    ON  g.geolocation_zip_code_prefix = r.ZipCodePrefix
    AND g.geolocation_state = r.StateCode

GROUP BY
    g.geolocation_zip_code_prefix,
    g.geolocation_state,
    r.SupportRows;
GO


SELECT
    *,

    DENSE_RANK() OVER
    (
        PARTITION BY ZipCodePrefix
        ORDER BY
            GeoRows DESC,
            ReferenceSupportRows DESC
    ) AS ResolutionRank,

    DENSE_RANK() OVER
    (
        PARTITION BY ZipCodePrefix
        ORDER BY
            GeoRows DESC
    ) AS GeoOnlyRank

INTO #GeoStateRanked

FROM #GeoStateCandidate;
GO


/* =========================================================
   State resolution
   ========================================================= */

SELECT
    ZipCodePrefix,

    CASE
        WHEN
            SUM(
                CASE
                    WHEN ResolutionRank = 1
                    THEN 1
                    ELSE 0
                END
            ) = 1

        THEN
            MAX(
                CASE
                    WHEN ResolutionRank = 1
                    THEN StateCode
                END
            )

        ELSE NULL
    END AS RepresentativeState,

    COUNT(*) AS DistinctStateCount,

    CASE
        WHEN COUNT(*) > 1
        THEN 1
        ELSE 0
    END AS StateConflictFlag,

    CASE
        WHEN
            SUM(
                CASE
                    WHEN ResolutionRank = 1
                    THEN 1
                    ELSE 0
                END
            ) > 1

        THEN 1
        ELSE 0
    END AS StateAmbiguousFlag,

    CASE
        WHEN
            SUM(
                CASE
                    WHEN GeoOnlyRank = 1
                    THEN 1
                    ELSE 0
                END
            ) > 1

            AND

            SUM(
                CASE
                    WHEN ResolutionRank = 1
                    THEN 1
                    ELSE 0
                END
            ) = 1

            AND

            MAX(
                CASE
                    WHEN ResolutionRank = 1
                    THEN ReferenceSupportRows
                    ELSE 0
                END
            ) > 0

        THEN 1
        ELSE 0
    END AS StateResolvedByReferenceFlag

INTO #GeoStateResolution

FROM #GeoStateRanked

GROUP BY
    ZipCodePrefix;
GO


/* =========================================================
   Normalized geolocation City candidates

   City comparison:
   - case insensitive
   - accent insensitive
   - spaces removed
   - hyphens removed
   - apostrophes removed

   Only rows belonging to the resolved representative state
   participate in City selection.
   ========================================================= */

SELECT
    g.geolocation_zip_code_prefix AS ZipCodePrefix,

    REPLACE(
        REPLACE(
            REPLACE(
                LOWER(
                    LTRIM(
                        RTRIM(g.geolocation_city)
                    )
                ) COLLATE Latin1_General_100_CI_AI,
                N' ',
                N''
            ),
            N'-',
            N''
        ),
        N'''',
        N''
    ) AS CityMatchKey,

    COUNT(*) AS GeoRows

INTO #GeoCityCandidate

FROM stg.geolocation g

INNER JOIN #GeoStateResolution s
    ON  g.geolocation_zip_code_prefix = s.ZipCodePrefix
    AND g.geolocation_state = s.RepresentativeState

GROUP BY
    g.geolocation_zip_code_prefix,

    REPLACE(
        REPLACE(
            REPLACE(
                LOWER(
                    LTRIM(
                        RTRIM(g.geolocation_city)
                    )
                ) COLLATE Latin1_General_100_CI_AI,
                N' ',
                N''
            ),
            N'-',
            N''
        ),
        N'''',
        N''
    );
GO


/* =========================================================
   Add Customer / Seller support to City candidates
   ========================================================= */

SELECT
    c.ZipCodePrefix,
    c.CityMatchKey,
    c.GeoRows,

    ISNULL(
        r.SupportRows,
        0
    ) AS ReferenceSupportRows

INTO #GeoCityCandidateWithSupport

FROM #GeoCityCandidate c

INNER JOIN #GeoStateResolution s
    ON c.ZipCodePrefix = s.ZipCodePrefix

LEFT JOIN #ReferenceCityCount r
    ON  c.ZipCodePrefix = r.ZipCodePrefix
    AND s.RepresentativeState = r.StateCode
    AND c.CityMatchKey = r.CityMatchKey;
GO


SELECT
    *,

    DENSE_RANK() OVER
    (
        PARTITION BY ZipCodePrefix
        ORDER BY
            GeoRows DESC,
            ReferenceSupportRows DESC
    ) AS ResolutionRank,

    DENSE_RANK() OVER
    (
        PARTITION BY ZipCodePrefix
        ORDER BY
            GeoRows DESC
    ) AS GeoOnlyRank

INTO #GeoCityRanked

FROM #GeoCityCandidateWithSupport;
GO


/* =========================================================
   Resolve normalized CityMatchKey
   ========================================================= */

SELECT
    ZipCodePrefix,

    CASE
        WHEN
            SUM(
                CASE
                    WHEN ResolutionRank = 1
                    THEN 1
                    ELSE 0
                END
            ) = 1

        THEN
            MAX(
                CASE
                    WHEN ResolutionRank = 1
                    THEN CityMatchKey
                END
            )

        ELSE NULL
    END AS RepresentativeCityMatchKey,

    CASE
        WHEN
            SUM(
                CASE
                    WHEN ResolutionRank = 1
                    THEN 1
                    ELSE 0
                END
            ) > 1

        THEN 1
        ELSE 0
    END AS CityAmbiguousFlag,

    CASE
        WHEN
            SUM(
                CASE
                    WHEN GeoOnlyRank = 1
                    THEN 1
                    ELSE 0
                END
            ) > 1

            AND

            SUM(
                CASE
                    WHEN ResolutionRank = 1
                    THEN 1
                    ELSE 0
                END
            ) = 1

            AND

            MAX(
                CASE
                    WHEN ResolutionRank = 1
                    THEN ReferenceSupportRows
                    ELSE 0
                END
            ) > 0

        THEN 1
        ELSE 0
    END AS CityResolvedByReferenceFlag

INTO #GeoCityResolutionKey

FROM #GeoCityRanked

GROUP BY
    ZipCodePrefix;
GO


/* =========================================================
   Choose representative original City label

   After the normalized City has been resolved, preserve a
   real source label rather than generating a synthetic label.
   ========================================================= */

SELECT
    g.geolocation_zip_code_prefix AS ZipCodePrefix,

    REPLACE(
        REPLACE(
            REPLACE(
                LOWER(
                    LTRIM(
                        RTRIM(g.geolocation_city)
                    )
                ) COLLATE Latin1_General_100_CI_AI,
                N' ',
                N''
            ),
            N'-',
            N''
        ),
        N'''',
        N''
    ) AS CityMatchKey,

    g.geolocation_city AS CityName,

    COUNT(*) AS SourceRows

INTO #GeoCityDisplayCandidate

FROM stg.geolocation g

INNER JOIN #GeoStateResolution s
    ON  g.geolocation_zip_code_prefix = s.ZipCodePrefix
    AND g.geolocation_state = s.RepresentativeState

GROUP BY
    g.geolocation_zip_code_prefix,

    REPLACE(
        REPLACE(
            REPLACE(
                LOWER(
                    LTRIM(
                        RTRIM(g.geolocation_city)
                    )
                ) COLLATE Latin1_General_100_CI_AI,
                N' ',
                N''
            ),
            N'-',
            N''
        ),
        N'''',
        N''
    ),

    g.geolocation_city;
GO


SELECT
    *,

    ROW_NUMBER() OVER
    (
        PARTITION BY
            ZipCodePrefix,
            CityMatchKey

        ORDER BY
            SourceRows DESC,
            CityName
    ) AS DisplayRank

INTO #GeoCityDisplayRanked

FROM #GeoCityDisplayCandidate;
GO


SELECT
    r.ZipCodePrefix,

    d.CityName,

    r.CityAmbiguousFlag,
    r.CityResolvedByReferenceFlag

INTO #GeoCityResolution

FROM #GeoCityResolutionKey r

LEFT JOIN #GeoCityDisplayRanked d
    ON  r.ZipCodePrefix = d.ZipCodePrefix
    AND r.RepresentativeCityMatchKey = d.CityMatchKey
    AND d.DisplayRank = 1;
GO


/* =========================================================
   Fallback for ZIPs absent from geolocation

   Previous DQ confirmed that the missing ZIPs have a single
   consistent City and State across Customer / Seller sources.
   ========================================================= */

SELECT
    ZipCodePrefix,

    MIN(StateCode) AS StateCode,
    MIN(CityName) AS CityName,

    COUNT(
        DISTINCT StateCode
    ) AS DistinctStateCount,

    COUNT(
        DISTINCT CityName
    ) AS DistinctCityCount

INTO #ReferenceFallback

FROM #ReferenceObservation

GROUP BY
    ZipCodePrefix;
GO


/* =========================================================
   Representative coordinates

   Use the median of DISTINCT coordinate pairs from the
   representative state.

   Median is used to reduce sensitivity to coordinate
   outliers.

   Exact duplicate coordinate pairs do not receive additional
   weight.

   No coordinates are fabricated for ZIPs missing from the
   geolocation source.
   ========================================================= */

WITH DistinctCoordinates AS
(
    SELECT DISTINCT

        g.geolocation_zip_code_prefix AS ZipCodePrefix,
        g.geolocation_lat AS Latitude,
        g.geolocation_lng AS Longitude

    FROM stg.geolocation g

    INNER JOIN #GeoStateResolution s
        ON  g.geolocation_zip_code_prefix = s.ZipCodePrefix
        AND g.geolocation_state = s.RepresentativeState
),
MedianCoordinates AS
(
    SELECT

        ZipCodePrefix,

        PERCENTILE_CONT(0.5)
        WITHIN GROUP
        (
            ORDER BY Latitude
        )
        OVER
        (
            PARTITION BY ZipCodePrefix
        ) AS MedianLatitude,

        PERCENTILE_CONT(0.5)
        WITHIN GROUP
        (
            ORDER BY Longitude
        )
        OVER
        (
            PARTITION BY ZipCodePrefix
        ) AS MedianLongitude

    FROM DistinctCoordinates
)
SELECT DISTINCT

    ZipCodePrefix,

    CAST(
        MedianLatitude
        AS DECIMAL(28,20)
    ) AS RepresentativeLatitude,

    CAST(
        MedianLongitude
        AS DECIMAL(28,20)
    ) AS RepresentativeLongitude

INTO #RepresentativeCoordinates

FROM MedianCoordinates;
GO


/* =========================================================
   Populate Conformed Geography
   ========================================================= */

INSERT INTO conformed.Geography
(
    ZipCodePrefix,

    CityName,
    StateCode,

    RepresentativeLatitude,
    RepresentativeLongitude,

    GeolocationSourceRowCount,
    GeolocationDistinctStateCount,
    GeolocationDistinctCityLabelCount,

    MissingFromGeolocationFlag,

    StateConflictFlag,
    StateAmbiguousFlag,
    StateResolvedByReferenceFlag,

    CityAmbiguousFlag,
    CityResolvedByReferenceFlag,

    ReferenceFallbackFlag
)
SELECT
    u.ZipCodePrefix,

    CASE
        WHEN gs.ZipCodePrefix IS NULL
        THEN rf.CityName
        ELSE cr.CityName
    END AS CityName,

    CASE
        WHEN gs.ZipCodePrefix IS NULL
        THEN rf.StateCode
        ELSE sr.RepresentativeState
    END AS StateCode,

    rc.RepresentativeLatitude,
    rc.RepresentativeLongitude,

    ISNULL(
        gs.SourceRowCount,
        0
    ),

    ISNULL(
        gs.DistinctStateCount,
        0
    ),

    ISNULL(
        gs.DistinctCityLabelCount,
        0
    ),

    CASE
        WHEN gs.ZipCodePrefix IS NULL
        THEN 1
        ELSE 0
    END,

    ISNULL(
        sr.StateConflictFlag,
        0
    ),

    ISNULL(
        sr.StateAmbiguousFlag,
        0
    ),

    ISNULL(
        sr.StateResolvedByReferenceFlag,
        0
    ),

    ISNULL(
        cr.CityAmbiguousFlag,
        0
    ),

    ISNULL(
        cr.CityResolvedByReferenceFlag,
        0
    ),

    CASE
        WHEN gs.ZipCodePrefix IS NULL
             AND rf.ZipCodePrefix IS NOT NULL
        THEN 1
        ELSE 0
    END

FROM #ZipUniverse u

LEFT JOIN #GeoSummary gs
    ON u.ZipCodePrefix = gs.ZipCodePrefix

LEFT JOIN #GeoStateResolution sr
    ON u.ZipCodePrefix = sr.ZipCodePrefix

LEFT JOIN #GeoCityResolution cr
    ON u.ZipCodePrefix = cr.ZipCodePrefix

LEFT JOIN #ReferenceFallback rf
    ON u.ZipCodePrefix = rf.ZipCodePrefix

LEFT JOIN #RepresentativeCoordinates rc
    ON u.ZipCodePrefix = rc.ZipCodePrefix;
GO


/* =========================================================
   Validation 1:
   Overall Geography statistics
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount],

    SUM(
        CAST(
            MissingFromGeolocationFlag
            AS INT
        )
    ) AS MissingFromGeolocation,

    SUM(
        CAST(
            StateConflictFlag
            AS INT
        )
    ) AS StateConflicts,

    SUM(
        CAST(
            StateAmbiguousFlag
            AS INT
        )
    ) AS StateAmbiguous,

    SUM(
        CAST(
            StateResolvedByReferenceFlag
            AS INT
        )
    ) AS StatesResolvedByReference,

    SUM(
        CAST(
            CityAmbiguousFlag
            AS INT
        )
    ) AS CityAmbiguous,

    SUM(
        CAST(
            CityResolvedByReferenceFlag
            AS INT
        )
    ) AS CitiesResolvedByReference,

    SUM(
        CAST(
            ReferenceFallbackFlag
            AS INT
        )
    ) AS ReferenceFallbackZIPs,

    SUM(
        CASE
            WHEN StateCode IS NULL
            THEN 1
            ELSE 0
        END
    ) AS NullStates,

    SUM(
        CASE
            WHEN CityName IS NULL
            THEN 1
            ELSE 0
        END
    ) AS NullCities,

    SUM(
        CASE
            WHEN RepresentativeLatitude IS NULL
              OR RepresentativeLongitude IS NULL
            THEN 1
            ELSE 0
        END
    ) AS ZIPsWithoutCoordinates

FROM conformed.Geography;
GO


/* =========================================================
   Validation 2:
   Customer and Seller ZIP coverage
   ========================================================= */

WITH RequiredZip AS
(
    SELECT
        customer_zip_code_prefix AS ZipCodePrefix
    FROM stg.customers

    UNION

    SELECT
        seller_zip_code_prefix
    FROM stg.sellers
)
SELECT
    COUNT(*) AS RequiredZIPsMissingFromConformedGeography

FROM RequiredZip r

LEFT JOIN conformed.Geography g
    ON r.ZipCodePrefix = g.ZipCodePrefix

WHERE g.ZipCodePrefix IS NULL;
GO


/* =========================================================
   Validation 3:
   Show unresolved geography rows
   ========================================================= */

SELECT
    ZipCodePrefix,
    CityName,
    StateCode,

    StateConflictFlag,
    StateAmbiguousFlag,

    CityAmbiguousFlag,
    CityResolvedByReferenceFlag,

    MissingFromGeolocationFlag,
    ReferenceFallbackFlag

FROM conformed.Geography

WHERE
       StateAmbiguousFlag = 1
    OR CityAmbiguousFlag = 1

ORDER BY
    ZipCodePrefix;
GO