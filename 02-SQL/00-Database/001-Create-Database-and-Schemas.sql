/*
=========================================================
NOVA Market BI
Layer  : Database
Purpose: Create project database and schemas
=========================================================
*/

USE master;
GO

IF DB_ID(N'NOVA_Market') IS NULL
BEGIN
    CREATE DATABASE NOVA_Market;
END
GO

USE NOVA_Market;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'stg'
)
    EXEC(N'CREATE SCHEMA stg');
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'dwh'
)
    EXEC(N'CREATE SCHEMA dwh');
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'dq'
)
    EXEC(N'CREATE SCHEMA dq');
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = N'meta'
)
    EXEC(N'CREATE SCHEMA meta');
GO