USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.payments', N'U') IS NOT NULL
    DROP TABLE stg.payments;
GO

CREATE TABLE stg.payments
(
    order_id              VARCHAR(50)    NOT NULL,
    payment_sequential    INT            NOT NULL,
    payment_type          NVARCHAR(30)   NULL,
    payment_installments  INT            NULL,
    payment_value         DECIMAL(18,2)  NULL
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
WHERE object_id = OBJECT_ID(N'stg.payments')
ORDER BY column_id;