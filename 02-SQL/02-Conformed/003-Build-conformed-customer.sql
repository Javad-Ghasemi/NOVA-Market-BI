USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   Conformed Customer

   Grain:
   1 row = 1 customer_unique_id

   Representative geography:
   Geography from the latest purchase.

   Tie handling:
   If multiple rows share the same latest purchase timestamp,
   order_id is used only as a deterministic technical
   tie-breaker.

   Previous DQ confirmed that latest-timestamp ties do not
   contain conflicting ZIP / City / State values.
   ========================================================= */


IF OBJECT_ID(N'conformed.Customer', N'U') IS NOT NULL
    DROP TABLE conformed.Customer;
GO


CREATE TABLE conformed.Customer
(
    CustomerUniqueID            VARCHAR(50)     NOT NULL,

    RepresentativeCustomerID    VARCHAR(50)     NOT NULL,

    ZipCodePrefix               VARCHAR(5)      NOT NULL,
    CityName                    NVARCHAR(100)   NOT NULL,
    StateCode                   CHAR(2)         NOT NULL,

    FirstPurchaseTimestamp      DATETIME2       NOT NULL,
    LatestPurchaseTimestamp     DATETIME2       NOT NULL,

    OrderCount                  INT             NOT NULL,
    CustomerIDCount             INT             NOT NULL,

    DistinctZIPCount            INT             NOT NULL,
    DistinctCityCount           INT             NOT NULL,
    DistinctStateCount          INT             NOT NULL,

    LatestTimestampTieFlag      BIT             NOT NULL,

    CONSTRAINT PK_ConformedCustomer
        PRIMARY KEY (CustomerUniqueID)
);
GO


/* =========================================================
   Customer + Order source
   ========================================================= */

WITH CustomerOrders AS
(
    SELECT
        c.customer_unique_id,
        c.customer_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,

        o.order_id,
        o.order_purchase_timestamp

    FROM stg.customers c

    INNER JOIN stg.orders o
        ON c.customer_id = o.customer_id
),
CustomerSummary AS
(
    SELECT
        customer_unique_id,

        MIN(order_purchase_timestamp)
            AS FirstPurchaseTimestamp,

        MAX(order_purchase_timestamp)
            AS LatestPurchaseTimestamp,

        COUNT(DISTINCT order_id)
            AS OrderCount,

        COUNT(DISTINCT customer_id)
            AS CustomerIDCount,

        COUNT(DISTINCT customer_zip_code_prefix)
            AS DistinctZIPCount,

        COUNT(DISTINCT customer_city)
            AS DistinctCityCount,

        COUNT(DISTINCT customer_state)
            AS DistinctStateCount

    FROM CustomerOrders

    GROUP BY
        customer_unique_id
),
LatestTimestampCounts AS
(
    SELECT
        co.customer_unique_id,
        COUNT(*) AS LatestTimestampRows

    FROM CustomerOrders co

    INNER JOIN CustomerSummary cs
        ON  co.customer_unique_id = cs.customer_unique_id
        AND co.order_purchase_timestamp = cs.LatestPurchaseTimestamp

    GROUP BY
        co.customer_unique_id
),
RankedLatest AS
(
    SELECT
        co.customer_unique_id,
        co.customer_id,
        co.customer_zip_code_prefix,
        co.customer_city,
        co.customer_state,
        co.order_id,
        co.order_purchase_timestamp,

        ROW_NUMBER() OVER
        (
            PARTITION BY co.customer_unique_id
            ORDER BY
                co.order_purchase_timestamp DESC,
                co.order_id DESC,
                co.customer_id DESC
        ) AS RepresentativeRank

    FROM CustomerOrders co
)
INSERT INTO conformed.Customer
(
    CustomerUniqueID,
    RepresentativeCustomerID,

    ZipCodePrefix,
    CityName,
    StateCode,

    FirstPurchaseTimestamp,
    LatestPurchaseTimestamp,

    OrderCount,
    CustomerIDCount,

    DistinctZIPCount,
    DistinctCityCount,
    DistinctStateCount,

    LatestTimestampTieFlag
)
SELECT
    cs.customer_unique_id,

    rl.customer_id,

    rl.customer_zip_code_prefix,
    rl.customer_city,
    rl.customer_state,

    cs.FirstPurchaseTimestamp,
    cs.LatestPurchaseTimestamp,

    cs.OrderCount,
    cs.CustomerIDCount,

    cs.DistinctZIPCount,
    cs.DistinctCityCount,
    cs.DistinctStateCount,

    CASE
        WHEN ltc.LatestTimestampRows > 1
        THEN 1
        ELSE 0
    END

FROM CustomerSummary cs

INNER JOIN RankedLatest rl
    ON  cs.customer_unique_id = rl.customer_unique_id
    AND rl.RepresentativeRank = 1

INNER JOIN LatestTimestampCounts ltc
    ON cs.customer_unique_id = ltc.customer_unique_id;
GO


/* =========================================================
   Validation 1:
   Core counts
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount],
    COUNT(DISTINCT CustomerUniqueID) AS DistinctCustomers,

    SUM(
        CASE
            WHEN CustomerIDCount > 1
            THEN 1
            ELSE 0
        END
    ) AS ReturningCustomers,

    SUM(
        CASE
            WHEN DistinctZIPCount > 1
            THEN 1
            ELSE 0
        END
    ) AS CustomersWithMultipleZIPs,

    SUM(
        CASE
            WHEN DistinctStateCount > 1
            THEN 1
            ELSE 0
        END
    ) AS CustomersWithMultipleStates,

    SUM(
        CASE
            WHEN DistinctCityCount > 1
            THEN 1
            ELSE 0
        END
    ) AS CustomersWithMultipleCities,

    SUM(
        CASE
            WHEN LatestTimestampTieFlag = 1
            THEN 1
            ELSE 0
        END
    ) AS LatestTimestampTies

FROM conformed.Customer;
GO


/* =========================================================
   Validation 2:
   Geography coverage

   Every representative ZIP must exist in
   conformed.Geography.
   ========================================================= */

SELECT
    COUNT(*) AS CustomerZIPsMissingFromConformedGeography
FROM conformed.Customer c
LEFT JOIN conformed.Geography g
    ON c.ZipCodePrefix = g.ZipCodePrefix
WHERE g.ZipCodePrefix IS NULL;
GO


/* =========================================================
   Validation 3:
   Null business attributes
   ========================================================= */

SELECT
    SUM(
        CASE
            WHEN CustomerUniqueID IS NULL
            THEN 1
            ELSE 0
        END
    ) AS NullCustomerUniqueIDs,

    SUM(
        CASE
            WHEN RepresentativeCustomerID IS NULL
            THEN 1
            ELSE 0
        END
    ) AS NullRepresentativeCustomerIDs,

    SUM(
        CASE
            WHEN ZipCodePrefix IS NULL
            THEN 1
            ELSE 0
        END
    ) AS NullZIPs,

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
    ) AS NullCities

FROM conformed.Customer;
GO