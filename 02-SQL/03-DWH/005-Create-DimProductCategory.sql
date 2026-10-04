USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dwh.DimProductCategory', N'U') IS NOT NULL
    DROP TABLE dwh.DimProductCategory;
GO


CREATE TABLE dwh.DimProductCategory
(
    ProductCategoryKey INT IDENTITY(1,1) NOT NULL,

    SourceCategoryName VARCHAR(100) NULL,
    EnglishCategoryName VARCHAR(100) NULL,
    PersianCategoryName NVARCHAR(100) NOT NULL,

    MissingEnglishTranslationFlag BIT NOT NULL,
    MissingPersianLocalizationFlag BIT NOT NULL,

    CONSTRAINT PK_DimProductCategory
        PRIMARY KEY (ProductCategoryKey)
);
GO


CREATE UNIQUE INDEX UX_DimProductCategory_SourceCategoryName
    ON dwh.DimProductCategory(SourceCategoryName)
    WHERE SourceCategoryName IS NOT NULL;
GO


SELECT
    COUNT(*) AS [RowCount]
FROM dwh.DimProductCategory;
GO