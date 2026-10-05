USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   Create DQ Procedure:
   dq.usp_ValidateWarehouse

   Purpose:
   - Single orchestration entry point for full DWH DQ
   - Executes all dimension and fact validations
   - Stops immediately if any validation throws
   - Intended for SSMS and SSIS Master execution

   Validation order follows DWH dependencies.
   ========================================================= */

CREATE OR ALTER PROCEDURE dq.usp_ValidateWarehouse
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        PRINT '=========================================================';
        PRINT 'NOVA MARKET - WAREHOUSE DATA QUALITY VALIDATION';
        PRINT '=========================================================';


        /* =================================================
           Dimensions
           ================================================= */

        PRINT 'DQ 1/9 - DimGeography';
        EXEC dq.usp_ValidateDimGeography;


        PRINT 'DQ 2/9 - DimCustomer';
        EXEC dq.usp_ValidateDimCustomer;


        PRINT 'DQ 3/9 - DimSeller';
        EXEC dq.usp_ValidateDimSeller;


        PRINT 'DQ 4/9 - DimProductCategory';
        EXEC dq.usp_ValidateDimProductCategory;


        PRINT 'DQ 5/9 - DimProduct';
        EXEC dq.usp_ValidateDimProduct;


        /* =================================================
           Facts
           ================================================= */

        PRINT 'DQ 6/9 - FactOrder';
        EXEC dq.usp_ValidateFactOrder;


        PRINT 'DQ 7/9 - FactOrderItem';
        EXEC dq.usp_ValidateFactOrderItem;


        PRINT 'DQ 8/9 - FactPayment';
        EXEC dq.usp_ValidateFactPayment;


        PRINT 'DQ 9/9 - FactReview';
        EXEC dq.usp_ValidateFactReview;


        /* =================================================
           Success
           ================================================= */

        PRINT '=========================================================';
        PRINT 'WAREHOUSE DATA QUALITY VALIDATION PASSED.';
        PRINT '=========================================================';

    END TRY

    BEGIN CATCH

        DECLARE
            @ErrorNumber    int            = ERROR_NUMBER(),
            @ErrorMessage   nvarchar(4000) = ERROR_MESSAGE(),
            @ErrorProcedure sysname        = ERROR_PROCEDURE(),
            @ErrorLine      int            = ERROR_LINE();

        PRINT '=========================================================';
        PRINT 'WAREHOUSE DATA QUALITY VALIDATION FAILED.';
        PRINT CONCAT('Error Number: ', @ErrorNumber);
        PRINT CONCAT(
            'Procedure: ',
            COALESCE(@ErrorProcedure, N'<unknown>')
        );
        PRINT CONCAT('Line: ', @ErrorLine);
        PRINT CONCAT('Message: ', @ErrorMessage);
        PRINT '=========================================================';

        THROW;

    END CATCH;
END;
GO