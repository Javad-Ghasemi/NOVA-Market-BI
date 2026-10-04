USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

DECLARE
    @ConformedRows             INT,
    @LocalizationRows          INT,
    @MissingPersianNames       INT,
    @MissingLocalizationRows   INT,
    @OrphanLocalizationRows    INT,
    @DuplicateLocalizationRows INT;


SELECT
    @ConformedRows = COUNT(*)
FROM conformed.ProductCategory;


SELECT
    @LocalizationRows = COUNT(*)
FROM meta.ProductCategoryLocalization;


SELECT
    @MissingPersianNames = COUNT(*)
FROM meta.ProductCategoryLocalization
WHERE PersianCategoryName IS NULL
   OR LTRIM(RTRIM(PersianCategoryName)) = N'';


SELECT
    @MissingLocalizationRows = COUNT(*)
FROM conformed.ProductCategory AS c
LEFT JOIN meta.ProductCategoryLocalization AS l
    ON c.SourceCategoryName = l.SourceCategoryName
WHERE l.SourceCategoryName IS NULL;


SELECT
    @OrphanLocalizationRows = COUNT(*)
FROM meta.ProductCategoryLocalization AS l
LEFT JOIN conformed.ProductCategory AS c
    ON l.SourceCategoryName = c.SourceCategoryName
WHERE c.SourceCategoryName IS NULL;


SELECT
    @DuplicateLocalizationRows = COUNT(*)
FROM
(
    SELECT SourceCategoryName
    FROM meta.ProductCategoryLocalization
    GROUP BY SourceCategoryName
    HAVING COUNT(*) > 1
) AS d;


SELECT
    @ConformedRows             AS ConformedCategoryRows,
    @LocalizationRows          AS LocalizationRows,
    @MissingPersianNames       AS MissingPersianNames,
    @MissingLocalizationRows   AS MissingLocalizationRows,
    @OrphanLocalizationRows    AS OrphanLocalizationRows,
    @DuplicateLocalizationRows AS DuplicateLocalizationRows;
GO


IF
(
    SELECT COUNT(*)
    FROM conformed.ProductCategory
)
<>
(
    SELECT COUNT(*)
    FROM meta.ProductCategoryLocalization
)
    THROW 51000,
        'Product category localization validation failed: row count mismatch.',
        1;


IF EXISTS
(
    SELECT 1
    FROM meta.ProductCategoryLocalization
    WHERE PersianCategoryName IS NULL
       OR LTRIM(RTRIM(PersianCategoryName)) = N''
)
    THROW 51001,
        'Product category localization validation failed: missing Persian category name.',
        1;


IF EXISTS
(
    SELECT 1
    FROM conformed.ProductCategory AS c
    LEFT JOIN meta.ProductCategoryLocalization AS l
        ON c.SourceCategoryName = l.SourceCategoryName
    WHERE l.SourceCategoryName IS NULL
)
    THROW 51002,
        'Product category localization validation failed: missing localization row.',
        1;


IF EXISTS
(
    SELECT 1
    FROM meta.ProductCategoryLocalization AS l
    LEFT JOIN conformed.ProductCategory AS c
        ON l.SourceCategoryName = c.SourceCategoryName
    WHERE c.SourceCategoryName IS NULL
)
    THROW 51003,
        'Product category localization validation failed: orphan localization row.',
        1;


PRINT 'PRODUCT CATEGORY PERSIAN LOCALIZATION VALIDATION PASSED.';
GO