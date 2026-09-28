USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.sellers', N'U') IS NOT NULL
    DROP TABLE stg.sellers;
GO

CREATE TABLE stg.sellers
(
    seller_id               VARCHAR(50)   NOT NULL,
    seller_zip_code_prefix  VARCHAR(5)    NULL,
    seller_city             NVARCHAR(100) NULL,
    seller_state            CHAR(2)       NULL
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
WHERE object_id = OBJECT_ID(N'stg.sellers')
ORDER BY column_id;