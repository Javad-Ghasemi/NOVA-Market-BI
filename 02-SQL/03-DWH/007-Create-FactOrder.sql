USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dwh.FactOrder', N'U') IS NOT NULL
    DROP TABLE dwh.FactOrder;
GO


CREATE TABLE dwh.FactOrder
(
    OrderKey INT IDENTITY(1,1) NOT NULL,

    /* Degenerate business key */
    OrderID VARCHAR(50) NOT NULL,

    /* Dimension surrogate keys */
    CustomerKey INT NOT NULL,
    CustomerGeographyKey INT NOT NULL,

    PurchaseDateKey INT NOT NULL,
    ApprovedDateKey INT NOT NULL,
    CarrierDateKey INT NOT NULL,
    DeliveredDateKey INT NOT NULL,
    EstimatedDeliveryDateKey INT NOT NULL,

    /* Source business attributes */
    OrderStatus VARCHAR(20) NULL,

    /* Source timestamps preserved at source precision */
    PurchaseTimestamp DATETIME2(0) NULL,
    ApprovedTimestamp DATETIME2(0) NULL,
    DeliveredCarrierTimestamp DATETIME2(0) NULL,
    DeliveredCustomerTimestamp DATETIME2(0) NULL,
    EstimatedDeliveryDate DATE NULL,

    /* Additive row-count measure */
    OrderCount TINYINT NOT NULL,

    /* Source temporal DQ flags */
    CarrierBeforePurchaseFlag BIT NOT NULL,
    CarrierBeforeApprovalFlag BIT NOT NULL,
    DeliveredBeforeCarrierFlag BIT NOT NULL,

    /*
       Business KPI flag:
       1 = delivered after estimated date
       0 = delivered on/before estimated date
       NULL = no actual customer delivery timestamp
    */
    DeliveredLateFlag BIT NULL,

    CONSTRAINT PK_FactOrder
        PRIMARY KEY (OrderKey)
);
GO


CREATE UNIQUE INDEX UX_FactOrder_OrderID
    ON dwh.FactOrder(OrderID);
GO


CREATE INDEX IX_FactOrder_CustomerKey
    ON dwh.FactOrder(CustomerKey);
GO


CREATE INDEX IX_FactOrder_CustomerGeographyKey
    ON dwh.FactOrder(CustomerGeographyKey);
GO


CREATE INDEX IX_FactOrder_PurchaseDateKey
    ON dwh.FactOrder(PurchaseDateKey);
GO


SELECT
    COUNT(*) AS [RowCount]
FROM dwh.FactOrder;
GO