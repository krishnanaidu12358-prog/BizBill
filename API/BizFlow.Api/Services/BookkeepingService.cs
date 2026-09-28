using BizFlow.Api.Data;
using BizFlow.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Services;

/// <summary>
/// Shared money/ledger plumbing used by invoices, payments and credits.
/// Ledger convention: Debit increases what the customer owes, Credit reduces it.
/// </summary>
public interface IBookkeepingService
{
    Task<string> NextInvoiceNumberAsync(int businessId, CancellationToken ct = default);
    Task<string> NextReceiptNumberAsync(int businessId, CancellationToken ct = default);
    Task<string> NextCreditCodeAsync(int businessId, CancellationToken ct = default);

    Task<LedgerEntry> PostAsync(int businessId, int customerId, string refType, int? refId,
                                string description, decimal debit, decimal credit,
                                CancellationToken ct = default);

    Task AuditAsync(int? businessId, int? userId, string action, string? entityName,
                    int? entityId, string? details, string? ip, CancellationToken ct = default);

    /// <summary>
    /// Spreads an amount that is not tied to one bill across the customer's unpaid
    /// invoices, oldest first. Without this the customer's outstanding and the sum
    /// of their unpaid bills drift apart and the statement stops adding up.
    /// Returns how much was actually allocated.
    /// </summary>
    Task<decimal> AllocateToOldestUnpaidAsync(int customerId, decimal amount,
                                              CancellationToken ct = default);
}

public class BookkeepingService : IBookkeepingService
{
    private readonly AppDbContext _db;

    public BookkeepingService(AppDbContext db) => _db = db;

    public async Task<string> NextInvoiceNumberAsync(int businessId, CancellationToken ct = default)
    {
        var prefix = await _db.Businesses.Where(x => x.Id == businessId)
                                         .Select(x => x.InvoicePrefix)
                                         .FirstOrDefaultAsync(ct) ?? "INV";
        var seq = await _db.Invoices.CountAsync(x => x.BusinessId == businessId, ct) + 1;
        var candidate = $"{prefix}-{businessId:D3}-{seq:D5}";

        // Defensive: skip numbers already taken (e.g. after a cancelled/deleted row).
        while (await _db.Invoices.AnyAsync(x => x.BusinessId == businessId && x.InvoiceNumber == candidate, ct))
            candidate = $"{prefix}-{businessId:D3}-{++seq:D5}";

        return candidate;
    }

    public async Task<string> NextReceiptNumberAsync(int businessId, CancellationToken ct = default)
    {
        var seq = await _db.Payments.CountAsync(x => x.BusinessId == businessId, ct) + 1;
        var candidate = $"RCP-{businessId:D3}-{seq:D5}";
        while (await _db.Payments.AnyAsync(x => x.BusinessId == businessId && x.ReceiptNumber == candidate, ct))
            candidate = $"RCP-{businessId:D3}-{++seq:D5}";
        return candidate;
    }

    public async Task<string> NextCreditCodeAsync(int businessId, CancellationToken ct = default)
    {
        var seq = await _db.CreditGrants.CountAsync(x => x.BusinessId == businessId, ct) + 1;
        var candidate = $"CR-{businessId:D3}-{seq:D5}";
        while (await _db.CreditGrants.AnyAsync(x => x.CreditCode == candidate, ct))
            candidate = $"CR-{businessId:D3}-{++seq:D5}";
        return candidate;
    }

    public async Task<LedgerEntry> PostAsync(int businessId, int customerId, string refType, int? refId,
                                             string description, decimal debit, decimal credit,
                                             CancellationToken ct = default)
    {
        var last = await _db.LedgerEntries
                            .Where(x => x.CustomerId == customerId)
                            .OrderByDescending(x => x.Id)
                            .Select(x => (decimal?)x.RunningBalance)
                            .FirstOrDefaultAsync(ct) ?? 0m;

        var entry = new LedgerEntry
        {
            BusinessId     = businessId,
            CustomerId     = customerId,
            EntryDate      = DateTime.UtcNow,
            RefType        = refType,
            RefId          = refId,
            Description    = description.Length > 250 ? description[..250] : description,
            Debit          = debit,
            Credit         = credit,
            RunningBalance = last + debit - credit
        };
        _db.LedgerEntries.Add(entry);
        return entry;
    }

    public async Task<decimal> AllocateToOldestUnpaidAsync(int customerId, decimal amount,
                                                           CancellationToken ct = default)
    {
        if (amount <= 0) return 0;

        var unpaid = await _db.Invoices
                              .Where(i => i.CustomerId == customerId &&
                                          i.BalanceAmount > 0 &&
                                          i.Status != InvoiceStatus.Cancelled)
                              .OrderBy(i => i.InvoiceDate).ThenBy(i => i.Id)
                              .ToListAsync(ct);

        var left = amount;
        foreach (var inv in unpaid)
        {
            if (left <= 0) break;

            var take = Math.Min(left, inv.BalanceAmount);
            inv.PaidAmount    += take;
            inv.BalanceAmount  = decimal.Round(Math.Max(0, inv.GrandTotal - inv.PaidAmount), 2);
            inv.Status         = inv.BalanceAmount <= 0
                ? InvoiceStatus.Paid
                : InvoiceStatus.PartiallyPaid;
            left -= take;
        }

        return amount - left;
    }

    public Task AuditAsync(int? businessId, int? userId, string action, string? entityName,
                           int? entityId, string? details, string? ip, CancellationToken ct = default)
    {
        _db.AuditLogs.Add(new AuditLog
        {
            BusinessId = businessId,
            UserId     = userId,
            Action     = action,
            EntityName = entityName,
            EntityId   = entityId,
            Details    = details,
            IpAddress  = ip
        });
        return Task.CompletedTask;
    }
}
