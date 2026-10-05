USE NOVA_Market;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   NOVA Market BI
   DimCustomer Data Quality Validation Wrapper

   Validation logic is centralized in:
   dq.usp_ValidateDimCustomer

   This wrapper is kept for:
   - manual execution from SSMS,
   - source-control discoverability,
   - compatibility with the existing DQ script sequence.
   ========================================================= */

EXEC dq.usp_ValidateDimCustomer;
GO