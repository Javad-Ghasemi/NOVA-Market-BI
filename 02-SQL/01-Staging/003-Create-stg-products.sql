USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.products', N'U') IS NOT NULL
    DROP TABLE stg.products;
GO

CREATE TABLE stg.products
(
    product_id                    VARCHAR(50)    NOT NULL,
    product_category_name         NVARCHAR(100) NULL,
    product_name_lenght           INT           NULL,
    product_description_lenght    INT           NULL,
    product_photos_qty            INT           NULL,
    product_weight_g              INT           NULL,
    product_length_cm             INT           NULL,
    product_height_cm             INT           NULL,
    product_width_cm              INT           NULL
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
WHERE object_id = OBJECT_ID(N'stg.products')
ORDER BY column_id;