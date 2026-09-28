USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.reviews', N'U') IS NOT NULL
    DROP TABLE stg.reviews;
GO

CREATE TABLE stg.reviews
(
    review_id                VARCHAR(50)     NOT NULL,
    order_id                 VARCHAR(50)     NOT NULL,
    review_score             INT             NOT NULL,
    review_comment_title     NVARCHAR(100)   NULL,
    review_comment_message   NVARCHAR(1000)  NULL,
    review_creation_date     DATETIME2       NOT NULL,
    review_answer_timestamp  DATETIME2       NOT NULL
);
GO

SELECT
    column_id,
    name AS ColumnName,
    TYPE_NAME(user_type_id) AS DataType,
    max_length,
    precision,
    scale,
    is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID(N'stg.reviews')
ORDER BY column_id;