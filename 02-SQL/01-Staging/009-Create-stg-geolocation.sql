USE NOVA_Market;
GO

IF OBJECT_ID(N'stg.geolocation', N'U') IS NOT NULL
    DROP TABLE stg.geolocation;
GO

CREATE TABLE stg.geolocation
(
    geolocation_zip_code_prefix  VARCHAR(5)      NOT NULL,
    geolocation_lat              DECIMAL(28,20)  NOT NULL,
    geolocation_lng              DECIMAL(28,20)  NOT NULL,
    geolocation_city             NVARCHAR(100)   NOT NULL,
    geolocation_state            CHAR(2)         NOT NULL
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
WHERE object_id = OBJECT_ID(N'stg.geolocation')
ORDER BY column_id;
