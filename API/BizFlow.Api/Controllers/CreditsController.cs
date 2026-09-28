using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// Store credit (Udhaar) the shop hands to a trusted customer. The customer is told on
/// WhatsApp, sees it in their own app, and claims it; the shop approves the claim and the
/// amount is applied against what the customer owes.
/// </summary>
[Authorize(Roles = Roles.BusinessUser + "," + Roles.SuperAdmin)]
public class CreditsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _wa;

    public CreditsController(AppDbContext db, ICurrentUser me, IBookkeepingService books, IWhatsAppService wa)
    {
        _db = db; _me = me; _books = books; _wa = wa;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] int? customerId, [FromQuery] string? status,
                                          [FromQuery] int? businessId,
                                          [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        var q = _db.CreditGrants.AsNoTracking().Include(g => g.Customer).Include(g => g.Business).AsQueryable();
        if (bizId is not null) q = q.Where(g => g.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        if (customerId is not null) q = q.Where(g => g.CustomerId == customerId);
        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(g => g.Status == status);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(g => g.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<CreditGrantDto>
        {
            Items = rows.Select(g => ToDto(g, g.Business, g.Customer)).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    /// <summary>Issue credit to a trusted customer and notify them on WhatsApp.</summary>
    [HttpPost("issue")]
    public async Task<IActionResult> Issue(IssueCreditRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var biz  = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == bizId, ct);
        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == req.CustomerId && c.BusinessId == bizId, ct);
        if (biz is null)  return NotFoundMsg("Business not found.");
        if (cust is null) return NotFoundMsg("Customer not found in this business.");
        if (!cust.IsActive) return Fail("This customer is deactivated.");

        if (!cust.IsTrusted)
            return Fail("Credit can only be issued to a trusted customer. "
                      + "Mark this customer as trusted and set a credit limit first.");

        if (cust.CreditLimit > 0 && cust.CreditBalance + req.Amount > cust.CreditLimit)
            return Fail($"This would exceed the customer's credit limit of Rs.{cust.CreditLimit:N2}. "
                      + $"Unclaimed credit is already Rs.{cust.CreditBalance:N2}.");

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var grant = new CreditGrant
        {
            BusinessId     = bizId.Value,
            CustomerId     = cust.Id,
            CreditCode     = await _books.NextCreditCodeAsync(bizId.Value, ct),
            Amount         = req.Amount,
            ClaimedAmount  = 0,
            BalanceAmount  = req.Amount,
            Reason         = req.Reason,
            ExpiryDate     = req.ExpiryDate,
            Status         = CreditStatus.Active,
            IssuedByUserId = _me.UserId
        };
        _db.CreditGrants.Add(grant);

        // Unclaimed credit is tracked on the customer; it only hits the ledger when claimed.
        cust.CreditBalance += req.Amount;

        await _books.AuditAsync(bizId, _me.UserId, "IssueCredit", "CreditGrant", null,
                                $"{grant.CreditCode} amount={req.Amount} to {cust.Mobile}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        string? waLink = null;
        if (req.SendWhatsApp)
        {
            var msg = await _wa.SendAsync("CreditIssued", cust.Mobile,
                                          MessageTemplates.CreditIssued(biz, cust, grant), biz.Id, cust.Id, ct);
            waLink = msg.DeepLink;
        }

        return Ok(ToDto(grant, biz, cust, waLink),
                  req.SendWhatsApp ? "Credit issued and sent on WhatsApp." : "Credit issued.");
    }

    [HttpPost("{id:int}/cancel")]
    public async Task<IActionResult> Cancel(int id, [FromQuery] string? reason, CancellationToken ct)
    {
        var grant = await _db.CreditGrants.FirstOrDefaultAsync(g => g.Id == id, ct);
        if (grant is null) return NotFoundMsg("Credit not found.");
        if (!CanTouch(grant.BusinessId)) return Forbidden();
        if (grant.Status is CreditStatus.Cancelled or CreditStatus.Claimed)
            return Fail($"This credit is already {grant.Status.ToLowerInvariant()}.");

        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == grant.CustomerId, ct);
        if (cust is not null)
            cust.CreditBalance = Math.Max(0, cust.CreditBalance - grant.BalanceAmount);

        // Any pending claims against it die with it.
        var pending = await _db.CreditClaims
                               .Where(c => c.CreditGrantId == grant.Id && c.Status == ClaimStatus.Pending)
                               .ToListAsync(ct);
        foreach (var c in pending)
        {
            c.Status      = ClaimStatus.Cancelled;
            c.ProcessedAt = DateTime.UtcNow;
            c.Remarks     = "Credit cancelled by the business.";
        }

        grant.BalanceAmount = 0;
        grant.Status        = CreditStatus.Cancelled;

        await _books.AuditAsync(grant.BusinessId, _me.UserId, "CancelCredit", "CreditGrant", grant.Id, reason, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Credit cancelled.");
    }

    // ------------------------------- claims --------------------------------

    [HttpGet("claims")]
    public async Task<IActionResult> Claims([FromQuery] string? status, [FromQuery] int? businessId,
                                            [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                            CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        var q = _db.CreditClaims.AsNoTracking()
                   .Include(c => c.CreditGrant).Include(c => c.Customer).Include(c => c.Business)
                   .AsQueryable();
        if (bizId is not null) q = q.Where(c => c.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(c => c.Status == status);

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(c => c.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);

        return Ok(new PagedResult<CreditClaimDto>
        {
            Items = rows.Select(c => ToDto(c, c.CreditGrant, c.Business, c.Customer)).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    /// <summary>Approve or reject a customer's claim. Approving applies the amount to their account.</summary>
    [HttpPost("claims/{id:int}/process")]
    public async Task<IActionResult> ProcessClaim(int id, ProcessClaimRequest req, CancellationToken ct)
    {
        var claim = await _db.CreditClaims.FirstOrDefaultAsync(c => c.Id == id, ct);
        if (claim is null) return NotFoundMsg("Claim not found.");
        if (!CanTouch(claim.BusinessId)) return Forbidden();
        if (claim.Status != ClaimStatus.Pending)
            return Fail($"This claim was already {claim.Status.ToLowerInvariant()}.");

        var grant = await _db.CreditGrants.FirstOrDefaultAsync(g => g.Id == claim.CreditGrantId, ct);
        var cust  = await _db.Customers.FirstOrDefaultAsync(c => c.Id == claim.CustomerId, ct);
        var biz   = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == claim.BusinessId, ct);
        if (grant is null || cust is null || biz is null) return NotFoundMsg("Credit record is incomplete.");

        claim.ProcessedAt       = DateTime.UtcNow;
        claim.ProcessedByUserId = _me.UserId;
        claim.Remarks           = req.Remarks;

        if (!req.Approve)
        {
            claim.Status = ClaimStatus.Rejected;
            await _books.AuditAsync(biz.Id, _me.UserId, "RejectCreditClaim", "CreditClaim", claim.Id, req.Remarks, ClientIp, ct);
            await _db.SaveChangesAsync(ct);

            await _wa.SendAsync("ClaimRejected", cust.Mobile,
                                MessageTemplates.ClaimRejected(biz, cust, claim), biz.Id, cust.Id, ct);
            return Ok(ToDto(claim, grant, biz, cust), "Claim rejected.");
        }

        if (claim.Amount > grant.BalanceAmount)
            return Fail($"Only Rs.{grant.BalanceAmount:N2} is left on credit {grant.CreditCode}.");

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        claim.Status = ClaimStatus.Approved;

        grant.ClaimedAmount += claim.Amount;
        grant.BalanceAmount -= claim.Amount;
        grant.Status = grant.BalanceAmount <= 0 ? CreditStatus.Claimed : CreditStatus.PartiallyClaimed;

        cust.CreditBalance      = Math.Max(0, cust.CreditBalance - claim.Amount);
        cust.OutstandingBalance = Math.Max(0, cust.OutstandingBalance - claim.Amount);

        // Settle the claim against the customer's oldest bills so the statement
        // keeps adding up: outstanding must equal the sum of unpaid bill balances.
        await _books.AllocateToOldestUnpaidAsync(cust.Id, claim.Amount, ct);

        await _books.PostAsync(biz.Id, cust.Id, "CreditClaim", claim.Id,
                               $"Credit {grant.CreditCode} claimed", 0, claim.Amount, ct);
        await _books.AuditAsync(biz.Id, _me.UserId, "ApproveCreditClaim", "CreditClaim", claim.Id,
                                $"{grant.CreditCode} amount={claim.Amount}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        await _wa.SendAsync("ClaimApproved", cust.Mobile,
                            MessageTemplates.ClaimApproved(biz, cust, claim, grant), biz.Id, cust.Id, ct);

        return Ok(ToDto(claim, grant, biz, cust), "Claim approved and applied to the customer's account.");
    }

    private bool CanTouch(int businessId) => _me.IsSuperAdmin || _me.BusinessId == businessId;
}
