using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>Money the shop collects from a customer against their Udhaar / bills.</summary>
[Authorize(Roles = Roles.BusinessUser + "," + Roles.SuperAdmin)]
public class PaymentsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _wa;

    public PaymentsController(AppDbContext db, ICurrentUser me, IBookkeepingService books, IWhatsAppService wa)
    {
        _db = db; _me = me; _books = books; _wa = wa;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] int? customerId, [FromQuery] DateTime? from,
                                          [FromQuery] DateTime? to, [FromQuery] int? businessId,
                                          [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        var q = _db.Payments.AsNoTracking().Include(p => p.Customer).AsQueryable();
        if (bizId is not null) q = q.Where(p => p.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        if (customerId is not null) q = q.Where(p => p.CustomerId == customerId);
        if (from is not null) q = q.Where(p => p.PaidOn >= from);
        if (to is not null)   q = q.Where(p => p.PaidOn <= to);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(p => p.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize)
                          .ToListAsync(ct);

        return Ok(new PagedResult<PaymentDto>
        {
            Items = rows.Select(p => new PaymentDto
            {
                Id = p.Id, ReceiptNumber = p.ReceiptNumber, CustomerId = p.CustomerId,
                CustomerName = p.Customer?.Name ?? "", InvoiceId = p.InvoiceId, Amount = p.Amount,
                Mode = p.Mode, ReferenceNo = p.ReferenceNo, PaidOn = p.PaidOn,
                OutstandingAfter = p.Customer?.OutstandingBalance ?? 0
            }).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpPost]
    public async Task<IActionResult> Record(RecordPaymentRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var biz  = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == bizId, ct);
        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == req.CustomerId && c.BusinessId == bizId, ct);
        if (biz is null)  return NotFoundMsg("Business not found.");
        if (cust is null) return NotFoundMsg("Customer not found in this business.");

        if (req.Mode == "Card" && InvoicesController.ValidateCard(req.Card) is { } cardProblem)
            return Fail(cardProblem);

        if (req.Amount > cust.OutstandingBalance)
            return Fail($"Payment exceeds the outstanding amount of Rs.{cust.OutstandingBalance:N2}.");

        Invoice? inv = null;
        if (req.InvoiceId is not null)
        {
            inv = await _db.Invoices.FirstOrDefaultAsync(i => i.Id == req.InvoiceId && i.BusinessId == bizId, ct);
            if (inv is null) return NotFoundMsg("Bill not found in this business.");
            if (inv.CustomerId != cust.Id) return Fail("That bill belongs to a different customer.");
            if (req.Amount > inv.BalanceAmount)
                return Fail($"Payment exceeds the bill balance of Rs.{inv.BalanceAmount:N2}.");
        }

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var pay = new Payment
        {
            BusinessId      = bizId.Value,
            CustomerId      = cust.Id,
            InvoiceId       = inv?.Id,
            ReceiptNumber   = await _books.NextReceiptNumberAsync(bizId.Value, ct),
            Amount          = req.Amount,
            Mode            = req.Mode,
            ReferenceNo     = req.ReferenceNo,
            Note            = req.Note,
            PaidOn          = DateTime.UtcNow,
            CreatedByUserId = _me.UserId
        };
        if (req.Mode == "Card") InvoicesController.ApplyCard(pay, req.Card);
        _db.Payments.Add(pay);
        await _db.SaveChangesAsync(ct);

        cust.OutstandingBalance = Math.Max(0, cust.OutstandingBalance - req.Amount);

        if (inv is not null)
        {
            inv.PaidAmount    += req.Amount;
            inv.BalanceAmount  = Math.Max(0, inv.GrandTotal - inv.PaidAmount);
            inv.Status         = inv.BalanceAmount <= 0 ? InvoiceStatus.Paid : InvoiceStatus.PartiallyPaid;
        }
        else
        {
            // Not against a named bill, so spread it over the oldest ones. Keeps the
            // customer's outstanding equal to the sum of their unpaid bill balances.
            await _books.AllocateToOldestUnpaidAsync(cust.Id, req.Amount, ct);
        }

        await _books.PostAsync(bizId.Value, cust.Id, "Payment", pay.Id,
                               $"Payment {pay.ReceiptNumber}" + (inv is null ? "" : $" against {inv.InvoiceNumber}"),
                               0, req.Amount, ct);
        await _books.AuditAsync(bizId, _me.UserId, "RecordPayment", "Payment", pay.Id,
                                $"{pay.ReceiptNumber} amount={req.Amount}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        if (req.SendWhatsApp)
            await _wa.SendAsync("PaymentReceipt", cust.Mobile,
                                MessageTemplates.PaymentReceipt(biz, cust, pay), biz.Id, cust.Id, ct);

        return Ok(new PaymentDto
        {
            Id = pay.Id, ReceiptNumber = pay.ReceiptNumber, CustomerId = cust.Id, CustomerName = cust.Name,
            InvoiceId = pay.InvoiceId, Amount = pay.Amount, Mode = pay.Mode, ReferenceNo = pay.ReferenceNo,
            PaidOn = pay.PaidOn, OutstandingAfter = cust.OutstandingBalance,
            CardScope = pay.CardScope, CardNetwork = pay.CardNetwork, CardLast4 = pay.CardLast4
        }, "Payment recorded.");
    }
}
