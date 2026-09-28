using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// The shop owner's side of UPI screenshots: see what customers have sent,
/// look at the image, and approve or reject. Approving records the payment
/// and re-issues the bill with the remaining amount.
/// </summary>
[Authorize(Roles = Roles.BusinessUser + "," + Roles.SuperAdmin)]
[Route("api/payment-proofs")]
public class PaymentProofsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _wa;
    private readonly IFileStorageService _files;

    public PaymentProofsController(AppDbContext db, ICurrentUser me, IBookkeepingService books,
                                   IWhatsAppService wa, IFileStorageService files)
    {
        _db = db; _me = me; _books = books; _wa = wa; _files = files;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? status, [FromQuery] int? customerId,
                                          [FromQuery] int? businessId,
                                          [FromQuery] int page = 1, [FromQuery] int pageSize = 50,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        var q = _db.PaymentProofs.AsNoTracking()
                   .Include(p => p.Customer).Include(p => p.Business).Include(p => p.Invoice)
                   .AsQueryable();

        if (bizId is not null) q = q.Where(p => p.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(p => p.Status == status);
        if (customerId is not null) q = q.Where(p => p.CustomerId == customerId);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(p => p.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<PaymentProofDto>
        {
            Items = rows.Select(p => ToDto(p)).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    /// <summary>Serves the screenshot. Only the shop that received it, or an admin, may look.</summary>
    [HttpGet("{id:int}/image")]
    public async Task<IActionResult> Image(int id, CancellationToken ct)
    {
        var proof = await _db.PaymentProofs.AsNoTracking().FirstOrDefaultAsync(p => p.Id == id, ct);
        if (proof is null) return NotFoundMsg("Payment proof not found.");
        if (!CanTouch(proof.BusinessId)) return Forbidden();

        var path = _files.ResolvePath(proof.StoredPath);
        if (path is null) return NotFoundMsg("The screenshot is no longer available.");

        return PhysicalFile(path, proof.ContentType ?? "application/octet-stream");
    }

    /// <summary>
    /// Approve or reject. Approving books the money, updates the bill and the
    /// customer's Udhaar, and sends the customer the updated bill.
    /// </summary>
    [HttpPost("{id:int}/process")]
    public async Task<IActionResult> Process(int id, ProcessProofRequest req, CancellationToken ct)
    {
        var proof = await _db.PaymentProofs.FirstOrDefaultAsync(p => p.Id == id, ct);
        if (proof is null) return NotFoundMsg("Payment proof not found.");
        if (!CanTouch(proof.BusinessId)) return Forbidden();
        if (proof.Status != ProofStatus.Pending)
            return Fail($"This proof was already {proof.Status.ToLowerInvariant()}.");

        var biz  = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == proof.BusinessId, ct);
        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == proof.CustomerId, ct);
        if (biz is null || cust is null) return NotFoundMsg("Payment record is incomplete.");

        proof.ProcessedAt       = DateTime.UtcNow;
        proof.ProcessedByUserId = _me.UserId;
        proof.Remarks           = req.Remarks;

        // ------------------------------------------------------- rejected
        if (!req.Approve)
        {
            proof.Status = ProofStatus.Rejected;
            await _books.AuditAsync(biz.Id, _me.UserId, "RejectPaymentProof", "PaymentProof",
                                    proof.Id, req.Remarks, ClientIp, ct);
            await _db.SaveChangesAsync(ct);

            await _wa.SendAsync("ProofRejected", cust.Mobile,
                                MessageTemplates.ProofRejected(biz, cust, proof.Amount, req.Remarks),
                                biz.Id, cust.Id, ct);

            return Ok(new ProofApprovalResultDto
            {
                Proof = ToDto(proof, biz, cust),
                CustomerOutstanding = cust.OutstandingBalance
            }, "Payment rejected and the customer has been told.");
        }

        // ------------------------------------------------------- approved
        if (proof.Amount > cust.OutstandingBalance)
            return Fail($"This payment of Rs.{proof.Amount:N2} is more than the customer owes "
                      + $"(Rs.{cust.OutstandingBalance:N2}). Reject it or ask them to re-send the right amount.");

        Invoice? inv = null;
        if (proof.InvoiceId is not null)
        {
            inv = await _db.Invoices.Include(i => i.Items)
                           .FirstOrDefaultAsync(i => i.Id == proof.InvoiceId, ct);
            if (inv is not null && proof.Amount > inv.BalanceAmount)
                return Fail($"That bill only has Rs.{inv.BalanceAmount:N2} left to pay.");
        }

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var pay = new Payment
        {
            BusinessId      = biz.Id,
            CustomerId      = cust.Id,
            InvoiceId       = inv?.Id,
            ReceiptNumber   = await _books.NextReceiptNumberAsync(biz.Id, ct),
            Amount          = proof.Amount,
            Mode            = proof.Method,
            ReferenceNo     = proof.ReferenceNo,
            Note            = $"UPI screenshot approved (proof #{proof.Id})",
            PaidOn          = DateTime.UtcNow,
            CreatedByUserId = _me.UserId
        };
        _db.Payments.Add(pay);
        await _db.SaveChangesAsync(ct);

        cust.OutstandingBalance = Math.Max(0, cust.OutstandingBalance - proof.Amount);

        if (inv is not null)
        {
            inv.PaidAmount    += proof.Amount;
            inv.BalanceAmount  = Math.Max(0, inv.GrandTotal - inv.PaidAmount);
            inv.Status         = inv.BalanceAmount <= 0 ? InvoiceStatus.Paid : InvoiceStatus.PartiallyPaid;
        }
        else
        {
            await _books.AllocateToOldestUnpaidAsync(cust.Id, proof.Amount, ct);
        }

        proof.Status    = ProofStatus.Approved;
        proof.PaymentId = pay.Id;

        await _books.PostAsync(biz.Id, cust.Id, "Payment", pay.Id,
                               $"UPI payment {pay.ReceiptNumber}"
                             + (inv is null ? "" : $" against {inv.InvoiceNumber}"),
                               0, proof.Amount, ct);
        await _books.AuditAsync(biz.Id, _me.UserId, "ApprovePaymentProof", "PaymentProof", proof.Id,
                                $"amount={proof.Amount} receipt={pay.ReceiptNumber}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        // ------- re-issue the bill so the customer sees what is still owed -------
        string? waLink = null;
        if (req.SendWhatsApp)
        {
            string body;
            if (inv is not null)
            {
                body = MessageTemplates.ReIssuedBill(biz, cust, inv, proof.Amount);
            }
            else
            {
                // Not tied to one bill, so send the whole running account instead.
                var unpaid = await UnpaidBillsAsync(cust.Id, ct);
                body = MessageTemplates.Statement(biz, cust, unpaid);
            }

            var msg = await _wa.SendAsync("ReIssuedBill", cust.Mobile, body, biz.Id, cust.Id, ct);
            waLink = msg.DeepLink;
        }

        return Ok(new ProofApprovalResultDto
        {
            Proof = ToDto(proof, biz, cust, inv),
            Payment = new PaymentDto
            {
                Id = pay.Id, ReceiptNumber = pay.ReceiptNumber, CustomerId = cust.Id,
                CustomerName = cust.Name, InvoiceId = pay.InvoiceId, Amount = pay.Amount,
                Mode = pay.Mode, ReferenceNo = pay.ReferenceNo, PaidOn = pay.PaidOn,
                OutstandingAfter = cust.OutstandingBalance
            },
            ReIssuedInvoice = inv is null ? null : ToDto(inv, biz, cust, waLink),
            RemainingOnInvoice = inv?.BalanceAmount ?? 0,
            CustomerOutstanding = cust.OutstandingBalance,
            WhatsAppLink = waLink
        }, inv is null
            ? $"Payment of Rs.{proof.Amount:N2} approved. Statement sent to the customer."
            : $"Payment approved. Rs.{inv.BalanceAmount:N2} remaining on {inv.InvoiceNumber}, "
            + "updated bill sent to the customer.");
    }

    private async Task<List<Invoice>> UnpaidBillsAsync(int customerId, CancellationToken ct) =>
        await _db.Invoices.AsNoTracking().Include(i => i.Items)
                 .Where(i => i.CustomerId == customerId &&
                             i.BalanceAmount > 0 &&
                             i.Status != InvoiceStatus.Cancelled)
                 .OrderBy(i => i.InvoiceDate)
                 .ToListAsync(ct);

    private bool CanTouch(int businessId) => _me.IsSuperAdmin || _me.BusinessId == businessId;

    internal static PaymentProofDto ToDto(PaymentProof p, Business? biz = null,
                                          Customer? cust = null, Invoice? inv = null) => new()
    {
        Id = p.Id,
        BusinessId = p.BusinessId,
        BusinessName = (biz ?? p.Business)?.Name ?? "",
        CustomerId = p.CustomerId,
        CustomerName = (cust ?? p.Customer)?.Name ?? "",
        CustomerMobile = (cust ?? p.Customer)?.Mobile ?? "",
        InvoiceId = p.InvoiceId,
        InvoiceNumber = (inv ?? p.Invoice)?.InvoiceNumber,
        Amount = p.Amount,
        Method = p.Method,
        ReferenceNo = p.ReferenceNo,
        Note = p.Note,
        HasScreenshot = !string.IsNullOrWhiteSpace(p.StoredPath),
        Status = p.Status,
        Remarks = p.Remarks,
        SubmittedAt = p.SubmittedAt,
        ProcessedAt = p.ProcessedAt,
        InvoiceBalance = (inv ?? p.Invoice)?.BalanceAmount ?? 0,
        CustomerOutstanding = (cust ?? p.Customer)?.OutstandingBalance ?? 0
    };
}
