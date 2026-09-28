using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>What a shop spends. Feeds the owner's net figure and the Super Admin expenditure charts.</summary>
[Authorize(Roles = Roles.BusinessUser + "," + Roles.SuperAdmin)]
public class ExpensesController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;

    public ExpensesController(AppDbContext db, ICurrentUser me, IBookkeepingService books)
    {
        _db = db; _me = me; _books = books;
    }

    [HttpGet("categories")]
    public IActionResult Categories() => Ok(ExpenseCategories.All);

    /// <summary>Expenses in a date range with a per-category total. Defaults to this month.</summary>
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                          [FromQuery] string? category, [FromQuery] int? businessId,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null && !_me.IsSuperAdmin) return Forbidden();

        var now   = DateTime.UtcNow;
        var start = from ?? new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
        var end   = to ?? now.AddDays(1);

        var q = _db.Expenses.AsNoTracking().Include(e => e.Business)
                   .Where(e => !e.IsCancelled && e.ExpenseDate >= start && e.ExpenseDate < end);
        if (bizId is not null) q = q.Where(e => e.BusinessId == bizId);
        if (!string.IsNullOrWhiteSpace(category)) q = q.Where(e => e.Category == category);

        var rows = await q.OrderByDescending(e => e.ExpenseDate).ThenByDescending(e => e.Id)
                          .Take(500).ToListAsync(ct);

        return Ok(new ExpenseSummaryDto
        {
            Total = rows.Sum(e => e.Amount),
            Count = rows.Count,
            ByCategory = rows.GroupBy(e => e.Category)
                             .Select(g => new NamedAmountDto { Name = g.Key, Amount = g.Sum(x => x.Amount), Count = g.Count() })
                             .OrderByDescending(x => x.Amount).ToList(),
            Items = rows.Select(ToDto).ToList()
        });
    }

    [HttpPost]
    public async Task<IActionResult> Create(CreateExpenseRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        // The shop owner records their own spending; the Super Admin can record it
        // for any shop they have opened (?businessId=), like every other owner screen.
        if (_me.Role is not (Roles.BusinessUser or Roles.SuperAdmin) ||
            ResolveBusinessId(_me, businessId) is not { } bizId)
            return Forbidden("Open a shop first, then record its expense.");

        var date = req.ExpenseDate?.ToUniversalTime() ?? DateTime.UtcNow;
        if (date > DateTime.UtcNow.AddDays(1)) return Fail("An expense cannot be dated in the future.");

        var e = new Expense
        {
            BusinessId      = bizId,
            Category        = req.Category.Trim(),
            Amount          = decimal.Round(req.Amount, 2),
            ExpenseDate     = date,
            PaymentMode     = string.IsNullOrWhiteSpace(req.PaymentMode) ? "Cash" : req.PaymentMode.Trim(),
            PaidTo          = string.IsNullOrWhiteSpace(req.PaidTo) ? null : req.PaidTo.Trim(),
            Note            = string.IsNullOrWhiteSpace(req.Note) ? null : req.Note.Trim(),
            CreatedByUserId = _me.UserId
        };
        _db.Expenses.Add(e);
        await _db.SaveChangesAsync(ct);

        await _books.AuditAsync(bizId, _me.UserId, "CreateExpense", "Expense", e.Id,
                                $"{e.Category} Rs.{e.Amount}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(ToDto(e), $"Expense of Rs.{e.Amount:N2} saved.");
    }

    /// <summary>Cancels (never deletes) an expense entered by mistake.</summary>
    [HttpPost("{id:int}/cancel")]
    public async Task<IActionResult> Cancel(int id, CancellationToken ct)
    {
        var e = await _db.Expenses.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (e is null) return NotFoundMsg("Expense not found.");
        if (!_me.IsSuperAdmin && _me.BusinessId != e.BusinessId) return Forbidden();
        if (e.IsCancelled) return Fail("This expense is already cancelled.");

        e.IsCancelled = true;
        await _books.AuditAsync(e.BusinessId, _me.UserId, "CancelExpense", "Expense", e.Id,
                                $"{e.Category} Rs.{e.Amount}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Expense cancelled.");
    }

    private static ExpenseDto ToDto(Expense e) => new()
    {
        Id = e.Id, BusinessId = e.BusinessId, BusinessName = e.Business?.Name ?? "",
        Category = e.Category, Amount = e.Amount, ExpenseDate = e.ExpenseDate,
        PaymentMode = e.PaymentMode, PaidTo = e.PaidTo, Note = e.Note,
        IsCancelled = e.IsCancelled, CreatedAt = e.CreatedAt
    };
}
