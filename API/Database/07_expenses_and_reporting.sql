/* =====================================================================
   BizFlow - 07_expenses_and_reporting.sql

   1. Expenses - what a shop spends (rent, stock purchase, salary, ...).
      This is the "expenditure" side of the Super Admin analytics; sales
      minus expenses gives each shop's net.
   2. Reporting views (vw_PowerBI_*) - flat, denormalised views that
      Power BI Desktop can read straight from SQL Server:
         Get Data -> SQL Server -> DESKTOP-BV2BD6K -> BizFlowDb -> vw_PowerBI_*

   Additive and safe to re-run.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 07_expenses_and_reporting.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* 1. Expenses                                                         */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Expenses') IS NULL
CREATE TABLE dbo.Expenses
(
    Id              INT IDENTITY(1,1) CONSTRAINT PK_Expenses PRIMARY KEY,
    BusinessId      INT            NOT NULL,
    Category        NVARCHAR(40)   NOT NULL,
    Amount          DECIMAL(18,2)  NOT NULL,
    ExpenseDate     DATETIME2(0)   NOT NULL,
    PaymentMode     VARCHAR(20)    NOT NULL CONSTRAINT DF_Expenses_Mode DEFAULT ('Cash'),
    PaidTo          NVARCHAR(120)  NULL,
    Note            NVARCHAR(250)  NULL,
    IsCancelled     BIT            NOT NULL CONSTRAINT DF_Expenses_Cancelled DEFAULT (0),
    CreatedByUserId INT            NULL,
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Expenses_Created DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT CK_Expenses_Amount CHECK (Amount > 0),
    CONSTRAINT FK_Expenses_Business FOREIGN KEY (BusinessId)      REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Expenses_User     FOREIGN KEY (CreatedByUserId) REFERENCES dbo.AppUsers(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Expenses_Business_Date')
    CREATE INDEX IX_Expenses_Business_Date ON dbo.Expenses(BusinessId, ExpenseDate DESC);
GO

/* ------------------------------------------------------------------ */
/* 2. Power BI views                                                   */
/* ------------------------------------------------------------------ */
CREATE OR ALTER VIEW dbo.vw_PowerBI_Sales AS
SELECT  i.Id              AS InvoiceId,
        i.InvoiceNumber,
        CAST(i.InvoiceDate AS DATE) AS InvoiceDay,
        i.InvoiceDate,
        b.Id              AS BusinessId,
        b.Name            AS ShopName,
        b.City            AS ShopCity,
        c.Id              AS CustomerId,
        c.Name            AS CustomerName,
        c.Mobile          AS CustomerMobile,
        i.SubTotal, i.DiscountAmount, i.TaxAmount, i.GrandTotal,
        i.PaidAmount, i.BalanceAmount, i.PaymentMode, i.Status
FROM    dbo.Invoices  i
JOIN    dbo.Businesses b ON b.Id = i.BusinessId
JOIN    dbo.Customers  c ON c.Id = i.CustomerId;
GO

CREATE OR ALTER VIEW dbo.vw_PowerBI_Expenses AS
SELECT  e.Id              AS ExpenseId,
        CAST(e.ExpenseDate AS DATE) AS ExpenseDay,
        e.ExpenseDate,
        b.Id              AS BusinessId,
        b.Name            AS ShopName,
        e.Category, e.Amount, e.PaymentMode, e.PaidTo, e.Note
FROM    dbo.Expenses   e
JOIN    dbo.Businesses b ON b.Id = e.BusinessId
WHERE   e.IsCancelled = 0;
GO

CREATE OR ALTER VIEW dbo.vw_PowerBI_Payments AS
SELECT  p.Id              AS PaymentId,
        p.ReceiptNumber,
        CAST(p.PaidOn AS DATE) AS PaidDay,
        p.PaidOn,
        b.Id              AS BusinessId,
        b.Name            AS ShopName,
        c.Id              AS CustomerId,
        c.Name            AS CustomerName,
        p.Amount, p.Mode
FROM    dbo.Payments   p
JOIN    dbo.Businesses b ON b.Id = p.BusinessId
JOIN    dbo.Customers  c ON c.Id = p.CustomerId;
GO

/* One row per shop-customer link, so "how many shops does this person use"
   is a simple COUNT DISTINCT BusinessId grouped by CustomerMobile.        */
CREATE OR ALTER VIEW dbo.vw_PowerBI_Customers AS
SELECT  c.Id              AS CustomerId,
        c.Mobile          AS CustomerMobile,
        c.Name            AS CustomerName,
        b.Id              AS BusinessId,
        b.Name            AS ShopName,
        u.FullName        AS ShopOwner,
        c.IsTrusted, c.CreditLimit, c.OutstandingBalance, c.CreditBalance,
        CASE WHEN c.UserId IS NULL THEN 0 ELSE 1 END AS HasAppAccount,
        c.CreatedAt
FROM    dbo.Customers  c
JOIN    dbo.Businesses b ON b.Id = c.BusinessId
OUTER APPLY (SELECT TOP 1 FullName FROM dbo.AppUsers
             WHERE BusinessId = b.Id AND Role = 'BusinessUser' ORDER BY Id) u
WHERE   c.IsActive = 1;
GO

CREATE OR ALTER VIEW dbo.vw_PowerBI_Shops AS
SELECT  b.Id AS BusinessId, b.Name AS ShopName, b.OwnerName, b.Mobile, b.City, b.State,
        b.IsActive, b.CreatedAt,
        (SELECT COUNT(*) FROM dbo.Customers c WHERE c.BusinessId = b.Id AND c.IsActive = 1) AS Customers,
        (SELECT ISNULL(SUM(GrandTotal),0) FROM dbo.Invoices i
          WHERE i.BusinessId = b.Id AND i.Status <> 'Cancelled')                         AS GrossSales,
        (SELECT ISNULL(SUM(Amount),0) FROM dbo.Expenses e
          WHERE e.BusinessId = b.Id AND e.IsCancelled = 0)                              AS Expenses,
        (SELECT ISNULL(SUM(OutstandingBalance),0) FROM dbo.Customers c
          WHERE c.BusinessId = b.Id)                                                     AS Receivable
FROM    dbo.Businesses b;
GO

PRINT '07_expenses_and_reporting applied.';
GO
