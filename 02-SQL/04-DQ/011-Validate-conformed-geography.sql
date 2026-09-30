USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   Conformed Geography Data Quality Validation

   Grain:
   1 row = 1 ZIP code prefix
   ========================================================= */


/* =========================================================
   1. Row count and uniqueness
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount],
    COUNT(DISTINCT ZipCodePrefix) AS DistinctZIPs
FROM conformed.Geography;
GO


SELECT
    ZipCodePrefix,
    COUNT(*) AS DuplicateRows
FROM conformed.Geography
GROUP BY ZipCodePrefix
HAVING COUNT(*) > 1;
GO


/* =========================================================
   2. Required Customer / Seller ZIP coverage
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
   3. Missing Geography attributes
   ========================================================= */

SELECT
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
   4. Geography resolution flags
   ========================================================= */

SELECT
    SUM(CAST(MissingFromGeolocationFlag AS INT))
        AS MissingFromGeolocation,

    SUM(CAST(StateConflictFlag AS INT))
        AS StateConflicts,

    SUM(CAST(StateAmbiguousFlag AS INT))
        AS StateAmbiguous,

    SUM(CAST(StateResolvedByReferenceFlag AS INT))
        AS StatesResolvedByReference,

    SUM(CAST(CityAmbiguousFlag AS INT))
        AS CityAmbiguous,

    SUM(CAST(CityResolvedByReferenceFlag AS INT))
        AS CitiesResolvedByReference,

    SUM(CAST(ReferenceFallbackFlag AS INT))
        AS ReferenceFallbackZIPs

FROM conformed.Geography;
GO


/* =========================================================
   5. Validate Brazilian state codes
   ========================================================= */

SELECT
    ZipCodePrefix,
    StateCode
FROM conformed.Geography
WHERE StateCode IS NULL
   OR StateCode NOT IN
   (
       'AC','AL','AP','AM','BA','CE','DF',
       'ES','GO','MA','MT','MS','MG','PA',
       'PB','PR','PE','PI','RJ','RN','RS',
       'RO','RR','SC','SP','SE','TO'
   )
ORDER BY ZipCodePrefix;
GO


/* =========================================================
   6. Validate global coordinate ranges
   ========================================================= */

SELECT
    ZipCodePrefix,
    RepresentativeLatitude,
    RepresentativeLongitude
FROM conformed.Geography
WHERE
       RepresentativeLatitude < -90
    OR RepresentativeLatitude > 90
    OR RepresentativeLongitude < -180
    OR RepresentativeLongitude > 180
ORDER BY ZipCodePrefix;
GO


/* =========================================================
   7. Missing-from-geolocation rows

   Expected:
   Coordinates remain NULL.
   City / State come only from Customer / Seller fallback.
   ========================================================= */

SELECT
    COUNT(*) AS InvalidFallbackRows
FROM conformed.Geography
WHERE MissingFromGeolocationFlag = 1
  AND
  (
       ReferenceFallbackFlag <> 1
       OR StateCode IS NULL
       OR CityName IS NULL
       OR RepresentativeLatitude IS NOT NULL
       OR RepresentativeLongitude IS NOT NULL
  );
GO


/* =========================================================
   8. Ambiguous cities

   Expected:
   CityName remains NULL rather than selecting an arbitrary
   source label.
   ========================================================= */

SELECT
    COUNT(*) AS InvalidAmbiguousCityRows
FROM conformed.Geography
WHERE CityAmbiguousFlag = 1
  AND CityName IS NOT NULL;
GO


/* =========================================================
   9. Summary
   ========================================================= */

SELECT
    CASE
        WHEN
            (SELECT COUNT(*)
             FROM conformed.Geography) = 19177

        AND
            (SELECT COUNT(*)
             FROM conformed.Geography
             WHERE StateCode IS NULL) = 0

        AND
            (SELECT COUNT(*)
             FROM conformed.Geography
             WHERE MissingFromGeolocationFlag = 1) = 162

        AND
            (SELECT COUNT(*)
             FROM conformed.Geography
             WHERE StateAmbiguousFlag = 1) = 0

        AND
            (SELECT COUNT(*)
             FROM conformed.Geography
             WHERE CityAmbiguousFlag = 1) = 20

        AND
            (SELECT COUNT(*)
             FROM conformed.Geography
             WHERE CityResolvedByReferenceFlag = 1) = 12

        THEN 'CONFORMED GEOGRAPHY VALIDATION PASSED'

        ELSE 'CONFORMED GEOGRAPHY VALIDATION FAILED'
    END AS GeographyValidationStatus;
GO