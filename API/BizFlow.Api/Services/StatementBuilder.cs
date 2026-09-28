using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Services;

/// <summary>
/// Builds a customer's running account with one shop: every unpaid bill with its
/// date, oldest first, and the combined amount due. Used by the owner screen, the
/// customer screen and the WhatsApp statement.
/// </summary>
public static class StatementBuilder
{
    public static async Task<StatementDto> BuildAsync(AppDbContext db, Customer cust,
                                                      Business? biz, CancellationToken ct = default)
    {
        var live = db.Invoices.AsNoTracking()
                     .Where(i => i.CustomerId == cust.Id && i.Status != InvoiceStatus.Cancelled);

        var unpaid = await live.Where(i => i.BalanceAmount > 0)
                               .OrderBy(i => i.InvoiceDate)
                               .ToListAsync(ct);

        var now = DateTime.UtcNow;

        return new StatementDto
        {
            CustomerId      = cust.Id,
            CustomerName    = cust.Name,
            CustomerMobile  = cust.Mobile,
            BusinessId      = cust.BusinessId,
            BusinessName    = biz?.Name ?? "",
            TotalBilled     = await live.SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
            TotalPaid       = await live.SumAsync(i => (decimal?)i.PaidAmount, ct) ?? 0,
            TotalDue        = cust.OutstandingBalance,
            CreditAvailable = cust.CreditBalance,
            OldestBillDays  = unpaid.Count == 0
                ? 0
                : (int)(now - unpaid.First().InvoiceDate).TotalDays,
            UnpaidBills = unpaid.Select(i => new StatementLineDto
            {
                InvoiceId     = i.Id,
                InvoiceNumber = i.InvoiceNumber,
                InvoiceDate   = i.InvoiceDate,
                GrandTotal    = i.GrandTotal,
                PaidAmount    = i.PaidAmount,
                BalanceAmount = i.BalanceAmount,
                Status        = i.Status,
                DaysOld       = (int)(now - i.InvoiceDate).TotalDays
            }).ToList()
        };
    }

    /// <summary>Unpaid bills with their items, for the WhatsApp statement text.</summary>
    public static Task<List<Invoice>> UnpaidWithItemsAsync(AppDbContext db, int customerId,
                                                           CancellationToken ct = default) =>
        db.Invoices.AsNoTracking().Include(i => i.Items)
          .Where(i => i.CustomerId == customerId &&
                      i.BalanceAmount > 0 &&
                      i.Status != InvoiceStatus.Cancelled)
          .OrderBy(i => i.InvoiceDate)
          .ToListAsync(ct);
}
