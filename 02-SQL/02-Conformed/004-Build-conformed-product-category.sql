USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'conformed.ProductCategory', N'U') IS NOT NULL
    DROP TABLE conformed.ProductCategory;
GO


CREATE TABLE conformed.ProductCategory
(
    SourceCategoryName VARCHAR(100) NOT NULL,
    EnglishCategoryName VARCHAR(100) NULL,
    MissingEnglishTranslationFlag BIT NOT NULL,

    CONSTRAINT PK_conformed_ProductCategory
        PRIMARY KEY (SourceCategoryName)
);
GO


INSERT INTO conformed.ProductCategory
(
    SourceCategoryName,
    EnglishCategoryName,
    MissingEnglishTranslationFlag
)
SELECT
    p.product_category_name AS SourceCategoryName,
    t.product_category_name_english AS EnglishCategoryName,

    CAST(
        CASE
            WHEN t.product_category_name_english IS NULL
                THEN 1
            ELSE 0
        END
        AS BIT
    ) AS MissingEnglishTranslationFlag

FROM
(
    SELECT DISTINCT
        product_category_name
    FROM stg.products
    WHERE product_category_name IS NOT NULL
) AS p

LEFT JOIN stg.category_translation AS t
    ON p.product_category_name = t.product_category_name;
GO


SELECT
    COUNT(*) AS [RowCount],
    SUM(
        CASE
            WHEN MissingEnglishTranslationFlag = 1
            THEN 1 ELSE 0
        END
    ) AS MissingEnglishTranslations
FROM conformed.ProductCategory;
GO


SELECT
    SourceCategoryName,
    EnglishCategoryName,
    MissingEnglishTranslationFlag
FROM conformed.ProductCategory
WHERE MissingEnglishTranslationFlag = 1
ORDER BY SourceCategoryName;
GO