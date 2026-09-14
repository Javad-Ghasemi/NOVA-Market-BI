/*
=========================================================
NOVA Market BI
Layer       : Staging
Object      : stg.orders
Source      : olist_orders_dataset.csv
Grain       : One row per order
Purpose     : Raw source representation in SQL Server

Important:
- No business transformation is applied here.
- Source structure is preserved as much as practical.
=========================================================
*/

USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.orders', N'U') IS NOT NULL
    DROP TABLE stg.orders;
GO

CREATE TABLE stg.orders
(
    order_id                         VARCHAR(50)  NOT NULL,
    customer_id                      VARCHAR(50)  NOT NULL,

    order_status                     VARCHAR(20)  NULL,

    order_purchase_timestamp         DATETIME2(0) NULL,
    order_approved_at                DATETIME2(0) NULL,
    order_delivered_carrier_date     DATETIME2(0) NULL,
    order_delivered_customer_date    DATETIME2(0) NULL,
    order_estimated_delivery_date    DATE         NULL
);
GO

/*
=========================================================
Validation
=========================================================
*/

SELECT
    c.column_id,
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length,
    c.is_nullable
FROM sys.columns AS c
JOIN sys.types AS t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(N'stg.orders')
ORDER BY c.column_id;
GO