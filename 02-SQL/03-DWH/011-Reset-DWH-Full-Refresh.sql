USE NOVA_Market;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   NOVA Market BI
   DWH Full-Refresh Reset

   Purpose:
   - Clear fact tables.
   - Clear dimensions in FK-safe dependency order.
   - Reseed surrogate-key identity columns.
   - Preserve DimDate as a separately managed static dimension.

   Important:
   - This script intentionally removes all loaded DWH data
     except DimDate.
   - Dimension ETL packages are responsible for recreating
     Unknown members after this reset.
   - Do not run this script independently unless a complete
     DWH reload will follow.
   ========================================================= */

IF DB_NAME() <> N'NOVA_Market'
BEGIN
    THROW 51040, 'Full-refresh reset aborted: current database is not NOVA_Market.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* =====================================================
       1. Clear facts first.

       Facts currently have no physical foreign keys to the
       dimensions, so TRUNCATE is safe and also resets their
       identity values automatically.
       ===================================================== */

    TRUNCATE TABLE dwh.FactReview;
    TRUNCATE TABLE dwh.FactPayment;
    TRUNCATE TABLE dwh.FactOrderItem;
    TRUNCATE TABLE dwh.FactOrder;


    /* =====================================================
       2. Clear child dimensions before referenced parents.

       Dependency relationships:

       DimCustomer -> DimGeography
       DimSeller   -> DimGeography
       DimProduct  -> DimProductCategory
       ===================================================== */

    DELETE FROM dwh.DimCustomer;
    DELETE FROM dwh.DimSeller;
    DELETE FROM dwh.DimProduct;


    /* =====================================================
       3. Clear parent dimensions.

       DELETE is required instead of TRUNCATE because these
       tables are referenced by physical foreign keys.
       ===================================================== */

    DELETE FROM dwh.DimGeography;
    DELETE FROM dwh.DimProductCategory;


    /* =====================================================
       4. Reset dimension surrogate-key identities.

       Dimension packages recreate the Unknown member at key 0
       with IDENTITY_INSERT.

       After the Unknown member is inserted, normal business
       rows will again receive keys beginning at 1.
       ===================================================== */

    DBCC CHECKIDENT ('dwh.DimGeography', RESEED, 0);
    DBCC CHECKIDENT ('dwh.DimCustomer', RESEED, 0);
    DBCC CHECKIDENT ('dwh.DimSeller', RESEED, 0);
    DBCC CHECKIDENT ('dwh.DimProductCategory', RESEED, 0);
    DBCC CHECKIDENT ('dwh.DimProduct', RESEED, 0);


    COMMIT TRANSACTION;

    PRINT 'DWH FULL-REFRESH RESET COMPLETED SUCCESSFULLY.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO