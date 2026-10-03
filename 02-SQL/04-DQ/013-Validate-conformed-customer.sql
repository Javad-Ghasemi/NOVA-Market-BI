USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   Conformed Customer Data Quality Validation

   Grain:
   1 row = 1 customer_unique_id

   Representative geography:
   Geography associated with the latest purchase.

   Tie rule:
   order_id is used only as a deterministic technical
   tie-breaker when latest purchase timestamps are equal.
   ========================================================= */


/* =========================================================
   1. Row Count / Business Key Uniqueness
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount],
    COUNT(DISTINCT CustomerUniqueID) AS DistinctCustomers
FROM conformed.Customer;
GO


SELECT
    CustomerUniqueID,
    COUNT(*) AS DuplicateRows
FROM conformed.Customer
GROUP BY CustomerUniqueID
HAVING COUNT(*) > 1;
GO


/* =========================================================
   2. Null Business Attributes
   ========================================================= */

SELECT
    SUM(
        CASE
            WHEN CustomerUniqueID IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullCustomerUniqueIDs,

    SUM(
        CASE
            WHEN RepresentativeCustomerID IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullRepresentativeCustomerIDs,

    SUM(
        CASE
            WHEN ZipCodePrefix IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullZIPs,

    SUM(
        CASE
            WHEN CityName IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullCities,

    SUM(
        CASE
            WHEN StateCode IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullStates,

    SUM(
        CASE
            WHEN FirstPurchaseTimestamp IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullFirstPurchaseTimestamps,

    SUM(
        CASE
            WHEN LatestPurchaseTimestamp IS NULL
            THEN 1 ELSE 0
        END
    ) AS NullLatestPurchaseTimestamps

FROM conformed.Customer;
GO


/* =========================================================
   3. Customer Characteristics
   ========================================================= */

SELECT
    SUM(
        CASE
            WHEN CustomerIDCount > 1
            THEN 1 ELSE 0
        END
    ) AS ReturningCustomers,

    SUM(
        CASE
            WHEN DistinctZIPCount > 1
            THEN 1 ELSE 0
        END
    ) AS CustomersWithMultipleZIPs,

    SUM(
        CASE
            WHEN DistinctStateCount > 1
            THEN 1 ELSE 0
        END
    ) AS CustomersWithMultipleStates,

    SUM(
        CASE
            WHEN DistinctCityCount > 1
            THEN 1 ELSE 0
        END
    ) AS CustomersWithMultipleCities,

    SUM(
        CASE
            WHEN LatestTimestampTieFlag = 1
            THEN 1 ELSE 0
        END
    ) AS LatestTimestampTies

FROM conformed.Customer;
GO


/* =========================================================
   4. Geography Coverage
   ========================================================= */

SELECT
    COUNT(*) AS CustomerZIPsMissingFromConformedGeography
FROM conformed.Customer c
LEFT JOIN conformed.Geography g
    ON c.ZipCodePrefix = g.ZipCodePrefix
WHERE g.ZipCodePrefix IS NULL;
GO


/* =========================================================
   5. Date Consistency
   ========================================================= */

SELECT
    COUNT(*) AS InvalidPurchaseDateRanges
FROM conformed.Customer
WHERE FirstPurchaseTimestamp > LatestPurchaseTimestamp;
GO


/* =========================================================
   6. Count Consistency
   ========================================================= */

SELECT
    COUNT(*) AS InvalidCustomerCounts
FROM conformed.Customer
WHERE
       OrderCount <= 0
    OR CustomerIDCount <= 0
    OR DistinctZIPCount <= 0
    OR DistinctCityCount <= 0
    OR DistinctStateCount <= 0;
GO


/* =========================================================
   7. Representative Customer belongs to the same
      customer_unique_id
   ========================================================= */

SELECT
    COUNT(*) AS InvalidRepresentativeCustomerIDs
FROM conformed.Customer cc
LEFT JOIN stg.customers sc
    ON cc.RepresentativeCustomerID = sc.customer_id
WHERE
       sc.customer_id IS NULL
    OR sc.customer_unique_id <> cc.CustomerUniqueID;
GO


/* =========================================================
   8. Representative Geography matches its source
      customer row
   ========================================================= */

SELECT
    COUNT(*) AS RepresentativeGeographyMismatches
FROM conformed.Customer cc
INNER JOIN stg.customers sc
    ON cc.RepresentativeCustomerID = sc.customer_id
WHERE
       cc.ZipCodePrefix <> sc.customer_zip_code_prefix
    OR cc.CityName <> sc.customer_city
    OR cc.StateCode <> sc.customer_state;
GO


/* =========================================================
   9. Representative Customer is from the latest
      purchase timestamp
   ========================================================= */

SELECT
    COUNT(*) AS RepresentativeCustomersNotLatest
FROM conformed.Customer cc
INNER JOIN stg.orders o
    ON cc.RepresentativeCustomerID = o.customer_id
WHERE o.order_purchase_timestamp <> cc.LatestPurchaseTimestamp;
GO


/* =========================================================
   10. Latest Timestamp Tie Geography Consistency

   Expected:
   269 customers have latest-timestamp ties,
   but none of those ties conflict on geography.
   ========================================================= */

WITH CustomerOrders AS
(
    SELECT
        c.customer_unique_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,
        o.order_purchase_timestamp,

        MAX(o.order_purchase_timestamp) OVER
        (
            PARTITION BY c.customer_unique_id
        ) AS LatestPurchaseTimestamp

    FROM stg.customers c

    INNER JOIN stg.orders o
        ON c.customer_id = o.customer_id
),
LatestRows AS
(
    SELECT
        *
    FROM CustomerOrders
    WHERE order_purchase_timestamp = LatestPurchaseTimestamp
)
SELECT
    COUNT(*) AS LatestTieGeographyConflicts
FROM
(
    SELECT
        customer_unique_id
    FROM LatestRows
    GROUP BY customer_unique_id
    HAVING
           COUNT(*) > 1
       AND
       (
            COUNT(DISTINCT customer_zip_code_prefix) > 1
         OR COUNT(DISTINCT customer_city) > 1
         OR COUNT(DISTINCT customer_state) > 1
       )
) x;
GO


/* =========================================================
   11. Overall Validation
   ========================================================= */

SELECT
    CASE
        WHEN
            (SELECT COUNT(*)
             FROM conformed.Customer) = 96096

        AND
            (SELECT COUNT(DISTINCT CustomerUniqueID)
             FROM conformed.Customer) = 96096

        AND
            (SELECT COUNT(*)
             FROM conformed.Customer
             WHERE CustomerIDCount > 1) = 2997

        AND
            (SELECT COUNT(*)
             FROM conformed.Customer
             WHERE DistinctZIPCount > 1) = 250

        AND
            (SELECT COUNT(*)
             FROM conformed.Customer
             WHERE DistinctStateCount > 1) = 39

        AND
            (SELECT COUNT(*)
             FROM conformed.Customer
             WHERE DistinctCityCount > 1) = 122

        AND
            (SELECT COUNT(*)
             FROM conformed.Customer
             WHERE LatestTimestampTieFlag = 1) = 269

        AND
            (
                SELECT COUNT(*)
                FROM conformed.Customer c
                LEFT JOIN conformed.Geography g
                    ON c.ZipCodePrefix = g.ZipCodePrefix
                WHERE g.ZipCodePrefix IS NULL
            ) = 0

        AND
            (SELECT COUNT(*)
             FROM conformed.Customer
             WHERE FirstPurchaseTimestamp >
                   LatestPurchaseTimestamp) = 0

        THEN 'CONFORMED CUSTOMER VALIDATION PASSED'

        ELSE 'CONFORMED CUSTOMER VALIDATION FAILED'
    END AS CustomerValidationStatus;
GO