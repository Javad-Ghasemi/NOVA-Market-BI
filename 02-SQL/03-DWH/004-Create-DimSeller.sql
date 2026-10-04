USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   Dimension: dwh.DimSeller

   Grain:
   1 row = 1 seller_id

   Business Key:
   SellerID

   Surrogate Key:
   SellerKey

   Geography:
   Resolved through DimGeography using seller ZIP prefix.

   Source City / State values are preserved for lineage.
   Canonical reporting geography comes from DimGeography.
   ========================================================= */


IF OBJECT_ID(N'dwh.DimSeller', N'U') IS NOT NULL
    DROP TABLE dwh.DimSeller;
GO


CREATE TABLE dwh.DimSeller
(
    SellerKey                  INT IDENTITY(1,1) NOT NULL,

    SellerID                   VARCHAR(50)       NULL,

    GeographyKey               INT               NOT NULL,

    SourceZipCodePrefix        VARCHAR(5)        NULL,
    SourceCityName             NVARCHAR(100)     NULL,
    SourceStateCode            CHAR(2)           NULL,

    CityMismatchFlag           BIT               NOT NULL,
    StateMismatchFlag          BIT               NOT NULL,

    CONSTRAINT PK_DimSeller
        PRIMARY KEY (SellerKey),

    CONSTRAINT FK_DimSeller_Geography
        FOREIGN KEY (GeographyKey)
        REFERENCES dwh.DimGeography(GeographyKey)
);
GO


CREATE UNIQUE INDEX UX_DimSeller_SellerID
    ON dwh.DimSeller(SellerID)
    WHERE SellerID IS NOT NULL;
GO


/* =========================================================
   Validation

   Population is performed by SSIS.
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount]
FROM dwh.DimSeller;
GO