USE NOVA_Market;
GO

CREATE TABLE dwh.FactReview
(
    ReviewKey INT IDENTITY(1,1) NOT NULL,

    /* Natural / degenerate business keys */
    ReviewID VARCHAR(50) NOT NULL,
    OrderID  VARCHAR(50) NOT NULL,

    /* Conformed dimensions */
    CustomerKey INT NOT NULL,
    CustomerGeographyKey INT NOT NULL,

    PurchaseDateKey INT NOT NULL,
    ReviewCreationDateKey INT NOT NULL,
    ReviewAnswerDateKey INT NOT NULL,

    /* Order context */
    OrderStatus VARCHAR(20) NULL,

    /* Review attributes */
    ReviewScore INT NOT NULL,

    ReviewCommentTitle NVARCHAR(100) NULL,
    ReviewCommentMessage NVARCHAR(1000) NULL,

    /* Preserve source timestamps */
    ReviewCreationTimestamp DATETIME2(7) NOT NULL,
    ReviewAnswerTimestamp DATETIME2(7) NOT NULL,

    /* Additive row counter */
    ReviewCount TINYINT NOT NULL,

    /* Source / quality diagnostics */
    DuplicateReviewIDFlag BIT NOT NULL,

    ReviewCreatedBeforePurchaseFlag BIT NOT NULL,

    /* NULL = order has no delivered timestamp */
    ReviewCreatedBeforeDeliveryFlag BIT NULL,

    ReviewAnsweredBeforePurchaseFlag BIT NOT NULL,

    /* NULL = order has no delivered timestamp */
    ReviewAnsweredBeforeDeliveryFlag BIT NULL,

    ReviewAnsweredBeforeCreationFlag BIT NOT NULL,

    CONSTRAINT PK_FactReview
        PRIMARY KEY (ReviewKey)
);
GO


/* Natural grain: one source review row per ReviewID + OrderID */
CREATE UNIQUE INDEX UX_FactReview_ReviewID_OrderID
    ON dwh.FactReview
    (
        ReviewID,
        OrderID
    );
GO


CREATE INDEX IX_FactReview_OrderID
    ON dwh.FactReview
    (
        OrderID
    );
GO


CREATE INDEX IX_FactReview_CustomerKey
    ON dwh.FactReview
    (
        CustomerKey
    );
GO


CREATE INDEX IX_FactReview_CustomerGeographyKey
    ON dwh.FactReview
    (
        CustomerGeographyKey
    );
GO


CREATE INDEX IX_FactReview_PurchaseDateKey
    ON dwh.FactReview
    (
        PurchaseDateKey
    );
GO


CREATE INDEX IX_FactReview_ReviewCreationDateKey
    ON dwh.FactReview
    (
        ReviewCreationDateKey
    );
GO


CREATE INDEX IX_FactReview_ReviewAnswerDateKey
    ON dwh.FactReview
    (
        ReviewAnswerDateKey
    );
GO