USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   Dimension: dwh.DimCustomer

   Grain:
   1 row = 1 customer_unique_id

   Business Key:
   CustomerUniqueID

   Surrogate Key:
   CustomerKey

   Important:
   Geography used for historical order analysis is stored
   on FactOrder as CustomerGeographyKey.

   Representative geography from conformed.Customer is a
   customer-profile attribute only.
   ========================================================= */


IF OBJECT_ID(N'dwh.DimCustomer', N'U') IS NOT NULL
    DROP TABLE dwh.DimCustomer;
GO


CREATE TABLE dwh.DimCustomer
(
    CustomerKey                     INT IDENTITY(1,1) NOT NULL,

    CustomerUniqueID                VARCHAR(50)       NULL,
    RepresentativeCustomerID        VARCHAR(50)       NULL,

    RepresentativeGeographyKey      INT               NOT NULL,

    FirstPurchaseTimestamp          DATETIME2         NULL,
    LatestPurchaseTimestamp         DATETIME2         NULL,

    OrderCount                      INT               NOT NULL,
    CustomerIDCount                 INT               NOT NULL,

    ReturningCustomerFlag           BIT               NOT NULL,
    MultipleZIPFlag                 BIT               NOT NULL,
    MultipleCityFlag                BIT               NOT NULL,
    MultipleStateFlag               BIT               NOT NULL,
    LatestTimestampTieFlag          BIT               NOT NULL,

    CONSTRAINT PK_DimCustomer
        PRIMARY KEY (CustomerKey),

    CONSTRAINT FK_DimCustomer_RepresentativeGeography
        FOREIGN KEY (RepresentativeGeographyKey)
        REFERENCES dwh.DimGeography(GeographyKey)
);
GO


CREATE UNIQUE INDEX UX_DimCustomer_CustomerUniqueID
    ON dwh.DimCustomer(CustomerUniqueID)
    WHERE CustomerUniqueID IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_DimCustomer_RepresentativeGeographyKey
ON dwh.DimCustomer (RepresentativeGeographyKey);
GO


/* =========================================================
   Validation

   Population is performed by SSIS.
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount]
FROM dwh.DimCustomer;
GO