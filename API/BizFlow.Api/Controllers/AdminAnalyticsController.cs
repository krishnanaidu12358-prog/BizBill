using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// Super Admin analytics (the in-app BI dashboard) and the customer-by-person view.
/// Figures are aggregated in memory from narrow projections: it keeps every number
/// in one place and bucketed in IST, and is comfortably fast at the volumes a
/// local SQL Server holds. For heavy reporting, Power BI reads the vw_PowerBI_* views.
/// </summary>
[Authorize(Roles = Roles.SuperAdmin)]
[Route("api/admin")]
public class AdminAnalyticsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICustomerInsightService _insight;

    public AdminAnalyticsController(AppDbContext db, ICustomerInsightService insight)
    {
        _db = db; _insight = insight;
    }

    /// <param name="from">First day, IST (yyyy-MM-dd). Defaults to 29 days ago.</param>
    /// <param name="to">Last day, IST, inclusive. Defaults to today.</param>
    /// <param name="all">Ignore from/to and cover everything since the first shop joined.</param>
    /// <param name="businessId">Limit every figure to one shop (used on the owner drill-down).</param>
    [HttpGet("analytics")]
    public async Task<IActionResult> Analytics([FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                               [FromQuery] bool all = false, [FromQuery] int? businessId = null,
                                               CancellationToken ct = default)
    {
        var today = IndiaTime.Today;
        var lastDay = (to?.Date ?? today);
        DateTime firstDay;
        if (all)
        {
            var first = await _db.Businesses.AsNoTracking()
                                 .Where(b => businessId == null || b.Id == businessId)
                                 .MinAsync(b => (DateTime?)b.CreatedAt, ct);
            firstDay = first is null ? today : IndiaTime.FromUtc(first.Value).Date;
            lastDay = today;
        }
        else firstDay = from?.Date ?? today.AddDays(-29);
        if (firstDay > lastDay) (firstDay, lastDay) = (lastDay, firstDay);

        var startUtc = IndiaTime.ToUtc(firstDay);
        var endUtc   = IndiaTime.ToUtc(lastDay.AddDays(1));
        var monthly  = (lastDay - firstDay).TotalDays > 62;

        // ---------------------------------------------------------- raw rows
        var invQ = _db.Invoices.AsNoTracking().Where(i => i.InvoiceDate >= startUtc && i.InvoiceDate < endUtc);
        var payQ = _db.Payments.AsNoTracking().Where(p => p.PaidOn >= startUtc && p.PaidOn < endUtc);
        var expQ = _db.Expenses.AsNoTracking().Where(e => !e.IsCancelled && e.ExpenseDate >= startUtc && e.ExpenseDate < endUtc);
        var custQ = _db.Customers.AsNoTracking().Where(c => c.IsActive);
        var bizQ  = _db.Businesses.AsNoTracking();
        var grantQ = _db.CreditGrants.AsNoTracking().Where(g => g.CreatedAt >= startUtc && g.CreatedAt < endUtc &&
                                                                g.Status != CreditStatus.Cancelled);

        if (businessId is { } bid)
        {
            invQ = invQ.Where(i => i.BusinessId == bid);
            payQ = payQ.Where(p => p.BusinessId == bid);
            expQ = expQ.Where(e => e.BusinessId == bid);
            custQ = custQ.Where(c => c.BusinessId == bid);
            bizQ = bizQ.Where(b => b.Id == bid);
            grantQ = grantQ.Where(g => g.BusinessId == bid);
        }

        var invoices = await invQ.Select(i => new
        {
            i.Id, i.BusinessId, i.InvoiceDate, i.GrandTotal, i.DiscountAmount, i.TaxAmount, i.Status
        }).ToListAsync(ct);
        var payments = await payQ.Select(p => new { p.BusinessId, p.PaidOn, p.Amount, p.Mode }).ToListAsync(ct);
        var expenses = await expQ.Select(e => new { e.BusinessId, e.ExpenseDate, e.Amount, e.Category }).ToListAsync(ct);
        var customers = await custQ.Select(c => new
        {
            c.BusinessId, c.Mobile, c.CreatedAt, c.OutstandingBalance, HasApp = c.UserId != null
        }).ToListAsync(ct);
        var shops = await bizQ.Select(b => new { b.Id, b.Name, b.OwnerName, b.City, b.IsActive }).ToListAsync(ct);
        var owners = await _db.Users.AsNoTracking()
                              .Where(u => u.Role == Roles.BusinessUser && u.BusinessId != null)
                              .Select(u => new { u.Id, BusinessId = u.BusinessId!.Value, u.FullName })
                              .ToListAsync(ct);

        var live = invoices.Where(i => i.Status != InvoiceStatus.Cancelled).ToList();
        var shopIds = shops.Select(s => s.Id).ToHashSet();

        // --------------------------------------------------------------- KPIs
        var people = customers.GroupBy(c => c.Mobile).ToList();
        var gross = live.Sum(i => i.GrandTotal);
        var spent = expenses.Sum(e => e.Amount);

        var k = new AnalyticsKpiDto
        {
            GrossSales          = gross,
            Discounts           = live.Sum(i => i.DiscountAmount),
            Tax                 = live.Sum(i => i.TaxAmount),
            Collected           = payments.Sum(p => p.Amount),
            Expenditure         = spent,
            Net                 = gross - spent,
            Receivable          = customers.Sum(c => c.OutstandingBalance),
            CreditIssued        = await grantQ.SumAsync(g => (decimal?)g.Amount, ct) ?? 0,
            Bills               = live.Count,
            AverageBill         = live.Count == 0 ? 0 : decimal.Round(gross / live.Count, 2),
            Shops               = shops.Count,
            ActiveShops         = shops.Count(s => s.IsActive),
            ShopOwners          = owners.Count(o => shopIds.Contains(o.BusinessId)),
            Customers           = people.Count,
            CustomerRecords     = customers.Count,
            CustomersWithApp    = people.Count(g => g.Any(c => c.HasApp)),
            MultiShopCustomers  = people.Count(g => g.Select(c => c.BusinessId).Distinct().Count() > 1)
        };

        // -------------------------------------------------------------- trend
        DateTime Bucket(DateTime utc)
        {
            var d = IndiaTime.FromUtc(utc).Date;
            return monthly ? new DateTime(d.Year, d.Month, 1) : d;
        }

        var buckets = new List<DateTime>();
        for (var d = monthly ? new DateTime(firstDay.Year, firstDay.Month, 1) : firstDay;
             d <= lastDay;
             d = monthly ? d.AddMonths(1) : d.AddDays(1))
            buckets.Add(d);

        var salesBy = live.GroupBy(i => Bucket(i.InvoiceDate))
                          .ToDictionary(g => g.Key, g => (Sum: g.Sum(x => x.GrandTotal), Count: g.Count()));
        var paidBy  = payments.GroupBy(p => Bucket(p.PaidOn)).ToDictionary(g => g.Key, g => g.Sum(x => x.Amount));
        var spentBy = expenses.GroupBy(e => Bucket(e.ExpenseDate)).ToDictionary(g => g.Key, g => g.Sum(x => x.Amount));
        // A person is "new" in the bucket where any shop first recorded their mobile.
        var newBy = people.Select(g => g.Min(c => c.CreatedAt))
                          .Where(t => t >= startUtc && t < endUtc)
                          .GroupBy(Bucket).ToDictionary(g => g.Key, g => g.Count());

        var trend = buckets.Select(b => new TrendPointDto
        {
            Start        = b,
            Label        = monthly ? $"{b:MMM} '{b:yy}" : b.ToString("dd MMM"),
            Sales        = salesBy.TryGetValue(b, out var s) ? s.Sum : 0,
            Bills        = salesBy.TryGetValue(b, out var s2) ? s2.Count : 0,
            Collected    = paidBy.GetValueOrDefault(b),
            Expenses     = spentBy.GetValueOrDefault(b),
            NewCustomers = newBy.GetValueOrDefault(b)
        }).ToList();

        // ---------------------------------------------------------- per shop
        var topShops = shops.Select(s =>
        {
            var sales = live.Where(i => i.BusinessId == s.Id).Sum(i => i.GrandTotal);
            var exp   = expenses.Where(e => e.BusinessId == s.Id).Sum(e => e.Amount);
            var owner = owners.FirstOrDefault(o => o.BusinessId == s.Id);
            return new ShopPerformanceDto
            {
                BusinessId = s.Id, ShopName = s.Name, City = s.City,
                OwnerUserId = owner?.Id ?? 0, OwnerName = owner?.FullName ?? s.OwnerName,
                Sales = sales, Expenses = exp, Net = sales - exp,
                Receivable = customers.Where(c => c.BusinessId == s.Id).Sum(c => c.OutstandingBalance),
                Bills = live.Count(i => i.BusinessId == s.Id),
                Customers = customers.Count(c => c.BusinessId == s.Id)
            };
        }).OrderByDescending(s => s.Sales).ThenBy(s => s.ShopName).Take(10).ToList();

        // ------------------------------------------------------- breakdowns
        var liveIds = live.Select(i => i.Id).ToList();
        var topProducts = liveIds.Count == 0
            ? new List<NamedAmountDto>()
            : await _db.InvoiceItems.AsNoTracking()
                       .Where(it => liveIds.Contains(it.InvoiceId))
                       .GroupBy(it => it.ProductName)
                       .Select(g => new NamedAmountDto
                       {
                           Name = g.Key, Amount = g.Sum(x => x.LineTotal), Count = (int)g.Sum(x => x.Quantity)
                       })
                       .OrderByDescending(x => x.Amount).Take(8).ToListAsync(ct);

        return Ok(new AnalyticsDto
        {
            From = firstDay, To = lastDay, BusinessId = businessId,
            Granularity = monthly ? "Month" : "Day",
            Kpis = k,
            Trend = trend,
            TopShops = topShops,
            PaymentModes = payments.GroupBy(p => p.Mode)
                .Select(g => new NamedAmountDto { Name = g.Key, Amount = g.Sum(x => x.Amount), Count = g.Count() })
                .OrderByDescending(x => x.Amount).ToList(),
            ExpenseCategories = expenses.GroupBy(e => e.Category)
                .Select(g => new NamedAmountDto { Name = g.Key, Amount = g.Sum(x => x.Amount), Count = g.Count() })
                .OrderByDescending(x => x.Amount).ToList(),
            BillStatus = invoices.GroupBy(i => i.Status)
                .Select(g => new NamedAmountDto { Name = g.Key, Amount = g.Sum(x => x.GrandTotal), Count = g.Count() })
                .OrderByDescending(x => x.Count).ToList(),
            TopProducts = topProducts
        });
    }

    // ------------------------------------------------------------------
    // Customers as people: one mobile = one person, however many shops
    // ------------------------------------------------------------------

    [HttpGet("people")]
    public async Task<IActionResult> People([FromQuery] string? search, [FromQuery] int minShops = 1,
                                            CancellationToken ct = default)
    {
        var q = _db.Customers.AsNoTracking().Where(c => c.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(c => c.Name.Contains(search) || c.Mobile.Contains(search));

        var rows = await q.Select(c => new
        {
            c.Id, c.BusinessId, c.Mobile, c.Name, c.CreatedAt, c.IsTrusted,
            c.OutstandingBalance, c.CreditBalance, HasApp = c.UserId != null
        }).ToListAsync(ct);

        var ids = rows.Select(r => r.Id).ToList();
        var billed = ids.Count == 0
            ? new Dictionary<int, (decimal Sum, int Count)>()
            : (await _db.Invoices.AsNoTracking()
                        .Where(i => ids.Contains(i.CustomerId) && i.Status != InvoiceStatus.Cancelled)
                        .GroupBy(i => i.CustomerId)
                        .Select(g => new { g.Key, Sum = g.Sum(x => x.GrandTotal), Count = g.Count() })
                        .ToListAsync(ct))
              .ToDictionary(x => x.Key, x => (x.Sum, x.Count));

        var mobiles = rows.Select(r => r.Mobile).Distinct().ToList();
        var accountNames = await _db.Users.AsNoTracking()
                                    .Where(u => u.Role == Roles.Customer && mobiles.Contains(u.Mobile))
                                    .ToDictionaryAsync(u => u.Mobile, u => u.FullName, ct);

        var people = rows.GroupBy(r => r.Mobile).Select(g =>
        {
            var latest = g.OrderByDescending(r => r.CreatedAt).First();
            return new CustomerPersonDto
            {
                Mobile            = g.Key,
                Name              = accountNames.TryGetValue(g.Key, out var n) ? n : latest.Name,
                ShopCount         = g.Select(r => r.BusinessId).Distinct().Count(),
                TotalOutstanding  = g.Sum(r => r.OutstandingBalance),
                TotalCredit       = g.Sum(r => r.CreditBalance),
                TotalBilled       = g.Sum(r => billed.TryGetValue(r.Id, out var b) ? b.Sum : 0),
                BillCount         = g.Sum(r => billed.TryGetValue(r.Id, out var b) ? b.Count : 0),
                HasAppAccount     = g.Any(r => r.HasApp),
                IsTrustedAnywhere = g.Any(r => r.IsTrusted),
                FirstSeen         = g.Min(r => r.CreatedAt)
            };
        })
        .Where(p => p.ShopCount >= minShops)
        .OrderByDescending(p => p.ShopCount).ThenByDescending(p => p.TotalBilled).ThenBy(p => p.Name)
        .ToList();

        return Ok(people);
    }

    /// <summary>One person and every shop that has them as a customer.</summary>
    [HttpGet("people/{mobile}")]
    public async Task<IActionResult> Person(string mobile, CancellationToken ct)
    {
        var records = await _db.Customers.AsNoTracking().Include(c => c.Business)
                               .Where(c => c.Mobile == mobile)
                               .OrderBy(c => c.CreatedAt).ToListAsync(ct);
        if (records.Count == 0) return NotFoundMsg("No shop has this customer.");

        var ids = records.Select(r => r.Id).ToList();
        var bizIds = records.Select(r => r.BusinessId).ToList();

        var stats = await _db.Invoices.AsNoTracking()
                             .Where(i => ids.Contains(i.CustomerId) && i.Status != InvoiceStatus.Cancelled)
                             .GroupBy(i => i.CustomerId)
                             .Select(g => new
                             {
                                 g.Key, Billed = g.Sum(x => x.GrandTotal), Count = g.Count(),
                                 Last = g.Max(x => (DateTime?)x.InvoiceDate)
                             })
                             .ToDictionaryAsync(x => x.Key, ct);
        var paid = await _db.Payments.AsNoTracking()
                            .Where(p => ids.Contains(p.CustomerId))
                            .GroupBy(p => p.CustomerId)
                            .Select(g => new { g.Key, Sum = g.Sum(x => x.Amount) })
                            .ToDictionaryAsync(x => x.Key, x => x.Sum, ct);
        var owners = await _db.Users.AsNoTracking()
                              .Where(u => u.Role == Roles.BusinessUser && u.BusinessId != null &&
                                          bizIds.Contains(u.BusinessId.Value))
                              .OrderBy(u => u.Id)
                              .ToListAsync(ct);

        var account = await _db.Users.AsNoTracking()
                               .FirstOrDefaultAsync(u => u.Mobile == mobile && u.Role == Roles.Customer, ct);

        var shops = records.Select(r =>
        {
            stats.TryGetValue(r.Id, out var s);
            var owner = owners.FirstOrDefault(o => o.BusinessId == r.BusinessId);
            return new CustomerPersonShopDto
            {
                CustomerId = r.Id, BusinessId = r.BusinessId,
                ShopName = r.Business?.Name ?? "", ShopMobile = r.Business?.Mobile ?? "",
                ShopCity = r.Business?.City,
                OwnerUserId = owner?.Id ?? 0, OwnerName = owner?.FullName ?? r.Business?.OwnerName,
                NameAtShop = r.Name, IsTrusted = r.IsTrusted, CreditLimit = r.CreditLimit,
                Outstanding = r.OutstandingBalance, CreditAvailable = r.CreditBalance,
                TotalBilled = s?.Billed ?? 0, BillCount = s?.Count ?? 0, LastBillOn = s?.Last,
                TotalPaid = paid.GetValueOrDefault(r.Id),
                CustomerSince = r.CreatedAt
            };
        }).OrderByDescending(s => s.TotalBilled).ToList();

        var recent = await _db.Invoices.AsNoTracking()
                              .Include(i => i.Business).Include(i => i.Customer)
                              .Where(i => ids.Contains(i.CustomerId))
                              .OrderByDescending(i => i.InvoiceDate).Take(20).ToListAsync(ct);

        return Ok(new CustomerPersonDetailDto
        {
            Person = new CustomerPersonDto
            {
                Mobile = mobile,
                Name = account?.FullName ?? records[^1].Name,
                ShopCount = records.Select(r => r.BusinessId).Distinct().Count(),
                TotalOutstanding = shops.Sum(s => s.Outstanding),
                TotalCredit = shops.Sum(s => s.CreditAvailable),
                TotalBilled = shops.Sum(s => s.TotalBilled),
                BillCount = shops.Sum(s => s.BillCount),
                HasAppAccount = account is not null,
                IsTrustedAnywhere = shops.Any(s => s.IsTrusted),
                FirstSeen = records.Min(r => r.CreatedAt)
            },
            Account = account is null ? null : new AdminUserDto
            {
                Id = account.Id, Mobile = account.Mobile, FullName = account.FullName, Role = account.Role,
                IsActive = account.IsActive, LastLoginAt = account.LastLoginAt, CreatedAt = account.CreatedAt
            },
            Insight = LookupController.ToDto(await _insight.LookupAsync(mobile, null, ct)),
            Shops = shops,
            RecentBills = recent.Select(i => ToDto(i, i.Business, i.Customer)).ToList()
        });
    }
}
