USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   DimCustomer Data Quality Validation

   Source:
   conformed.Customer

   Geography lookup:
   dwh.DimGeography

   Target:
   dwh.DimCustomer

   Grain:
   1 row = 1 customer_unique_id

   Expected:
   96,096 business customers
   + 1 Unknown member
   ========================================================= */


/* =========================================================
   1. Row Count / Key Range
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount],

    SUM(
        CASE
            WHEN CustomerKey <> 0
            THEN 1
            ELSE 0
        END
    ) AS BusinessRows,

    COUNT(
        DISTINCT
        CASE
            WHEN CustomerKey <> 0
            THEN CustomerUniqueID
        END
    ) AS DistinctBusinessCustomers,

    SUM(
        CASE
            WHEN CustomerKey = 0
            THEN 1
            ELSE 0
        END
    ) AS UnknownMembers,

    MIN(CustomerKey) AS MinCustomerKey,
    MAX(CustomerKey) AS MaxCustomerKey

FROM dwh.DimCustomer;
GO


/* =========================================================
   2. Unknown Member
   ========================================================= */

SELECT
    CustomerKey,
    CustomerUniqueID,
    RepresentativeCustomerID,
    RepresentativeGeographyKey
FROM dwh.DimCustomer
WHERE CustomerKey = 0;
GO


/* =========================================================
   3. Business Key Uniqueness
   ========================================================= */

SELECT
    CustomerUniqueID,
    COUNT(*) AS DuplicateRows
FROM dwh.DimCustomer
WHERE CustomerKey <> 0
GROUP BY CustomerUniqueID
HAVING COUNT(*) > 1;
GO


/* =========================================================
   4. Geography Key Validation
   ========================================================= */

SELECT
    COUNT(*) AS InvalidBusinessGeographyKeys
FROM dwh.DimCustomer c
LEFT JOIN dwh.DimGeography g
    ON c.RepresentativeGeographyKey = g.GeographyKey
WHERE c.CustomerKey <> 0
  AND
  (
       c.RepresentativeGeographyKey = 0
       OR g.GeographyKey IS NULL
  );
GO


/* =========================================================
   5. Customer Characteristics
   ========================================================= */

