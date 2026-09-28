using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// The customer-facing side of the app. A customer sees every shop that bills their
/// mobile number, their bills, their outstanding Udhaar, and the credits they can claim.
/// </summary>
[Authorize(Roles = Roles.Customer)]
[Route("api/my")]
public class MyAccountController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _wa;
    private readonly IFileStorageService _files;

    public MyAccountController(AppDbContext db, ICurrentUser me, IBookkeepingService books,
                               IWhatsAppService wa, IFileStorageService files)
    {
        _db = db; _me = me; _books = books; _wa = wa; _files = files;
    }

    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard(CancellationToken ct)
    {
        var mine = await MyCustomerRowsAsync(ct);
        var ids  = mine.Select(c => c.Id).ToList();

        var user = await _db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == _me.UserId, ct);
        var billCount = await _db.Invoices.CountAsync(i => ids.Contains(i.CustomerId) &&
                                                           i.Status != InvoiceStatus.Cancelled, ct);

        var shops = new List<CustomerShopSummaryDto>();
        foreach (var c in mine)
        {
            var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == c.BusinessId, ct);
            shops.Add(new CustomerShopSummaryDto
            {
                CustomerId      = c.Id,
                BusinessId      = c.BusinessId,
                BusinessName    = biz?.Name ?? "",
                BusinessMobile  = biz?.Mobile ?? "",
                Outstanding     = c.OutstandingBalance,
                CreditAvailable = c.CreditBalance,
                IsTrusted       = c.IsTrusted
            });
        }

        return Ok(new CustomerDashboardDto
        {
            FullName             = user?.FullName ?? "",
            Mobile               = _me.Mobile,
            TotalOutstanding     = mine.Sum(c => c.OutstandingBalance),
            TotalCreditAvailable = mine.Sum(c => c.CreditBalance),
            BillCount            = billCount,
            ShopCount            = mine.Count,
            Shops                = shops.OrderByDescending(s => s.Outstanding).ToList()
        });
    }

    [HttpGet("shops")]
    public async Task<IActionResult> Shops(CancellationToken ct)
    {
        var mine = await MyCustomerRowsAsync(ct);
        return Ok(mine.Select(ToDto).ToList());
    }

    /// <summary>
    /// The shop's UPI details so the customer can pay straight from their UPI app
    /// (and see the shop's QR). Only for shops the customer actually buys from.
    /// </summary>
    [HttpGet("shops/{businessId:int}/upi")]
    public async Task<IActionResult> ShopUpi(int businessId, CancellationToken ct)
    {
        var mine = await MyCustomerRowsAsync(ct);
        var cust = mine.FirstOrDefault(c => c.BusinessId == businessId);
        if (cust is null) return Fail("You are not a customer of that shop.");

        var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == businessId, ct);
        if (biz is null) return NotFoundMsg("Shop not found.");

        return Ok(new ShopUpiDto
        {
            BusinessId   = biz.Id,
            BusinessName = biz.Name,
            UpiId        = biz.UpiId,
            UpiName      = string.IsNullOrWhiteSpace(biz.UpiName) ? biz.Name : biz.UpiName,
            Outstanding  = cust.OutstandingBalance
        });
    }

    [HttpGet("bills")]
    public async Task<IActionResult> Bills([FromQuery] int? businessId, [FromQuery] bool? unpaidOnly,
                                           [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                           CancellationToken ct = default)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var q = _db.Invoices.AsNoTracking().Include(i => i.Customer).Include(i => i.Business)
                            .Where(i => ids.Contains(i.CustomerId));

        if (businessId is not null) q = q.Where(i => i.BusinessId == businessId);
        if (unpaidOnly == true)     q = q.Where(i => i.BalanceAmount > 0 && i.Status != InvoiceStatus.Cancelled);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(i => i.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<InvoiceDto>
        {
            Items = rows.Select(i => ToDto(i, i.Business, i.Customer)).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpGet("bills/{id:int}")]
    public async Task<IActionResult> Bill(int id, CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var inv = await _db.Invoices.AsNoTracking()
                           .Include(i => i.Items).Include(i => i.Customer).Include(i => i.Business)
                           .FirstOrDefaultAsync(i => i.Id == id && ids.Contains(i.CustomerId), ct);
        if (inv is null) return NotFoundMsg("Bill not found on your account.");
        return Ok(ToDto(inv, inv.Business, inv.Customer));
    }

    [HttpGet("payments")]
    public async Task<IActionResult> Payments([FromQuery] int? businessId, CancellationToken ct)
    {
        var mine = await MyCustomerRowsAsync(ct);
        var ids  = mine.Select(c => c.Id).ToList();
        var names = mine.ToDictionary(c => c.Id, c => c.Name);

        var q = _db.Payments.AsNoTracking().Where(p => ids.Contains(p.CustomerId));
        if (businessId is not null) q = q.Where(p => p.BusinessId == businessId);

        var rows = await q.OrderByDescending(p => p.Id).Take(200).ToListAsync(ct);

        var shopNames = await _db.Businesses.AsNoTracking()
                                 .ToDictionaryAsync(b => b.Id, b => b.Name, ct);

        return Ok(rows.Select(p => new PaymentDto
        {
            Id = p.Id,
            ReceiptNumber = p.ReceiptNumber,
            CustomerId = p.CustomerId,
            // For the customer the useful name is the shop they paid, not their own.
            CustomerName = shopNames.TryGetValue(p.BusinessId, out var n) ? n : names.GetValueOrDefault(p.CustomerId, ""),
            InvoiceId = p.InvoiceId,
            Amount = p.Amount,
            Mode = p.Mode,
            ReferenceNo = p.ReferenceNo,
            PaidOn = p.PaidOn,
            OutstandingAfter = mine.FirstOrDefault(c => c.Id == p.CustomerId)?.OutstandingBalance ?? 0
        }).ToList());
    }

    [HttpGet("credits")]
    public async Task<IActionResult> Credits([FromQuery] bool availableOnly = false, CancellationToken ct = default)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var q = _db.CreditGrants.AsNoTracking().Include(g => g.Business).Include(g => g.Customer)
                                .Where(g => ids.Contains(g.CustomerId));
        if (availableOnly)
            q = q.Where(g => g.BalanceAmount > 0 &&
                             (g.Status == CreditStatus.Active || g.Status == CreditStatus.PartiallyClaimed));

        var rows = await q.OrderByDescending(g => g.Id).Take(200).ToListAsync(ct);
        return Ok(rows.Select(g => ToDto(g, g.Business, g.Customer)).ToList());
    }

    /// <summary>Customer asks to use part (or all) of a credit. The shop approves it.</summary>
    [HttpPost("credits/claim")]
    public async Task<IActionResult> Claim(ClaimCreditRequest req, CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();

        var grant = await _db.CreditGrants.FirstOrDefaultAsync(
            g => g.Id == req.CreditGrantId && ids.Contains(g.CustomerId), ct);
        if (grant is null) return NotFoundMsg("Credit not found on your account.");

        if (grant.Status is CreditStatus.Cancelled or CreditStatus.Expired or CreditStatus.Claimed)
            return Fail($"This credit is {grant.Status.ToLowerInvariant()} and cannot be claimed.");

        if (grant.ExpiryDate is not null && grant.ExpiryDate < DateOnly.FromDateTime(DateTime.Today))
        {
            grant.Status = CreditStatus.Expired;
            await _db.SaveChangesAsync(ct);
            return Fail("This credit has expired.");
        }

        var amount = req.Amount is null or <= 0 ? grant.BalanceAmount : req.Amount.Value;
        if (amount <= 0) return Fail("Nothing left to claim on this credit.");
        if (amount > grant.BalanceAmount)
            return Fail($"Only Rs.{grant.BalanceAmount:N2} is available on this credit.");

        var alreadyPending = await _db.CreditClaims.AnyAsync(
            c => c.CreditGrantId == grant.Id && c.Status == ClaimStatus.Pending, ct);
        if (alreadyPending)
            return Fail("You already have a pending claim on this credit. Wait for the shop to approve it.");

        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == grant.CustomerId, ct);
        var biz  = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == grant.BusinessId, ct);
        if (cust is null || biz is null) return NotFoundMsg("Credit record is incomplete.");

        var claim = new CreditClaim
        {
            CreditGrantId = grant.Id,
            BusinessId    = grant.BusinessId,
            CustomerId    = grant.CustomerId,
            Amount        = amount,
            Status        = ClaimStatus.Pending,
            Remarks       = req.Remarks
        };
        _db.CreditClaims.Add(claim);

        await _books.AuditAsync(biz.Id, _me.UserId, "RequestCreditClaim", "CreditClaim", null,
                                $"{grant.CreditCode} amount={amount}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        // Let the shop owner know on WhatsApp.
        await _wa.SendAsync("ClaimRequested", biz.Mobile,
                            MessageTemplates.ClaimRequested(biz, cust, claim, grant), biz.Id, cust.Id, ct);

        return Ok(ToDto(claim, grant, biz, cust),
                  "Claim submitted. The shop will approve it shortly.");
    }

    [HttpGet("claims")]
    public async Task<IActionResult> MyClaims(CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var rows = await _db.CreditClaims.AsNoTracking()
                            .Include(c => c.CreditGrant).Include(c => c.Business).Include(c => c.Customer)
                            .Where(c => ids.Contains(c.CustomerId))
                            .OrderByDescending(c => c.Id).Take(100).ToListAsync(ct);
        return Ok(rows.Select(c => ToDto(c, c.CreditGrant, c.Business, c.Customer)).ToList());
    }

    [HttpPost("claims/{id:int}/cancel")]
    public async Task<IActionResult> CancelClaim(int id, CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var claim = await _db.CreditClaims.FirstOrDefaultAsync(c => c.Id == id && ids.Contains(c.CustomerId), ct);
        if (claim is null) return NotFoundMsg("Claim not found on your account.");
        if (claim.Status != ClaimStatus.Pending) return Fail("Only a pending claim can be cancelled.");

        claim.Status      = ClaimStatus.Cancelled;
        claim.ProcessedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Claim cancelled.");
    }

    // ------------------------- UPI payment proofs -------------------------

    /// <summary>
    /// Customer pays by UPI and uploads the screenshot. It sits as Pending until
    /// the shop approves it; nothing moves in the books before that.
    /// </summary>
    [HttpPost("payment-proofs")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    public async Task<IActionResult> SubmitProof(
        [FromForm] int businessId,
        [FromForm] decimal amount,
        [FromForm] int? invoiceId,
        [FromForm] string? referenceNo,
        [FromForm] string? note,
        IFormFile? screenshot,
        CancellationToken ct)
    {
        if (amount <= 0) return Fail("Enter the amount you paid.");

        var mine = await MyCustomerRowsAsync(ct);
        var cust = mine.FirstOrDefault(c => c.BusinessId == businessId);
        if (cust is null) return Fail("You are not a customer of that shop.");

        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == businessId, ct);
        if (biz is null) return NotFoundMsg("Shop not found.");

        if (amount > cust.OutstandingBalance)
            return Fail($"You owe Rs.{cust.OutstandingBalance:N2} at this shop. "
                      + "Enter that amount or less.");

        Invoice? inv = null;
        if (invoiceId is not null)
        {
            inv = await _db.Invoices.FirstOrDefaultAsync(
                i => i.Id == invoiceId && i.CustomerId == cust.Id, ct);
            if (inv is null) return NotFoundMsg("That bill is not on your account.");
            if (amount > inv.BalanceAmount)
                return Fail($"That bill only has Rs.{inv.BalanceAmount:N2} left to pay.");
        }

        var pending = await _db.PaymentProofs.AnyAsync(
            p => p.CustomerId == cust.Id && p.Status == ProofStatus.Pending, ct);
        if (pending)
            return Fail("You already have a payment waiting for this shop to approve.");

        StoredFile? stored = null;
        if (screenshot is not null)
        {
            try
            {
                stored = await _files.SaveImageAsync(screenshot, $"proofs{businessId}", ct);
            }
            catch (InvalidOperationException ex)
            {
                return Fail(ex.Message);
            }
        }

        var proof = new PaymentProof
        {
            BusinessId  = biz.Id,
            CustomerId  = cust.Id,
            InvoiceId   = inv?.Id,
            Amount      = amount,
            Method      = "UPI",
            ReferenceNo = referenceNo,
            Note        = note,
            FileName    = stored?.FileName,
            ContentType = stored?.ContentType,
            FileSize    = stored?.Size,
            StoredPath  = stored?.RelativePath,
            Status      = ProofStatus.Pending
        };
        _db.PaymentProofs.Add(proof);

        await _books.AuditAsync(biz.Id, _me.UserId, "SubmitPaymentProof", "PaymentProof", null,
                                $"amount={amount} ref={referenceNo}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        // Nudge the shop owner on WhatsApp so they know to look.
        await _wa.SendAsync("ProofReceived", biz.Mobile,
                            MessageTemplates.ProofReceived(biz, cust, amount, referenceNo,
                                                           inv?.InvoiceNumber, stored is not null),
                            biz.Id, cust.Id, ct);

        return Ok(PaymentProofsController.ToDto(proof, biz, cust, inv),
                  "Payment confirmation sent to the shop. Your balance updates once they approve it.");
    }

    [HttpGet("payment-proofs")]
    public async Task<IActionResult> MyProofs(CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var rows = await _db.PaymentProofs.AsNoTracking()
                            .Include(p => p.Business).Include(p => p.Customer).Include(p => p.Invoice)
                            .Where(p => ids.Contains(p.CustomerId))
                            .OrderByDescending(p => p.Id).Take(100).ToListAsync(ct);

        return Ok(rows.Select(p => PaymentProofsController.ToDto(p)).ToList());
    }

    [HttpPost("payment-proofs/{id:int}/cancel")]
    public async Task<IActionResult> CancelProof(int id, CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var proof = await _db.PaymentProofs.FirstOrDefaultAsync(
            p => p.Id == id && ids.Contains(p.CustomerId), ct);
        if (proof is null) return NotFoundMsg("Payment not found on your account.");
        if (proof.Status != ProofStatus.Pending)
            return Fail("Only a payment still waiting for approval can be cancelled.");

        proof.Status      = ProofStatus.Cancelled;
        proof.ProcessedAt = DateTime.UtcNow;
        _files.Delete(proof.StoredPath);
        proof.StoredPath = null;

        await _db.SaveChangesAsync(ct);
        return Ok(true, "Payment cancelled.");
    }

    /// <summary>The customer's running account with one shop: every unpaid bill with its date.</summary>
    [HttpGet("statement")]
    public async Task<IActionResult> Statement([FromQuery] int businessId, CancellationToken ct)
    {
        var mine = await MyCustomerRowsAsync(ct);
        var cust = mine.FirstOrDefault(c => c.BusinessId == businessId);
        if (cust is null) return Fail("You are not a customer of that shop.");

        var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == businessId, ct);
        return Ok(await StatementBuilder.BuildAsync(_db, cust, biz, ct));
    }

    [HttpGet("ledger")]
    public async Task<IActionResult> Ledger([FromQuery] int? businessId, CancellationToken ct)
    {
        var ids = (await MyCustomerRowsAsync(ct)).Select(c => c.Id).ToList();
        var q = _db.LedgerEntries.AsNoTracking().Where(l => ids.Contains(l.CustomerId));
        if (businessId is not null) q = q.Where(l => l.BusinessId == businessId);

        var rows = await q.OrderByDescending(l => l.Id).Take(200)
                          .Select(l => new LedgerEntryDto
                          {
                              Id = l.Id, EntryDate = l.EntryDate, RefType = l.RefType, RefId = l.RefId,
                              Description = l.Description, Debit = l.Debit, Credit = l.Credit,
                              RunningBalance = l.RunningBalance
                          }).ToListAsync(ct);
        return Ok(rows);
    }

    /// <summary>
    /// Every Customers row for this login. Rows a shop created before the customer
    /// signed up are matched by mobile number and linked on first access.
    /// </summary>
    private async Task<List<Customer>> MyCustomerRowsAsync(CancellationToken ct)
    {
        var unlinked = await _db.Customers
                                .Where(c => c.UserId == null && c.Mobile == _me.Mobile)
                                .ToListAsync(ct);
        if (unlinked.Count > 0)
        {
            foreach (var c in unlinked) c.UserId = _me.UserId;
            await _db.SaveChangesAsync(ct);
        }

        return await _db.Customers.Where(c => c.UserId == _me.UserId).ToListAsync(ct);
    }
}
