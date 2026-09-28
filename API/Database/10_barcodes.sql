/* =====================================================================
   BizFlow - 10_barcodes.sql
   Adds a barcode to products so the counter can scan packs (USB / Bluetooth
   scanner on Windows, camera on the phone). Additive and safe to re-run.
   Run : sqlcmd -S 192.168.29.53,50491 -U sa -C -I -d BizflowDb -i 10_barcodes.sql   (asks for the sa password)
   ===================================================================== */

USE BizflowDb;
GO
SET NOCOUNT ON;
GO

IF COL_LENGTH('dbo.Products', 'Barcode') IS NULL
    ALTER TABLE dbo.Products ADD Barcode VARCHAR(64) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Products_Business_Barcode')
    CREATE INDEX IX_Products_Business_Barcode ON dbo.Products(BusinessId, Barcode);
GO

PRINT '10_barcodes.sql completed.';
GO
