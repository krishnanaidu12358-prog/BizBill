using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

[Authorize(Roles = Roles.BusinessUser + "," + Roles.SuperAdmin)]
public class DashboardController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;

    public DashboardController(AppDbContext db, ICurrentUser me) { _db = db; _me = me; }

    [HttpGet]
    public async Task<IActionResult> Get([FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == bizId, ct);
        if (biz is null) return NotFoundMsg("Business not found.");

        var today      = DateTime.UtcNow.Date;
        var monthStart = new DateTime(today.Year, today.Month, 1);

        var live = _db.Invoices.AsNoTracking()
                       .Where(i => i.BusinessId == bizId && i.Status != InvoiceStatus.Cancelled);

        var dto = new OwnerDashboardDto
        {
            BusinessName = biz.Name,
            TodaySales   = await live.Where(i => i.InvoiceDate >= today).SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
            MonthSales   = await live.Where(i => i.InvoiceDate >= monthStart).SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
            InvoiceCountThisMonth = await live.CountAsync(i => i.InvoiceDate >= monthStart, ct),

            TotalReceivable = await _db.Customers.AsNoTracking()
                                    .Where(c => c.BusinessId == bizId && c.IsActive)
                                    .SumAsync(c => (decimal?)c.OutstandingBalance, ct) ?? 0,

            TodayCollection = await _db.Payments.AsNoTracking()
                                    .Where(p => p.BusinessId == bizId && p.PaidOn >= today)
                                    .SumAsync(p => (decimal?)p.Amount, ct) ?? 0,

            OutstandingCreditIssued = await _db.CreditGrants.AsNoTracking()
                                    .Where(g => g.BusinessId == bizId &&
                                               (g.Status == CreditStatus.Active ||
                                                g.Status == CreditStatus.PartiallyClaimed))
                                    .SumAsync(g => (decimal?)g.BalanceAmount, ct) ?? 0,

            CustomerCount = await _db.Customers.CountAsync(c => c.BusinessId == bizId && c.IsActive, ct),
            ProductCount  = await _db.Products.CountAsync(p => p.BusinessId == bizId && p.IsActive, ct),
            LowStockCount = await _db.Products.CountAsync(p => p.BusinessId == bizId && p.IsActive &&
                                                               p.StockQty <= p.MinStockQty, ct),
            PendingClaimCount = await _db.CreditClaims.CountAsync(c => c.BusinessId == bizId &&
                                                                       c.Status == ClaimStatus.Pending, ct),
            MonthExpenses = await _db.Expenses.AsNoTracking()
                                    .Where(e => e.BusinessId == bizId && !e.IsCancelled &&
                                                e.ExpenseDate >= monthStart)
                                    .SumAsync(e => (decimal?)e.Amount, ct) ?? 0
        };

        var recent = await _db.Invoices.AsNoTracking()
                              .Include(i => i.Customer).Include(i => i.Business)
                              .Where(i => i.BusinessId == bizId)
                              .OrderByDescending(i => i.Id).Take(10).ToListAsync(ct);
        dto.RecentInvoices = recent.Select(i => ToDto(i, i.Business, i.Customer)).ToList();

        return Ok(dto);
    }

    /// <summary>Sales / receivables / stock report with a date range (FR-030, FR-031).</summary>
    [HttpGet("reports/summary")]
    public async Task<IActionResult> Summary([FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                             [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var start = from ?? DateTime.UtcNow.Date.AddDays(-30);
        var end   = to   ?? DateTime.UtcNow;

        var live = _db.Invoices.AsNoTracking()
                       .Where(i => i.BusinessId == bizId && i.Status != InvoiceStatus.Cancelled &&
                                   i.InvoiceDate >= start && i.InvoiceDate <= end);

        var byDay = await live.GroupBy(i => i.InvoiceDate.Date)
                              .Select(g => new { Date = g.Key, Total = g.Sum(x => x.GrandTotal), Count = g.Count() })
                              .OrderBy(x => x.Date).ToListAsync(ct);

        var topCustomers = await live.GroupBy(i => i.CustomerId)
                                     .Select(g => new { CustomerId = g.Key, Total = g.Sum(x => x.GrandTotal) })
                                     .OrderByDescending(x => x.Total).Take(5).ToListAsync(ct);

        var names = await _db.Customers.AsNoTracking()
                             .Where(c => topCustomers.Select(t => t.CustomerId).Contains(c.Id))
                             .ToDictionaryAsync(c => c.Id, c => c.Name, ct);

        return Ok(new
        {
            From = start,
            To = end,
            TotalSales    = await live.SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
            TotalCollected= await live.SumAsync(i => (decimal?)i.PaidAmount, ct) ?? 0,
            TotalCredit   = await live.SumAsync(i => (decimal?)i.BalanceAmount, ct) ?? 0,
            InvoiceCount  = await live.CountAsync(ct),
            DailySales    = byDay,
            TopCustomers  = topCustomers.Select(t => new
            {
                t.CustomerId,
                Name = names.TryGetValue(t.CustomerId, out var n) ? n : "",
                t.Total
            })
        });
    }
}
