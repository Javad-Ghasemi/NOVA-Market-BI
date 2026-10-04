USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dwh.FactPayment', N'U') IS NOT NULL
    DROP TABLE dwh.FactPayment;
GO


CREATE TABLE dwh.FactPayment
(
    PaymentKey INT IDENTITY(1,1) NOT NULL,

    /* Natural transaction grain */
    OrderID VARCHAR(50) NOT NULL,
    PaymentSequential INT NOT NULL,

    /* Conformed dimension keys */
    CustomerKey INT NOT NULL,
    CustomerGeographyKey INT NOT NULL,
    PurchaseDateKey INT NOT NULL,

    /* Order-level descriptive attribute */
    OrderStatus VARCHAR(20) NULL,

    /* Source payment attributes */
    PaymentType NVARCHAR(30) NULL,
    PaymentInstallments INT NULL,
    PaymentAmount DECIMAL(18,2) NULL,

    /* Additive row-count measure */
    PaymentCount TINYINT NOT NULL,

    /* Source-quality diagnostic flags */
    PaymentSequenceAnomalyFlag BIT NOT NULL,
    UndefinedPaymentTypeFlag BIT NOT NULL,
    ZeroInstallmentFlag BIT NOT NULL,
    ZeroPaymentValueFlag BIT NOT NULL,

    CONSTRAINT PK_FactPayment
        PRIMARY KEY (PaymentKey)
);
GO


CREATE UNIQUE INDEX UX_FactPayment_OrderID_PaymentSequential
    ON dwh.FactPayment(OrderID, PaymentSequential);
GO


CREATE INDEX IX_FactPayment_CustomerKey
    ON dwh.FactPayment(CustomerKey);
GO


CREATE INDEX IX_FactPayment_CustomerGeographyKey
    ON dwh.FactPayment(CustomerGeographyKey);
GO


CREATE INDEX IX_FactPayment_PurchaseDateKey
    ON dwh.FactPayment(PurchaseDateKey);
GO


SELECT
    COUNT(*) AS [RowCount]
FROM dwh.FactPayment;
GO