USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.geolocation
   Source: Olist geolocation dataset

   Source Grain:
   One source geolocation observation.

   Important:
   The source does NOT expose a reliable row-level key.

   ZIP code prefix is NOT unique and exact duplicate rows
   legitimately exist in the source.

   Therefore:
   - No deduplication is applied in staging.
   - No primary/unique key is assumed.
   - Source rows are preserved exactly.

   Future DWH target:
   DimGeography

   Planned analytical grain:
   1 row per geolocation_zip_code_prefix

   Controlled aggregation / representative coordinates will
   be required before building DimGeography.
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.geolocation;

-- Expected: 1,000,163


------------------------------------------------------------
-- 2. NULL Audit
------------------------------------------------------------
SELECT
    SUM(CASE WHEN geolocation_zip_code_prefix IS NULL THEN 1 ELSE 0 END)
        AS ZipPrefixNulls,

    SUM(CASE WHEN geolocation_lat IS NULL THEN 1 ELSE 0 END)
        AS LatitudeNulls,

    SUM(CASE WHEN geolocation_lng IS NULL THEN 1 ELSE 0 END)
        AS LongitudeNulls,

    SUM(CASE WHEN geolocation_city IS NULL THEN 1 ELSE 0 END)
        AS CityNulls,

    SUM(CASE WHEN geolocation_state IS NULL THEN 1 ELSE 0 END)
        AS StateNulls
FROM stg.geolocation;

-- Expected: all 0


