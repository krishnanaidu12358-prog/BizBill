/* =====================================================================
   BizFlow - 06_reconcile_balances.sql

   One-off repair. Approved credit claims and payments that were not tied to
   a specific bill used to reduce Customers.OutstandingBalance without
   touching the matching Invoices.BalanceAmount, so a customer's statement
   listed more unpaid than they actually owed.

   The application now allocates such amounts to the oldest unpaid bills
   (BookkeepingService.AllocateToOldestUnpaidAsync). This script fixes the
   rows written before that change.

   Safe to re-run: it does nothing once the two figures agree.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 06_reconcile_balances.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

PRINT '--- before ---';
SELECT c.Id, c.Name, c.OutstandingBalance,
       ISNULL(SUM(i.BalanceAmount), 0) AS UnpaidOnBills,
       c.OutstandingBalance - ISNULL(SUM(i.BalanceAmount), 0) AS Difference
FROM dbo.Customers c
LEFT JOIN dbo.Invoices i
       ON i.CustomerId = c.Id AND i.BalanceAmount > 0 AND i.Status <> 'Cancelled'
GROUP BY c.Id, c.Name, c.OutstandingBalance
HAVING ISNULL(SUM(i.BalanceAmount), 0) <> c.OutstandingBalance
ORDER BY c.Id;
GO

DECLARE @CustomerId INT, @Excess DECIMAL(18,2);

DECLARE drift CURSOR LOCAL FAST_FORWARD FOR
    SELECT c.Id, ISNULL(SUM(i.BalanceAmount), 0) - c.OutstandingBalance
    FROM dbo.Customers c
    LEFT JOIN dbo.Invoices i
           ON i.CustomerId = c.Id AND i.BalanceAmount > 0 AND i.Status <> 'Cancelled'
    GROUP BY c.Id, c.OutstandingBalance
    HAVING ISNULL(SUM(i.BalanceAmount), 0) > c.OutstandingBalance;

OPEN drift;
FETCH NEXT FROM drift INTO @CustomerId, @Excess;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT('Customer ', @CustomerId, ': settling ', @Excess, ' against oldest bills.');

    DECLARE @InvoiceId INT, @Balance DECIMAL(18,2), @Take DECIMAL(18,2);

    DECLARE bills CURSOR LOCAL FAST_FORWARD FOR
        SELECT Id, BalanceAmount
        FROM dbo.Invoices
        WHERE CustomerId = @CustomerId AND BalanceAmount > 0 AND Status <> 'Cancelled'
        ORDER BY InvoiceDate, Id;

    OPEN bills;
    FETCH NEXT FROM bills INTO @InvoiceId, @Balance;

    WHILE @@FETCH_STATUS = 0 AND @Excess > 0
    BEGIN
        SET @Take = CASE WHEN @Excess < @Balance THEN @Excess ELSE @Balance END;

        UPDATE dbo.Invoices
        SET PaidAmount    = PaidAmount + @Take,
            BalanceAmount = ROUND(GrandTotal - (PaidAmount + @Take), 2),
            Status        = CASE WHEN ROUND(GrandTotal - (PaidAmount + @Take), 2) <= 0
                                 THEN 'Paid' ELSE 'PartiallyPaid' END
        WHERE Id = @InvoiceId;

        SET @Excess -= @Take;
        FETCH NEXT FROM bills INTO @InvoiceId, @Balance;
    END

    CLOSE bills;
    DEALLOCATE bills;

    FETCH NEXT FROM drift INTO @CustomerId, @Excess;
END

CLOSE drift;
DEALLOCATE drift;
GO

PRINT '';
PRINT '--- after (no rows means everything reconciles) ---';
SELECT c.Id, c.Name, c.OutstandingBalance,
       ISNULL(SUM(i.BalanceAmount), 0) AS UnpaidOnBills
FROM dbo.Customers c
LEFT JOIN dbo.Invoices i
       ON i.CustomerId = c.Id AND i.BalanceAmount > 0 AND i.Status <> 'Cancelled'
GROUP BY c.Id, c.Name, c.OutstandingBalance
HAVING ISNULL(SUM(i.BalanceAmount), 0) <> c.OutstandingBalance
ORDER BY c.Id;
GO

PRINT '06_reconcile_balances.sql completed.';
GO
