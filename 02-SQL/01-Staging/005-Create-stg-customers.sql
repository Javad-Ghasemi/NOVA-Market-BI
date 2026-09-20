USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.customers', N'U') IS NOT NULL
    DROP TABLE stg.customers;
GO

CREATE TABLE stg.customers
(
    customer_id               VARCHAR(50)   NOT NULL,
    customer_unique_id        VARCHAR(50)   NOT NULL,
    customer_zip_code_prefix  VARCHAR(5)    NULL,
    customer_city             NVARCHAR(100) NULL,
    customer_state            CHAR(2)       NULL
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
WHERE object_id = OBJECT_ID(N'stg.customers')
ORDER BY column_id;