------------------------------------------------------------
-- 3. Blank Text Values
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN LTRIM(RTRIM(geolocation_city)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankCityRows,

    SUM(
        CASE
            WHEN LTRIM(RTRIM(geolocation_state)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankStateRows
FROM stg.geolocation;

-- Expected: 0


------------------------------------------------------------
-- 4. ZIP Prefix Format Validation
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN LEN(geolocation_zip_code_prefix) <> 5
            THEN 1 ELSE 0
        END
    ) AS InvalidZipLengthRows,

    SUM(
        CASE
            WHEN geolocation_zip_code_prefix LIKE '%[^0-9]%'
            THEN 1 ELSE 0
        END
    ) AS NonNumericZipRows
FROM stg.geolocation;

-- Expected:
-- InvalidZipLengthRows = 0
-- NonNumericZipRows    = 0


------------------------------------------------------------
-- 5. Distinct ZIP Prefixes
------------------------------------------------------------
SELECT
    COUNT(DISTINCT geolocation_zip_code_prefix)
        AS DistinctZipPrefixes
FROM stg.geolocation;

-- Expected: 19,015


------------------------------------------------------------
-- 6. ZIP Prefixes With Multiple Source Rows
------------------------------------------------------------
SELECT
    COUNT(*) AS DuplicateZipGroups
FROM
(
    SELECT
        geolocation_zip_code_prefix
    FROM stg.geolocation
    GROUP BY geolocation_zip_code_prefix
    HAVING COUNT(*) > 1
) x;

-- Expected: 17,972


------------------------------------------------------------
-- 7. Maximum Rows per ZIP Prefix
------------------------------------------------------------
SELECT
    MAX(x.RowsPerZip) AS MaxRowsPerZip
FROM
(
    SELECT
        geolocation_zip_code_prefix,
        COUNT(*) AS RowsPerZip
    FROM stg.geolocation
    GROUP BY geolocation_zip_code_prefix
) x;

-- Expected: 1,146


------------------------------------------------------------
-- 8. Exact Duplicate Source Rows
--
-- Exact duplicate rows are intentionally preserved in staging.
------------------------------------------------------------
WITH DuplicateGroups AS
(
    SELECT
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state,
        COUNT(*) AS DuplicateCount
    FROM stg.geolocation
    GROUP BY
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    HAVING COUNT(*) > 1
)
SELECT
    SUM(DuplicateCount - 1) AS ExactDuplicateRows
FROM DuplicateGroups;

-- Expected: 261,831


------------------------------------------------------------
-- 9. Distinct Source Rows
------------------------------------------------------------
SELECT
    COUNT(*) AS DistinctSourceRows
FROM
(
    SELECT DISTINCT
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    FROM stg.geolocation
) x;

-- Expected:
-- 1,000,163 - 261,831 = 738,332


------------------------------------------------------------
-- 10. State Count
------------------------------------------------------------
SELECT
    COUNT(DISTINCT geolocation_state) AS DistinctStates
FROM stg.geolocation;

-- Expected: 27


------------------------------------------------------------
-- 11. State Distribution
------------------------------------------------------------
SELECT
    geolocation_state,
    COUNT(*) AS GeolocationRows,
    COUNT(DISTINCT geolocation_zip_code_prefix)
        AS DistinctZipPrefixes
FROM stg.geolocation
GROUP BY geolocation_state
ORDER BY geolocation_state;

-- Informational


------------------------------------------------------------
-- 12. Brazilian State Code Validation
------------------------------------------------------------
SELECT
    COUNT(*) AS InvalidStateCodeRows
FROM stg.geolocation
WHERE geolocation_state NOT IN
(
    'AC','AL','AP','AM','BA','CE','DF','ES','GO',
    'MA','MT','MS','MG','PA','PB','PR','PE','PI',
    'RJ','RN','RS','RO','RR','SC','SP','SE','TO'
);

-- Expected: 0


------------------------------------------------------------
-- 13. City Length
------------------------------------------------------------
SELECT
    MAX(LEN(geolocation_city)) AS MaxCityLength
FROM stg.geolocation;

-- Expected source maximum: 38


------------------------------------------------------------
-- 14. Coordinate Range
------------------------------------------------------------
SELECT
    MIN(geolocation_lat) AS MinLatitude,
    MAX(geolocation_lat) AS MaxLatitude,
    MIN(geolocation_lng) AS MinLongitude,
    MAX(geolocation_lng) AS MaxLongitude
FROM stg.geolocation;

-- Observed source ranges:
-- Latitude:
--   -36.6053744107061
--    45.06593318269697
--
-- Longitude:
--   -101.46676644931476
--    121.10539381057764
--
-- These values are preserved in staging.


------------------------------------------------------------
-- 15. Globally Invalid Coordinates
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN geolocation_lat < -90
              OR geolocation_lat > 90
            THEN 1 ELSE 0
        END
    ) AS InvalidLatitudeRows,

    SUM(
        CASE
            WHEN geolocation_lng < -180
              OR geolocation_lng > 180
            THEN 1 ELSE 0
        END
    ) AS InvalidLongitudeRows
FROM stg.geolocation;

-- Expected: 0
-- This validates global coordinate limits only.


------------------------------------------------------------
-- 16. ZIP Prefixes Mapping to Multiple States
------------------------------------------------------------
SELECT
    COUNT(*) AS ZipPrefixesWithMultipleStates
FROM
(
    SELECT
        geolocation_zip_code_prefix
    FROM stg.geolocation
    GROUP BY geolocation_zip_code_prefix
    HAVING COUNT(DISTINCT geolocation_state) > 1
) x;

-- Investigate if > 0


------------------------------------------------------------
-- 17. Multi-State ZIP Prefix Detail
------------------------------------------------------------
SELECT TOP (100)
    geolocation_zip_code_prefix,
    COUNT(*) AS SourceRows,
    COUNT(DISTINCT geolocation_state) AS DistinctStates,
    MIN(geolocation_state) AS MinState,
    MAX(geolocation_state) AS MaxState
FROM stg.geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_state) > 1
ORDER BY
    DistinctStates DESC,
    SourceRows DESC,
    geolocation_zip_code_prefix;

-- Diagnostic


------------------------------------------------------------
-- 18. ZIP Prefixes Mapping to Multiple City Labels
------------------------------------------------------------
SELECT
    COUNT(*) AS ZipPrefixesWithMultipleCities
FROM
(
    SELECT
        geolocation_zip_code_prefix
    FROM stg.geolocation
    GROUP BY geolocation_zip_code_prefix
    HAVING COUNT(DISTINCT geolocation_city) > 1
) x;

