USE NOVA_Market;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'conformed'
)
BEGIN
    EXEC('CREATE SCHEMA conformed');
END;
GO

SELECT
    name AS SchemaName
FROM sys.schemas
WHERE name IN ('stg', 'conformed', 'dwh', 'dq', 'meta')
ORDER BY name;
GO