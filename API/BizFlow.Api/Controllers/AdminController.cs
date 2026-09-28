using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>Super Admin console - full visibility over every business, user and customer.</summary>
[Authorize(Roles = Roles.SuperAdmin)]
[Route("api/admin")]
public class AdminController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly ICustomerInsightService _insight;

    public AdminController(AppDbContext db, ICurrentUser me, IBookkeepingService books,
                           ICustomerInsightService insight)
    {
        _db = db; _me = me; _books = books; _insight = insight;
    }

    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard(CancellationToken ct)
    {
        var live = _db.Invoices.AsNoTracking().Where(i => i.Status != InvoiceStatus.Cancelled);

        return Ok(new AdminDashboardDto
        {
            BusinessCount       = await _db.Businesses.CountAsync(ct),
            ActiveBusinessCount = await _db.Businesses.CountAsync(b => b.IsActive, ct),
            BusinessUserCount   = await _db.Users.CountAsync(u => u.Role == Roles.BusinessUser, ct),
            CustomerUserCount   = await _db.Users.CountAsync(u => u.Role == Roles.Customer, ct),
            InvoiceCount        = await live.CountAsync(ct),
            TotalSales          = await live.SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
            TotalReceivable     = await _db.Customers.SumAsync(c => (decimal?)c.OutstandingBalance, ct) ?? 0,
            TotalCreditIssued   = await _db.CreditGrants.SumAsync(g => (decimal?)g.Amount, ct) ?? 0,
            TotalCreditUnclaimed= await _db.CreditGrants
                                          .Where(g => g.Status == CreditStatus.Active ||
                                                      g.Status == CreditStatus.PartiallyClaimed)
                                          .SumAsync(g => (decimal?)g.BalanceAmount, ct) ?? 0,
            WhatsAppSent        = await _db.WhatsAppMessages.CountAsync(m => m.Status == "Sent", ct),
            WhatsAppFailed      = await _db.WhatsAppMessages.CountAsync(m => m.Status == "Failed", ct)
        });
    }

    [HttpGet("businesses")]
    public async Task<IActionResult> Businesses([FromQuery] string? search,
                                                [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                                CancellationToken ct = default)
    {
        var q = _db.Businesses.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(b => b.Name.Contains(search) || b.Mobile.Contains(search));

        var total = await q.CountAsync(ct);
        var rows = await q.OrderBy(b => b.Name).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        var items = new List<AdminBusinessDto>();
        foreach (var b in rows)
        {
            var ownerId = await _db.Users.Where(u => u.BusinessId == b.Id && u.Role == Roles.BusinessUser)
                                         .Select(u => u.Id).FirstOrDefaultAsync(ct);

            items.Add(new AdminBusinessDto
            {
                Id = b.Id, Name = b.Name, OwnerName = b.OwnerName, Mobile = b.Mobile,
                City = b.City, IsActive = b.IsActive, CreatedAt = b.CreatedAt,
                OwnerUserId = ownerId,
                BusinessType = b.BusinessType,
                LogoUrl = BrandingUrl(b, "logo"),
                WorkerCount = await _db.Workers.CountAsync(w => w.BusinessId == b.Id && w.IsActive, ct),
                CustomerCount = await _db.Customers.CountAsync(c => c.BusinessId == b.Id && c.IsActive, ct),
                InvoiceCount  = await _db.Invoices.CountAsync(i => i.BusinessId == b.Id &&
                                                                   i.Status != InvoiceStatus.Cancelled, ct),
                TotalSales    = await _db.Invoices.Where(i => i.BusinessId == b.Id &&
                                                              i.Status != InvoiceStatus.Cancelled)
                                                  .SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
                Receivable    = await _db.Customers.Where(c => c.BusinessId == b.Id)
                                                   .SumAsync(c => (decimal?)c.OutstandingBalance, ct) ?? 0
            });
        }

        return Ok(new PagedResult<AdminBusinessDto>
        {
            Items = items, Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpPost("businesses/{id:int}/toggle-active")]
    public async Task<IActionResult> ToggleBusiness(int id, CancellationToken ct)
    {
        var b = await _db.Businesses.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (b is null) return NotFoundMsg("Business not found.");

        b.IsActive = !b.IsActive;
        await _books.AuditAsync(b.Id, _me.UserId, "ToggleBusinessActive", "Business", b.Id,
                                $"IsActive={b.IsActive}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(b.IsActive, b.IsActive ? "Business activated." : "Business suspended.");
    }

    [HttpGet("users")]
    public async Task<IActionResult> Users([FromQuery] string? role, [FromQuery] string? search,
                                           [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                           CancellationToken ct = default)
    {
        var q = _db.Users.AsNoTracking().Include(u => u.Business).AsQueryable();
        if (!string.IsNullOrWhiteSpace(role))   q = q.Where(u => u.Role == role);
        if (!string.IsNullOrWhiteSpace(search)) q = q.Where(u => u.FullName.Contains(search) ||
                                                                 u.Mobile.Contains(search));

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(u => u.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<AdminUserDto>
        {
            Items = rows.Select(u => new AdminUserDto
            {
                Id = u.Id, Mobile = u.Mobile, FullName = u.FullName, Role = u.Role,
                BusinessId = u.BusinessId, BusinessName = u.Business?.Name,
                IsActive = u.IsActive, LastLoginAt = u.LastLoginAt, CreatedAt = u.CreatedAt
            }).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpPost("users/{id:int}/toggle-active")]
    public async Task<IActionResult> ToggleUser(int id, CancellationToken ct)
    {
        var u = await _db.Users.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (u is null) return NotFoundMsg("User not found.");
        if (u.Id == _me.UserId) return Fail("You cannot deactivate your own account.");

        u.IsActive = !u.IsActive;
        await _books.AuditAsync(u.BusinessId, _me.UserId, "ToggleUserActive", "AppUser", u.Id,
                                $"IsActive={u.IsActive}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(u.IsActive, u.IsActive ? "User activated." : "User deactivated.");
    }

    [HttpPost("users/{id:int}/reset-password")]
    public async Task<IActionResult> ResetPassword(int id, AdminResetPasswordRequest req, CancellationToken ct)
    {
        var u = await _db.Users.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (u is null) return NotFoundMsg("User not found.");

        u.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
        var active = await _db.RefreshTokens.Where(t => t.UserId == u.Id && t.RevokedAt == null).ToListAsync(ct);
        foreach (var t in active) t.RevokedAt = DateTime.UtcNow;

        await _books.AuditAsync(u.BusinessId, _me.UserId, "AdminResetPassword", "AppUser", u.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Password reset. The user must log in again.");
    }

    /// <summary>Every customer across every business.</summary>
    [HttpGet("customers")]
    public async Task<IActionResult> Customers([FromQuery] string? search, [FromQuery] int? businessId,
                                               [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                               CancellationToken ct = default)
    {
        var q = _db.Customers.AsNoTracking().AsQueryable();
        if (businessId is not null) q = q.Where(c => c.BusinessId == businessId);
        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(c => c.Name.Contains(search) || c.Mobile.Contains(search));

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(c => c.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<CustomerDto>
        {
            Items = rows.Select(ToDto).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpGet("whatsapp")]
    public async Task<IActionResult> WhatsAppLog([FromQuery] string? status, [FromQuery] int? businessId,
                                                 [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                                 CancellationToken ct = default)
    {
        var q = _db.WhatsAppMessages.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(m => m.Status == status);
        if (businessId is not null) q = q.Where(m => m.BusinessId == businessId);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(m => m.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        var bizNames = await _db.Businesses.AsNoTracking().ToDictionaryAsync(b => b.Id, b => b.Name, ct);

        return Ok(new PagedResult<WhatsAppMessageDto>
        {
            Items = rows.Select(m => new WhatsAppMessageDto
            {
                Id = m.Id, BusinessId = m.BusinessId,
                BusinessName = m.BusinessId is not null && bizNames.TryGetValue(m.BusinessId.Value, out var n) ? n : null,
                ToMobile = m.ToMobile, Template = m.Template, Body = m.Body, DeepLink = m.DeepLink,
                Status = m.Status, Provider = m.Provider, ErrorMessage = m.ErrorMessage,
                CreatedAt = m.CreatedAt, SentAt = m.SentAt
            }).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpGet("audit")]
    public async Task<IActionResult> Audit([FromQuery] int? businessId, [FromQuery] string? action,
                                           [FromQuery] int page = 1, [FromQuery] int pageSize = 50,
                                           CancellationToken ct = default)
    {
        var q = _db.AuditLogs.AsNoTracking().AsQueryable();
        if (businessId is not null) q = q.Where(a => a.BusinessId == businessId);
        if (!string.IsNullOrWhiteSpace(action)) q = q.Where(a => a.Action == action);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(a => a.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<AuditLog>
        {
            Items = rows, Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    // ------------------------------------------------------------------
    // Drill-downs
    // ------------------------------------------------------------------

    /// <summary>Everything about one shop-owner account: shop profile, address and customers.</summary>
    [HttpGet("users/{id:int}")]
    public async Task<IActionResult> UserDetail(int id, CancellationToken ct)
    {
        var user = await _db.Users.AsNoTracking().Include(u => u.Business)
                            .FirstOrDefaultAsync(u => u.Id == id, ct);
        if (user is null) return NotFoundMsg("Account not found.");

        var dto = new AdminUserDetailDto
        {
            Account = new AdminUserDto
            {
                Id = user.Id, Mobile = user.Mobile, FullName = user.FullName, Role = user.Role,
                BusinessId = user.BusinessId, BusinessName = user.Business?.Name,
                IsActive = user.IsActive, LastLoginAt = user.LastLoginAt, CreatedAt = user.CreatedAt
            }
        };

        // A customer account has no shop behind it; return the account alone.
        if (user.BusinessId is not { } bizId || user.Business is null)
            return Ok(dto);

        var b = user.Business;
        dto.Business = new AdminBusinessProfileDto
        {
            Id = b.Id, Name = b.Name, OwnerName = b.OwnerName, Mobile = b.Mobile, Email = b.Email,
            AddressLine = b.AddressLine, City = b.City, State = b.State, Pincode = b.Pincode,
            GstNumber = b.GstNumber, InvoicePrefix = b.InvoicePrefix, IsActive = b.IsActive,
            CreatedAt = b.CreatedAt,
            FullAddress = string.Join(", ",
                new[] { b.AddressLine, b.City, b.State, b.Pincode }
                    .Where(x => !string.IsNullOrWhiteSpace(x)))
        };

        var live = _db.Invoices.AsNoTracking()
                      .Where(i => i.BusinessId == bizId && i.Status != InvoiceStatus.Cancelled);

        dto.Stats = new AdminBusinessStatsDto
        {
            CustomerCount        = await _db.Customers.CountAsync(c => c.BusinessId == bizId && c.IsActive, ct),
            TrustedCustomerCount = await _db.Customers.CountAsync(c => c.BusinessId == bizId && c.IsActive && c.IsTrusted, ct),
            ProductCount         = await _db.Products.CountAsync(p => p.BusinessId == bizId && p.IsActive, ct),
            LowStockCount        = await _db.Products.CountAsync(p => p.BusinessId == bizId && p.IsActive && p.StockQty <= p.MinStockQty, ct),
            InvoiceCount         = await live.CountAsync(ct),
            TotalSales           = await live.SumAsync(i => (decimal?)i.GrandTotal, ct) ?? 0,
            TotalCollected       = await _db.Payments.Where(p => p.BusinessId == bizId).SumAsync(p => (decimal?)p.Amount, ct) ?? 0,
            Receivable           = await _db.Customers.Where(c => c.BusinessId == bizId).SumAsync(c => (decimal?)c.OutstandingBalance, ct) ?? 0,
            CreditIssued         = await _db.CreditGrants.Where(g => g.BusinessId == bizId).SumAsync(g => (decimal?)g.Amount, ct) ?? 0,
            CreditUnclaimed      = await _db.CreditGrants.Where(g => g.BusinessId == bizId &&
                                        (g.Status == CreditStatus.Active || g.Status == CreditStatus.PartiallyClaimed))
                                        .SumAsync(g => (decimal?)g.BalanceAmount, ct) ?? 0,
            PendingClaimCount    = await _db.CreditClaims.CountAsync(c => c.BusinessId == bizId && c.Status == ClaimStatus.Pending, ct),
            WhatsAppSent         = await _db.WhatsAppMessages.CountAsync(m => m.BusinessId == bizId && m.Status == "Sent", ct),
            LastInvoiceOn        = await live.OrderByDescending(i => i.InvoiceDate)
                                             .Select(i => (DateTime?)i.InvoiceDate).FirstOrDefaultAsync(ct),
            TotalExpenses        = await _db.Expenses.Where(e => e.BusinessId == bizId && !e.IsCancelled)
                                        .SumAsync(e => (decimal?)e.Amount, ct) ?? 0,
            TotalDiscount        = await live.SumAsync(i => (decimal?)i.DiscountAmount, ct) ?? 0,
            TotalTax             = await live.SumAsync(i => (decimal?)i.TaxAmount, ct) ?? 0
        };
        dto.Stats.NetAfterExpenses = dto.Stats.TotalSales - dto.Stats.TotalExpenses;

        var customers = await _db.Customers.AsNoTracking()
                                 .Where(c => c.BusinessId == bizId)
                                 .OrderByDescending(c => c.OutstandingBalance).ThenBy(c => c.Name)
                                 .Take(200).ToListAsync(ct);
        dto.Customers = customers.Select(ToDto).ToList();

        return Ok(dto);
    }

    /// <summary>One customer record in full: bills, payments, credits, ledger and messages.</summary>
    [HttpGet("customers/{id:int}")]
    public async Task<IActionResult> CustomerDetail(int id, CancellationToken ct)
    {
        var cust = await _db.Customers.AsNoTracking().Include(c => c.Business)
                            .FirstOrDefaultAsync(c => c.Id == id, ct);
        if (cust is null) return NotFoundMsg("Customer not found.");

        var dto = new AdminCustomerDetailDto
        {
            Customer       = ToDto(cust),
            BusinessName   = cust.Business?.Name ?? "",
            BusinessMobile = cust.Business?.Mobile ?? ""
        };

        if (cust.UserId is { } userId)
        {
            var u = await _db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == userId, ct);
            if (u is not null)
                dto.Account = new AdminUserDto
                {
                    Id = u.Id, Mobile = u.Mobile, FullName = u.FullName, Role = u.Role,
                    IsActive = u.IsActive, LastLoginAt = u.LastLoginAt, CreatedAt = u.CreatedAt
                };
        }

        dto.Insight = LookupController.ToDto(
            await _insight.LookupAsync(cust.Mobile, cust.BusinessId, ct));

        // Admin may see the other shops by name - that is the point of the console.
        var siblings = await _db.Customers.AsNoTracking().Include(c => c.Business)
                                .Where(c => c.Mobile == cust.Mobile && c.Id != cust.Id)
                                .ToListAsync(ct);
        dto.OtherShops = siblings.Select(s => new CustomerShopSummaryDto
        {
            CustomerId = s.Id, BusinessId = s.BusinessId,
            BusinessName = s.Business?.Name ?? "", BusinessMobile = s.Business?.Mobile ?? "",
            Outstanding = s.OutstandingBalance, CreditAvailable = s.CreditBalance,
            IsTrusted = s.IsTrusted
        }).ToList();

        var bills = await _db.Invoices.AsNoTracking()
                             .Include(i => i.Items).Include(i => i.Business)
                             .Where(i => i.CustomerId == id)
                             .OrderByDescending(i => i.Id).Take(100).ToListAsync(ct);
        dto.Bills = bills.Select(i => ToDto(i, i.Business, cust)).ToList();

        dto.Payments = await _db.Payments.AsNoTracking()
                                .Where(p => p.CustomerId == id)
                                .OrderByDescending(p => p.Id).Take(100)
                                .Select(p => new PaymentDto
                                {
                                    Id = p.Id, ReceiptNumber = p.ReceiptNumber, CustomerId = p.CustomerId,
                                    CustomerName = cust.Name, InvoiceId = p.InvoiceId, Amount = p.Amount,
                                    Mode = p.Mode, ReferenceNo = p.ReferenceNo, PaidOn = p.PaidOn,
                                    OutstandingAfter = cust.OutstandingBalance
                                }).ToListAsync(ct);

        var grants = await _db.CreditGrants.AsNoTracking().Include(g => g.Business)
                              .Where(g => g.CustomerId == id)
                              .OrderByDescending(g => g.Id).ToListAsync(ct);
        dto.Credits = grants.Select(g => ToDto(g, g.Business, cust)).ToList();

        var claims = await _db.CreditClaims.AsNoTracking()
                              .Include(c => c.CreditGrant).Include(c => c.Business)
                              .Where(c => c.CustomerId == id)
                              .OrderByDescending(c => c.Id).ToListAsync(ct);
        dto.Claims = claims.Select(c => ToDto(c, c.CreditGrant, c.Business, cust)).ToList();

        dto.Ledger = await _db.LedgerEntries.AsNoTracking()
                              .Where(l => l.CustomerId == id)
                              .OrderByDescending(l => l.Id).Take(100)
                              .Select(l => new LedgerEntryDto
                              {
                                  Id = l.Id, EntryDate = l.EntryDate, RefType = l.RefType, RefId = l.RefId,
                                  Description = l.Description, Debit = l.Debit, Credit = l.Credit,
                                  RunningBalance = l.RunningBalance
                              }).ToListAsync(ct);

        dto.Messages = await _db.WhatsAppMessages.AsNoTracking()
                                .Where(m => m.CustomerId == id)
                                .OrderByDescending(m => m.Id).Take(50)
                                .Select(m => new WhatsAppMessageDto
                                {
                                    Id = m.Id, BusinessId = m.BusinessId, ToMobile = m.ToMobile,
                                    Template = m.Template, Body = m.Body, DeepLink = m.DeepLink,
                                    Status = m.Status, Provider = m.Provider, ErrorMessage = m.ErrorMessage,
                                    CreatedAt = m.CreatedAt, SentAt = m.SentAt
                                }).ToListAsync(ct);

        return Ok(dto);
    }
}
