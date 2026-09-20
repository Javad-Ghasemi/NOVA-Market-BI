USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.category_translation', N'U') IS NOT NULL
    DROP TABLE stg.category_translation;
GO

CREATE TABLE stg.category_translation
(
    product_category_name          NVARCHAR(100) NOT NULL,
    product_category_name_english  NVARCHAR(100) NULL
);
GO

-- Validate table structure
SELECT
    column_id,
    name AS ColumnName,
    TYPE_NAME(user_type_id) AS DataType,
    max_length,
    precision,
    scale,
    is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID(N'stg.category_translation')
ORDER BY column_id;