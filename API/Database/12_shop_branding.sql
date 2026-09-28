/* =====================================================================
   BizFlow - 12_shop_branding.sql
   Shop profile and bill design: business type (Supermarket, Mart, Kirana ...),
   tagline, logo, signature, signatory, invoice terms, receipt footer.
   Additive and safe to re-run. The API also applies this on start-up.
   Run : sqlcmd -S 192.168.29.53,50491 -U sa -C -I -d BizflowDb -i 12_shop_branding.sql   (asks for the sa password)
   ===================================================================== */

USE BizflowDb;
GO
SET NOCOUNT ON;
GO

IF COL_LENGTH('dbo.Businesses','BusinessType') IS NULL
    ALTER TABLE dbo.Businesses ADD BusinessType NVARCHAR(30) NOT NULL CONSTRAINT DF_Businesses_Type DEFAULT('Retail');
IF COL_LENGTH('dbo.Businesses','Tagline') IS NULL ALTER TABLE dbo.Businesses ADD Tagline NVARCHAR(150) NULL;
IF COL_LENGTH('dbo.Businesses','LogoPath') IS NULL ALTER TABLE dbo.Businesses ADD LogoPath NVARCHAR(400) NULL;
IF COL_LENGTH('dbo.Businesses','LogoContentType') IS NULL ALTER TABLE dbo.Businesses ADD LogoContentType VARCHAR(100) NULL;
IF COL_LENGTH('dbo.Businesses','SignaturePath') IS NULL ALTER TABLE dbo.Businesses ADD SignaturePath NVARCHAR(400) NULL;
IF COL_LENGTH('dbo.Businesses','SignatureContentType') IS NULL ALTER TABLE dbo.Businesses ADD SignatureContentType VARCHAR(100) NULL;
IF COL_LENGTH('dbo.Businesses','SignatoryName') IS NULL ALTER TABLE dbo.Businesses ADD SignatoryName NVARCHAR(120) NULL;
IF COL_LENGTH('dbo.Businesses','InvoiceTerms') IS NULL ALTER TABLE dbo.Businesses ADD InvoiceTerms NVARCHAR(1000) NULL;
IF COL_LENGTH('dbo.Businesses','ReceiptFooter') IS NULL ALTER TABLE dbo.Businesses ADD ReceiptFooter NVARCHAR(200) NULL;
IF COL_LENGTH('dbo.Businesses','ShowLogoOnReceipt') IS NULL
    ALTER TABLE dbo.Businesses ADD ShowLogoOnReceipt BIT NOT NULL CONSTRAINT DF_Businesses_LogoReceipt DEFAULT(1);
IF COL_LENGTH('dbo.Businesses','ShowSignature') IS NULL
    ALTER TABLE dbo.Businesses ADD ShowSignature BIT NOT NULL CONSTRAINT DF_Businesses_ShowSig DEFAULT(1);
IF COL_LENGTH('dbo.Businesses','BrandingUpdatedAt') IS NULL ALTER TABLE dbo.Businesses ADD BrandingUpdatedAt DATETIME2 NULL;
GO

PRINT '12_shop_branding.sql completed.';
GO