SELECT
    SUM(
        CASE
            WHEN CustomerKey <> 0
             AND ReturningCustomerFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS ReturningCustomers,

    SUM(
        CASE
            WHEN CustomerKey <> 0
             AND MultipleZIPFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS CustomersWithMultipleZIPs,

    SUM(
        CASE
            WHEN CustomerKey <> 0
             AND MultipleStateFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS CustomersWithMultipleStates,

    SUM(
        CASE
            WHEN CustomerKey <> 0
             AND MultipleCityFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS CustomersWithMultipleCities,

    SUM(
        CASE
            WHEN CustomerKey <> 0
             AND LatestTimestampTieFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS LatestTimestampTies

FROM dwh.DimCustomer;
GO


/* =========================================================
   6. Source -> Target Exact Comparison

   RepresentativeGeographyKey is resolved from
   DimGeography using the customer's representative ZIP.
   ========================================================= */

WITH SourceData AS
(
    SELECT
        c.CustomerUniqueID,
        c.RepresentativeCustomerID,

        g.GeographyKey
            AS RepresentativeGeographyKey,

        c.FirstPurchaseTimestamp,
        c.LatestPurchaseTimestamp,

        c.OrderCount,
        c.CustomerIDCount,

        CASE
            WHEN c.CustomerIDCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS ReturningCustomerFlag,

        CASE
            WHEN c.DistinctZIPCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleZIPFlag,

        CASE
            WHEN c.DistinctCityCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleCityFlag,

        CASE
            WHEN c.DistinctStateCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleStateFlag,

        c.LatestTimestampTieFlag

    FROM conformed.Customer c

    INNER JOIN dwh.DimGeography g
        ON c.ZipCodePrefix = g.ZipCodePrefix
)
SELECT
    COUNT(*) AS SourceRowsMissingOrDifferentInDWH
FROM
(
    SELECT *
    FROM SourceData

    EXCEPT

    SELECT
        CustomerUniqueID,
        RepresentativeCustomerID,
        RepresentativeGeographyKey,

        FirstPurchaseTimestamp,
        LatestPurchaseTimestamp,

        OrderCount,
        CustomerIDCount,

        ReturningCustomerFlag,
        MultipleZIPFlag,
        MultipleCityFlag,
        MultipleStateFlag,
        LatestTimestampTieFlag

    FROM dwh.DimCustomer
    WHERE CustomerKey <> 0
) x;
GO


/* =========================================================
   7. Target -> Source Exact Comparison
   ========================================================= */

WITH SourceData AS
(
    SELECT
        c.CustomerUniqueID,
        c.RepresentativeCustomerID,

        g.GeographyKey
            AS RepresentativeGeographyKey,

        c.FirstPurchaseTimestamp,
        c.LatestPurchaseTimestamp,

        c.OrderCount,
        c.CustomerIDCount,

        CASE
            WHEN c.CustomerIDCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS ReturningCustomerFlag,

        CASE
            WHEN c.DistinctZIPCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleZIPFlag,

        CASE
            WHEN c.DistinctCityCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleCityFlag,

        CASE
            WHEN c.DistinctStateCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleStateFlag,

        c.LatestTimestampTieFlag

    FROM conformed.Customer c

    INNER JOIN dwh.DimGeography g
        ON c.ZipCodePrefix = g.ZipCodePrefix
)
SELECT
    COUNT(*) AS DWHRowsMissingOrDifferentInSource
FROM
(
    SELECT
        CustomerUniqueID,
        RepresentativeCustomerID,
        RepresentativeGeographyKey,

        FirstPurchaseTimestamp,
        LatestPurchaseTimestamp,

        OrderCount,
        CustomerIDCount,

        ReturningCustomerFlag,
        MultipleZIPFlag,
        MultipleCityFlag,
        MultipleStateFlag,
        LatestTimestampTieFlag

    FROM dwh.DimCustomer
    WHERE CustomerKey <> 0

    EXCEPT

    SELECT *
    FROM SourceData
) x;
GO


/* =========================================================
   8. Overall Validation
   ========================================================= */

WITH SourceData AS
(
    SELECT
        c.CustomerUniqueID,
        c.RepresentativeCustomerID,
        g.GeographyKey AS RepresentativeGeographyKey,

        c.FirstPurchaseTimestamp,
        c.LatestPurchaseTimestamp,

        c.OrderCount,
        c.CustomerIDCount,

        CASE
            WHEN c.CustomerIDCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS ReturningCustomerFlag,

        CASE
            WHEN c.DistinctZIPCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleZIPFlag,

        CASE
            WHEN c.DistinctCityCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleCityFlag,

        CASE
            WHEN c.DistinctStateCount > 1
            THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS MultipleStateFlag,

        c.LatestTimestampTieFlag

    FROM conformed.Customer c

    INNER JOIN dwh.DimGeography g
        ON c.ZipCodePrefix = g.ZipCodePrefix
),
SourceMissing AS
(
    SELECT *
    FROM SourceData

    EXCEPT

    SELECT
        CustomerUniqueID,
        RepresentativeCustomerID,
        RepresentativeGeographyKey,

        FirstPurchaseTimestamp,
        LatestPurchaseTimestamp,

        OrderCount,
        CustomerIDCount,

        ReturningCustomerFlag,
        MultipleZIPFlag,
        MultipleCityFlag,
        MultipleStateFlag,
        LatestTimestampTieFlag

    FROM dwh.DimCustomer
    WHERE CustomerKey <> 0
),
TargetMissing AS
(
    SELECT
        CustomerUniqueID,
        RepresentativeCustomerID,
        RepresentativeGeographyKey,

        FirstPurchaseTimestamp,
        LatestPurchaseTimestamp,

        OrderCount,
        CustomerIDCount,

        ReturningCustomerFlag,
        MultipleZIPFlag,
        MultipleCityFlag,
        MultipleStateFlag,
        LatestTimestampTieFlag

    FROM dwh.DimCustomer
    WHERE CustomerKey <> 0

    EXCEPT

    SELECT *
    FROM SourceData
)
SELECT
    CASE
        WHEN
            (SELECT COUNT(*)
             FROM dwh.DimCustomer) = 96097

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey = 0) = 1

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0) = 96096

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0
               AND ReturningCustomerFlag = 1) = 2997

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0
               AND MultipleZIPFlag = 1) = 250

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0
               AND MultipleStateFlag = 1) = 39

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0
               AND MultipleCityFlag = 1) = 122

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0
               AND LatestTimestampTieFlag = 1) = 269

        AND
            (SELECT COUNT(*)
             FROM dwh.DimCustomer
             WHERE CustomerKey <> 0
               AND RepresentativeGeographyKey = 0) = 0

        AND
            (SELECT COUNT(*)
             FROM SourceMissing) = 0

        AND
            (SELECT COUNT(*)
             FROM TargetMissing) = 0

        THEN 'DIM CUSTOMER VALIDATION PASSED'

        ELSE 'DIM CUSTOMER VALIDATION FAILED'
    END AS DimCustomerValidationStatus;
GO