-- Informational.
-- City spelling/accent variations may exist in the source.


------------------------------------------------------------
-- 19. Rows per ZIP Distribution Summary
------------------------------------------------------------
WITH ZipCounts AS
(
    SELECT
        geolocation_zip_code_prefix,
        COUNT(*) AS RowsPerZip
    FROM stg.geolocation
    GROUP BY geolocation_zip_code_prefix
)
SELECT
    MIN(RowsPerZip) AS MinRowsPerZip,
    MAX(RowsPerZip) AS MaxRowsPerZip,
    CAST(
        AVG(CAST(RowsPerZip AS DECIMAL(18,2)))
        AS DECIMAL(18,2)
    ) AS AvgRowsPerZip
FROM ZipCounts;

-- Informational


------------------------------------------------------------
-- 20. Highest-Volume ZIP Prefixes
------------------------------------------------------------
SELECT TOP (20)
    geolocation_zip_code_prefix,
    COUNT(*) AS SourceRows,
    COUNT(DISTINCT geolocation_city) AS DistinctCities,
    COUNT(DISTINCT geolocation_state) AS DistinctStates,
    MIN(geolocation_lat) AS MinLatitude,
    MAX(geolocation_lat) AS MaxLatitude,
    MIN(geolocation_lng) AS MinLongitude,
    MAX(geolocation_lng) AS MaxLongitude
FROM stg.geolocation
GROUP BY geolocation_zip_code_prefix
ORDER BY
    SourceRows DESC,
    geolocation_zip_code_prefix;

-- Diagnostic / informational


------------------------------------------------------------
-- Known Source Grain Characteristics
--
-- Total rows                = 1,000,163
-- Distinct ZIP prefixes     = 19,015
-- ZIPs with multiple rows   = 17,972
-- Exact duplicate rows      = 261,831
-- Maximum rows for one ZIP  = 1,146
-- Distinct states           = 27
--
-- Exact duplicate rows and repeated ZIP prefixes are preserved
-- in staging because they are characteristics of the source.
--
-- ZIP prefix must NOT be used as a unique staging key.
--
-- Before building DimGeography, the source must be transformed
-- to a controlled analytical grain of one row per ZIP prefix.
------------------------------------------------------------

------------------------------------------------------------
-- Known Geography Resolution Findings
--
-- Source characteristics:
--
-- Total source rows                     = 1,000,163
-- Distinct ZIP prefixes                 = 19,015
-- Exact duplicate rows                  = 261,831
-- ZIP prefixes with multiple states     = 8
-- ZIP prefixes with multiple city labels = 8,555
--
-- Multi-state ZIP review:
-- All 8 ZIP prefixes have one strongly dominant state.
-- Customer/Seller data independently confirms the dominant
-- state for all 8 reviewed ZIP prefixes.
--
-- City resolution review:
--
-- Raw dominant-city ties                = 174 ZIP prefixes
-- After accent normalization            = 35 ZIP prefixes
-- After full text normalization         = 32 ZIP prefixes
--
-- Full text normalization considered:
-- - case-insensitive comparison
-- - accent-insensitive comparison
-- - spaces
-- - hyphens
-- - apostrophes
--
-- Customer/Seller cross-check resolved:
-- 12 of the 32 remaining tied ZIP prefixes
--
-- Remaining unresolved ZIP prefixes:
-- 20
--
-- Planned DWH Geography Rules:
--
-- State:
--   Use the dominant source state per ZIP prefix.
--   Preserve a StateConflictFlag where multiple states exist.
--
-- City:
--   Use the unique dominant normalized city where available.
--
--   When dominant city counts are tied:
--     1. Cross-check Customers/Sellers.
--     2. If still unresolved, do NOT select an arbitrary city.
--     3. Use NULL/Unknown as the representative city.
--     4. Set CityAmbiguousFlag = 1.
--
-- Staging values remain unchanged.
-- No source row, city, state, coordinate, or duplicate row
-- is corrected or removed in stg.geolocation.
------------------------------------------------------------