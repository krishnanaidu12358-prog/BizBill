/* =====================================================================
   BizFlow - 09_shop_upi.sql
   Adds the shop's UPI ID so customers can pay straight from their UPI app
   (Google Pay, PhonePe, Paytm, BHIM ...) and see the shop's payment QR.
   Additive and safe to re-run.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 09_shop_upi.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

IF COL_LENGTH('dbo.Businesses', 'UpiId') IS NULL
    ALTER TABLE dbo.Businesses ADD UpiId VARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.Businesses', 'UpiName') IS NULL
    ALTER TABLE dbo.Businesses ADD UpiName NVARCHAR(100) NULL;
GO

PRINT '09_shop_upi.sql completed.';
GO
