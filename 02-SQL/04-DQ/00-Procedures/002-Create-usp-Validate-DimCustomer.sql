USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateDimCustomer

   Purpose:
   - Single source of truth for DimCustomer DQ
   - Usable from SSMS and SSIS Master
   - Throws on validation failure
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateDimCustomer
AS
BEGIN
    SET NOCOUNT ON;

    /* =====================================================
       Expected source representation

       RepresentativeGeographyKey is resolved from
       DimGeography using the representative ZIP.
       ===================================================== */

    DROP TABLE IF EXISTS #ExpectedCustomer;

    SELECT
        c.CustomerUniqueID,
        c.RepresentativeCustomerID,

        g.GeographyKey
            AS RepresentativeGeographyKey,

        c.FirstPurchaseTimestamp,
        c.LatestPurchaseTimestamp,

        c.OrderCount,
        c.CustomerIDCount,

        CAST(
            CASE
                WHEN c.CustomerIDCount > 1
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS ReturningCustomerFlag,

        CAST(
            CASE
                WHEN c.DistinctZIPCount > 1
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS MultipleZIPFlag,

        CAST(
            CASE
                WHEN c.DistinctCityCount > 1
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS MultipleCityFlag,

        CAST(
            CASE
                WHEN c.DistinctStateCount > 1
                THEN 1
                ELSE 0
            END
            AS bit
        ) AS MultipleStateFlag,

        c.LatestTimestampTieFlag

    INTO #ExpectedCustomer

    FROM conformed.Customer AS c

    INNER JOIN dwh.DimGeography AS g
        ON c.ZipCodePrefix = g.ZipCodePrefix
       AND g.GeographyKey <> 0;


    /* =====================================================
       Validation metrics
       ===================================================== */

    DECLARE
        @ConformedBusinessRows            bigint,
        @ExpectedResolvedRows             bigint,

        @ActualTotalRows                  bigint,
        @ActualBusinessRows               bigint,
        @DistinctBusinessCustomers        bigint,
        @UnknownRows                      bigint,

        @DuplicateBusinessKeyGroups       bigint,
        @InvalidBusinessGeographyKeys     bigint,

        @ReturningCustomers               bigint,
        @CustomersWithMultipleZIPs        bigint,
        @CustomersWithMultipleStates      bigint,
        @CustomersWithMultipleCities      bigint,
        @LatestTimestampTies              bigint,

        @SourceToTargetDifferences        bigint,
        @TargetToSourceDifferences        bigint;


    /* =====================================================
       Source counts
       ===================================================== */

    SELECT
        @ConformedBusinessRows = COUNT_BIG(*)
    FROM conformed.Customer;


    SELECT
        @ExpectedResolvedRows = COUNT_BIG(*)
    FROM #ExpectedCustomer;


    /* =====================================================
       Target row-count / characteristics
       ===================================================== */

    SELECT
        @ActualTotalRows =
            COUNT_BIG(*),

        @ActualBusinessRows =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey <> 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @UnknownRows =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey = 0
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @ReturningCustomers =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey <> 0
                         AND ReturningCustomerFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @CustomersWithMultipleZIPs =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey <> 0
                         AND MultipleZIPFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @CustomersWithMultipleStates =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey <> 0
                         AND MultipleStateFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @CustomersWithMultipleCities =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey <> 0
                         AND MultipleCityFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            ),

        @LatestTimestampTies =
            COALESCE(
                SUM(
                    CASE
                        WHEN CustomerKey <> 0
                         AND LatestTimestampTieFlag = 1
                        THEN CAST(1 AS bigint)
                        ELSE CAST(0 AS bigint)
                    END
                ),
                0
            )

    FROM dwh.DimCustomer;


    SELECT
        @DistinctBusinessCustomers =
            COUNT_BIG(DISTINCT CustomerUniqueID)
    FROM dwh.DimCustomer
    WHERE CustomerKey <> 0;


    /* =====================================================
       Business-key uniqueness
       ===================================================== */

    SELECT
        @DuplicateBusinessKeyGroups = COUNT_BIG(*)
    FROM
    (
        SELECT CustomerUniqueID
        FROM dwh.DimCustomer
        WHERE CustomerKey <> 0
        GROUP BY CustomerUniqueID
        HAVING COUNT_BIG(*) > 1
    ) AS d;


    /* =====================================================
       Geography-key integrity

       Business customers must resolve to a real
       DimGeography business member.
       ===================================================== */

    SELECT
        @InvalidBusinessGeographyKeys = COUNT_BIG(*)

    FROM dwh.DimCustomer AS c

    LEFT JOIN dwh.DimGeography AS g
        ON c.RepresentativeGeographyKey = g.GeographyKey

    WHERE c.CustomerKey <> 0
      AND
      (
           c.RepresentativeGeographyKey = 0
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

        FROM #ExpectedCustomer

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
    ) AS x;


    /* =====================================================
       Target -> Source exact comparison
       ===================================================== */

    SELECT
        @TargetToSourceDifferences = COUNT_BIG(*)

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

        FROM #ExpectedCustomer
    ) AS x;


    /* =====================================================
       Diagnostic summary
       ===================================================== */

    SELECT
        @ConformedBusinessRows          AS ConformedBusinessRows,
        @ExpectedResolvedRows           AS ExpectedResolvedRows,

        @ActualTotalRows                AS ActualTotalRows,
        @ActualBusinessRows             AS ActualBusinessRows,
        @DistinctBusinessCustomers      AS DistinctBusinessCustomers,
        @UnknownRows                    AS UnknownRows,

        @DuplicateBusinessKeyGroups     AS DuplicateBusinessKeyGroups,
        @InvalidBusinessGeographyKeys   AS InvalidBusinessGeographyKeys,

        @ReturningCustomers             AS ReturningCustomers,
        @CustomersWithMultipleZIPs      AS CustomersWithMultipleZIPs,
        @CustomersWithMultipleStates    AS CustomersWithMultipleStates,
        @CustomersWithMultipleCities    AS CustomersWithMultipleCities,
        @LatestTimestampTies            AS LatestTimestampTies,

        @SourceToTargetDifferences      AS SourceToTargetDifferences,
        @TargetToSourceDifferences      AS TargetToSourceDifferences;


    /* =====================================================
       Hard validation rules
       ===================================================== */

    IF @ConformedBusinessRows <> 96096
    BEGIN
        THROW 51140,
            'DimCustomer validation failed: conformed Customer baseline row count changed.',
            1;
    END;


    IF @ExpectedResolvedRows <> @ConformedBusinessRows
    BEGIN
        THROW 51141,
            'DimCustomer validation failed: one or more conformed customers could not resolve to DimGeography.',
            1;
    END;


    IF @ActualBusinessRows <> @ConformedBusinessRows
       OR @ActualTotalRows <> @ConformedBusinessRows + 1
    BEGIN
        THROW 51142,
            'DimCustomer validation failed: row count mismatch.',
            1;
    END;


    IF @UnknownRows <> 1
    BEGIN
        THROW 51143,
            'DimCustomer validation failed: expected exactly one Unknown member.',
            1;
    END;


    IF @DistinctBusinessCustomers <> @ConformedBusinessRows
       OR @DuplicateBusinessKeyGroups <> 0
    BEGIN
        THROW 51144,
            'DimCustomer validation failed: duplicate or invalid customer business-key grain.',
            1;
    END;


    IF @InvalidBusinessGeographyKeys <> 0
    BEGIN
        THROW 51145,
            'DimCustomer validation failed: invalid RepresentativeGeographyKey detected.',
            1;
    END;


    IF @SourceToTargetDifferences <> 0
    BEGIN
        THROW 51146,
            'DimCustomer validation failed: source-to-target differences detected.',
            1;
    END;


    IF @TargetToSourceDifferences <> 0
    BEGIN
        THROW 51147,
            'DimCustomer validation failed: target-to-source differences detected.',
            1;
    END;


    /* =====================================================
       Expected source anomaly / behavior profile

       These values document the validated current Olist
       customer characteristics.
       ===================================================== */

    IF @ReturningCustomers <> 2997
    BEGIN
        THROW 51148,
            'DimCustomer validation failed: unexpected returning-customer count.',
            1;
    END;


    IF @CustomersWithMultipleZIPs <> 250
    BEGIN
        THROW 51149,
            'DimCustomer validation failed: unexpected multiple-ZIP customer count.',
            1;
    END;


    IF @CustomersWithMultipleStates <> 39
    BEGIN
        THROW 51150,
            'DimCustomer validation failed: unexpected multiple-state customer count.',
            1;
    END;


    IF @CustomersWithMultipleCities <> 122
    BEGIN
        THROW 51151,
            'DimCustomer validation failed: unexpected multiple-city customer count.',
            1;
    END;


    IF @LatestTimestampTies <> 269
    BEGIN
        THROW 51152,
            'DimCustomer validation failed: unexpected latest-timestamp tie count.',
            1;
    END;


    PRINT 'DIM CUSTOMER VALIDATION PASSED.';
END;
GO