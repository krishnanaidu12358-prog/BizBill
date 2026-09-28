/* =====================================================================
   BizFlow - 03_verify.sql
   Quick health check: tables, row counts and the demo accounts.
   Run : sqlcmd -S 192.168.29.53,50491 -U sa -C -I -d BizflowDb -i 03_verify.sql   (asks for the sa password)
   ===================================================================== */

USE BizflowDb;
GO
SET NOCOUNT ON;
GO

PRINT '--- Tables ---';
SELECT t.name AS TableName,
       SUM(CASE WHEN p.index_id IN (0,1) THEN p.rows ELSE 0 END) AS [Rows]
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id
GROUP BY t.name
ORDER BY t.name;
GO

PRINT '';
PRINT '--- Accounts (login = Mobile) ---';
SELECT u.Id,
       u.Mobile,
       u.FullName,
       u.Role,
       ISNULL(b.Name, '-') AS Business,
       u.IsActive
FROM dbo.AppUsers u
LEFT JOIN dbo.Businesses b ON b.Id = u.BusinessId
ORDER BY CASE u.Role WHEN 'SuperAdmin' THEN 1 WHEN 'BusinessUser' THEN 2 ELSE 3 END, u.Id;
GO

PRINT '';
PRINT '--- Money check ---';
SELECT
    (SELECT COUNT(*) FROM dbo.Businesses)                                   AS Businesses,
    (SELECT COUNT(*) FROM dbo.Customers)                                    AS CustomerRecords,
    (SELECT COUNT(*) FROM dbo.Invoices WHERE Status <> 'Cancelled')         AS LiveBills,
    (SELECT ISNULL(SUM(GrandTotal),0) FROM dbo.Invoices WHERE Status <> 'Cancelled') AS TotalSales,
    (SELECT ISNULL(SUM(OutstandingBalance),0) FROM dbo.Customers)           AS TotalUdhaar,
    (SELECT ISNULL(SUM(BalanceAmount),0) FROM dbo.CreditGrants
       WHERE Status IN ('Active','PartiallyClaimed'))                       AS UnclaimedCredit,
    (SELECT COUNT(*) FROM dbo.CreditClaims WHERE Status = 'Pending')        AS PendingClaims,
    (SELECT COUNT(*) FROM dbo.WhatsAppMessages)                             AS WhatsAppMessages;
GO
