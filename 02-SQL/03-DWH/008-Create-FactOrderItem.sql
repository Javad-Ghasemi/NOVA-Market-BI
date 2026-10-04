USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dwh.FactOrderItem', N'U') IS NOT NULL
    DROP TABLE dwh.FactOrderItem;
GO


CREATE TABLE dwh.FactOrderItem
(
    OrderItemKey INT IDENTITY(1,1) NOT NULL,

    /* Natural transaction grain */
    OrderID VARCHAR(50) NOT NULL,
    OrderItemID INT NOT NULL,

    /* Dimension surrogate keys */
    CustomerKey INT NOT NULL,
    CustomerGeographyKey INT NOT NULL,
    ProductKey INT NOT NULL,
    SellerKey INT NOT NULL,

    /* Role-playing dates */
    PurchaseDateKey INT NOT NULL,
    ShippingLimitDateKey INT NOT NULL,

    /* Order-level descriptive attribute replicated for item analysis */
    OrderStatus VARCHAR(20) NULL,

    /* Source timestamp */
    ShippingLimitTimestamp DATETIME2(0) NULL,

    /* Source monetary measures */
    PriceAmount DECIMAL(18,2) NOT NULL,
    FreightAmount DECIMAL(18,2) NOT NULL,

    /* Additive row-count measure */
    OrderItemCount TINYINT NOT NULL,

    CONSTRAINT PK_FactOrderItem
        PRIMARY KEY (OrderItemKey)
);
GO


CREATE UNIQUE INDEX UX_FactOrderItem_OrderID_OrderItemID
    ON dwh.FactOrderItem(OrderID, OrderItemID);
GO


CREATE INDEX IX_FactOrderItem_ProductKey
    ON dwh.FactOrderItem(ProductKey);
GO


CREATE INDEX IX_FactOrderItem_SellerKey
    ON dwh.FactOrderItem(SellerKey);
GO


CREATE INDEX IX_FactOrderItem_CustomerKey
    ON dwh.FactOrderItem(CustomerKey);
GO


CREATE INDEX IX_FactOrderItem_CustomerGeographyKey
    ON dwh.FactOrderItem(CustomerGeographyKey);
GO


CREATE INDEX IX_FactOrderItem_PurchaseDateKey
    ON dwh.FactOrderItem(PurchaseDateKey);
GO


CREATE INDEX IX_FactOrderItem_ShippingLimitDateKey
    ON dwh.FactOrderItem(ShippingLimitDateKey);
GO


SELECT
    COUNT(*) AS [RowCount]
FROM dwh.FactOrderItem;
GO