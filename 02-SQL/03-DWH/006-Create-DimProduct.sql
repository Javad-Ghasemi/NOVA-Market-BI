USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dwh.DimProduct', N'U') IS NOT NULL
    DROP TABLE dwh.DimProduct;
GO


CREATE TABLE dwh.DimProduct
(
    ProductKey INT IDENTITY(1,1) NOT NULL,

    ProductID VARCHAR(50) NULL,

    ProductCategoryKey INT NOT NULL,

    ProductNameLength INT NULL,
    ProductDescriptionLength INT NULL,
    ProductPhotosQty INT NULL,

    ProductWeightG INT NULL,
    ProductLengthCm INT NULL,
    ProductHeightCm INT NULL,
    ProductWidthCm INT NULL,

    MissingSourceCategoryFlag BIT NOT NULL,
    MissingDescriptiveAttributesFlag BIT NOT NULL,
    MissingPhysicalAttributesFlag BIT NOT NULL,
    ZeroWeightFlag BIT NOT NULL,

    CONSTRAINT PK_DimProduct
        PRIMARY KEY (ProductKey),

    CONSTRAINT FK_DimProduct_ProductCategory
        FOREIGN KEY (ProductCategoryKey)
        REFERENCES dwh.DimProductCategory(ProductCategoryKey)
);
GO


CREATE UNIQUE INDEX UX_DimProduct_ProductID
    ON dwh.DimProduct(ProductID)
    WHERE ProductID IS NOT NULL;
GO


SELECT
    COUNT(*) AS [RowCount]
FROM dwh.DimProduct;
GO