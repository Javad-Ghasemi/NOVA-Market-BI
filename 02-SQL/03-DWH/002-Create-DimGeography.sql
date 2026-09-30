USE NOVA_Market;
GO

SET NOCOUNT ON;
GO


/* =========================================================
   NOVA Market BI
   Dimension: dwh.DimGeography

   Grain:
   1 row = 1 ZIP code prefix

   Business Key:
   ZipCodePrefix

   Surrogate Key:
   GeographyKey

   Source:
   conformed.Geography

   Population:
   Loaded by SSIS
   ========================================================= */


IF OBJECT_ID(N'dwh.DimGeography', N'U') IS NOT NULL
    DROP TABLE dwh.DimGeography;
GO


CREATE TABLE dwh.DimGeography
(
    GeographyKey                    INT IDENTITY(1,1) NOT NULL,

    ZipCodePrefix                   VARCHAR(5)       NULL,
    CityName                        NVARCHAR(100)    NULL,
    StateCode                       CHAR(2)          NULL,

    RepresentativeLatitude          DECIMAL(28,20)   NULL,
    RepresentativeLongitude         DECIMAL(28,20)   NULL,

    HasCoordinates                  BIT              NOT NULL,

    MissingFromGeolocationFlag      BIT              NOT NULL,
    StateConflictFlag               BIT              NOT NULL,
    StateAmbiguousFlag              BIT              NOT NULL,
    StateResolvedByReferenceFlag    BIT              NOT NULL,

    CityAmbiguousFlag               BIT              NOT NULL,
    CityResolvedByReferenceFlag     BIT              NOT NULL,

    ReferenceFallbackFlag           BIT              NOT NULL,

    CONSTRAINT PK_DimGeography
        PRIMARY KEY (GeographyKey)
);
GO


/* =========================================================
   Business Key

   NULL is reserved for the future Unknown Member.
   ========================================================= */

CREATE UNIQUE INDEX UX_DimGeography_ZipCodePrefix
    ON dwh.DimGeography(ZipCodePrefix)
    WHERE ZipCodePrefix IS NOT NULL;
GO


/* =========================================================
   Validation

   Expected:
   Table exists and contains 0 rows before SSIS population.
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount]
FROM dwh.DimGeography;
GO


SELECT
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length AS MaxLength,
    c.is_nullable AS IsNullable,
    c.is_identity AS IsIdentity
FROM sys.columns c
INNER JOIN sys.types t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(N'dwh.DimGeography')
ORDER BY c.column_id;
GO