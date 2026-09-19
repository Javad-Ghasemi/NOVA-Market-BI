USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.order_items', N'U') IS NOT NULL
    DROP TABLE stg.order_items;
GO

CREATE TABLE stg.order_items
(
    order_id             VARCHAR(50)   NOT NULL,
    order_item_id        INT           NOT NULL,
    product_id           VARCHAR(50)   NOT NULL,
    seller_id            VARCHAR(50)   NOT NULL,
    shipping_limit_date  DATETIME2(0)  NULL,
    price                 DECIMAL(18,2) NULL,
    freight_value         DECIMAL(18,2) NULL
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
WHERE object_id = OBJECT_ID(N'stg.order_items')
ORDER BY column_id;