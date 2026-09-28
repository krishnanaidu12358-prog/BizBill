/* =====================================================================
   BizFlow - 09_shop_upi.sql
   Adds the shop's UPI ID so customers can pay straight from their UPI app
   (Google Pay, PhonePe, Paytm, BHIM ...) and see the shop's payment QR.
   Additive and safe to re-run.
   Run : sqlcmd -S 192.168.29.53,50491 -U sa -C -I -d BizflowDb -i 09_shop_upi.sql   (asks for the sa password)
   ===================================================================== */

USE BizflowDb;
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
