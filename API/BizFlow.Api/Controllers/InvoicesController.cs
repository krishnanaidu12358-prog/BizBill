using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// Billing. Creating a bill also moves stock, the ledger and the customer's Udhaar.
/// Workers can bill and see their own bills; only the owner can cancel.
/// </summary>
[Authorize(Roles = Roles.Staff)]
public class InvoicesController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _wa;

    public InvoicesController(AppDbContext db, ICurrentUser me, IBookkeepingService books, IWhatsAppService wa)
    {
        _db = db; _me = me; _books = books; _wa = wa;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] int? customerId, [FromQuery] string? status,
                                          [FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                          [FromQuery] string? search, [FromQuery] int? businessId,
                                          [FromQuery] int? workerId, [FromQuery] bool? ownerOnly,
                                          [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        var q = _db.Invoices.AsNoTracking().Include(i => i.Customer).Include(i => i.Business)
                   .Include(i => i.BilledByWorker).AsQueryable();
        if (bizId is not null) q = q.Where(i => i.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        // A worker only ever sees the bills they made.
        if (_me.Role == Roles.Worker)
        {
            var me = await CurrentWorkerAsync(_db, _me, ct);
            if (me is null) return Forbidden("Your worker account is not active.");
            q = q.Where(i => i.BilledByWorkerId == me.Id);
        }
        else if (workerId is not null) q = q.Where(i => i.BilledByWorkerId == workerId);
        else if (ownerOnly == true) q = q.Where(i => i.BilledByWorkerId == null);

        if (customerId is not null) q = q.Where(i => i.CustomerId == customerId);
        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(i => i.Status == status);
        if (from is not null) q = q.Where(i => i.InvoiceDate >= from);
        if (to is not null)   q = q.Where(i => i.InvoiceDate <= to);
        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(i => i.InvoiceNumber.Contains(search) ||
                             (i.Customer != null && (i.Customer.Name.Contains(search) ||
                                                     i.Customer.Mobile.Contains(search))));

        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(i => i.Id)
                          .Skip((page - 1) * pageSize).Take(pageSize)
                          .ToListAsync(ct);

        return Ok(new PagedResult<InvoiceDto>
        {
            Items = rows.Select(i => ToDto(i, i.Business, i.Customer)).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id, CancellationToken ct)
    {
        var inv = await _db.Invoices.AsNoTracking()
                           .Include(i => i.Items).Include(i => i.Customer).Include(i => i.Business)
                           .Include(i => i.BilledByWorker)
                           .FirstOrDefaultAsync(i => i.Id == id, ct);
        if (inv is null) return NotFoundMsg("Bill not found.");
        if (!CanTouch(inv.BusinessId)) return Forbidden();
        if (_me.Role == Roles.Worker)
        {
            var me = await CurrentWorkerAsync(_db, _me, ct);
            if (me is null || inv.BilledByWorkerId != me.Id) return Forbidden("You can only open bills you made.");
        }

        var payments = await _db.Payments.AsNoTracking().Where(p => p.InvoiceId == inv.Id).ToListAsync(ct);

        // Only a message that actually carries this bill's number - the customer's
        // latest "Bill" message could be a different bill entirely.
        var link = await _db.WhatsAppMessages.AsNoTracking()
                            .Where(m => m.CustomerId == inv.CustomerId &&
                                        (m.Template == "Bill" || m.Template == "Statement") &&
                                        m.Body.Contains(inv.InvoiceNumber))
                            .OrderByDescending(m => m.Id).Select(m => m.DeepLink).FirstOrDefaultAsync(ct);

        return Ok(ToDto(inv, inv.Business, inv.Customer, link, payments));
    }

    [HttpPost]
    public async Task<IActionResult> Create(CreateInvoiceRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");
        if (req.Items.Count == 0) return Fail("Add at least one item to the bill.");

        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == bizId, ct);
        if (biz is null) return NotFoundMsg("Business not found.");

        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == req.CustomerId && c.BusinessId == bizId, ct);
        if (cust is null) return NotFoundMsg("Customer not found in this business.");
        if (!cust.IsActive) return Fail("This customer is deactivated.");

        Worker? worker = null;
        if (_me.Role == Roles.Worker)
        {
            worker = await CurrentWorkerAsync(_db, _me, ct);
            if (worker is null) return Forbidden("Your worker account is not active. Ask the owner.");
        }

        // Counter checkout: split tenders (cash + card, UPI + cash ...).
        var tenders = req.Tenders?.Where(t => t.Amount > 0).ToList() ?? new List<TenderRequest>();
        foreach (var t in tenders)
        {
            var problem = ValidateTender(t);
            if (problem is not null) return Fail(problem);
        }

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var inv = new Invoice
        {
            BusinessId      = bizId.Value,
            CustomerId      = cust.Id,
            InvoiceNumber   = await _books.NextInvoiceNumberAsync(bizId.Value, ct),
            InvoiceDate     = DateTime.UtcNow,
            PaymentMode     = req.PaymentMode,
            Notes           = req.Notes,
            CreatedByUserId = _me.UserId,
            BilledByWorkerId = worker?.Id,
            CashTendered    = req.CashTendered is > 0 ? req.CashTendered : null
        };

        decimal subTotal = 0, itemDiscount = 0, taxTotal = 0;
        var touchedProducts = new List<Product>();

        foreach (var line in req.Items)
        {
            if (line.Quantity <= 0) return Fail("Item quantity must be greater than zero.");

            Product? prod = null;
            if (line.ProductId is not null)
            {
                prod = await _db.Products.FirstOrDefaultAsync(p => p.Id == line.ProductId && p.BusinessId == bizId, ct);
                if (prod is null)  return Fail($"Product #{line.ProductId} not found in this business.");
                if (!prod.IsActive) return Fail($"Product '{prod.Name}' is deactivated and cannot be billed.");
                if (prod.StockQty < line.Quantity)
                    return Fail($"Not enough stock for '{prod.Name}'. Available {prod.StockQty:0.###} {prod.Unit}.");
            }
            else if (string.IsNullOrWhiteSpace(line.ProductName))
            {
                return Fail("Each item needs either a product or an item name.");
            }

            var unitPrice = line.UnitPrice > 0 ? line.UnitPrice : prod?.SellingPrice ?? 0;
            var taxPct    = line.TaxPercent > 0 ? line.TaxPercent : prod?.TaxPercent ?? 0;
            var gross     = decimal.Round(unitPrice * line.Quantity, 2);
            var discount  = Math.Min(line.DiscountAmount, gross);
            var taxable   = gross - discount;
            var tax       = decimal.Round(taxable * taxPct / 100m, 2);

            inv.Items.Add(new InvoiceItem
            {
                ProductId      = prod?.Id,
                ProductName    = prod?.Name ?? line.ProductName!.Trim(),
                Quantity       = line.Quantity,
                UnitPrice      = unitPrice,
                DiscountAmount = discount,
                TaxPercent     = taxPct,
                TaxAmount      = tax,
                LineTotal      = taxable + tax
            });

            subTotal     += gross;
            itemDiscount += discount;
            taxTotal     += tax;

            if (prod is not null)
            {
                prod.StockQty -= line.Quantity;
                touchedProducts.Add(prod);
            }
        }

        var headerDiscount = Math.Min(req.DiscountAmount, subTotal - itemDiscount);
        if (headerDiscount < 0) headerDiscount = 0;

        inv.SubTotal       = subTotal;
        inv.DiscountAmount = itemDiscount + headerDiscount;
        inv.TaxAmount      = taxTotal;
        inv.GrandTotal     = decimal.Round(subTotal - inv.DiscountAmount + taxTotal, 2);

        decimal paid;
        if (tenders.Count > 0)
        {
            paid = tenders.Sum(t => t.Amount);
            if (paid > inv.GrandTotal + 0.01m)
                return Fail($"Payments add up to Rs.{paid:N2} but the bill is Rs.{inv.GrandTotal:N2}. "
                          + "Enter only the bill amount against each payment; the change is worked out from the cash handed over.");
            paid = Math.Min(paid, inv.GrandTotal);
            inv.PaymentMode = tenders.Select(t => t.Mode).Distinct().Count() == 1 ? tenders[0].Mode : "Split";
        }
        else
        {
            paid = Math.Clamp(req.PaidAmount, 0, inv.GrandTotal);
        }
        var balance = decimal.Round(inv.GrandTotal - paid, 2);
        if (paid <= 0) inv.PaymentMode = "Credit";

        if (balance > 0 && worker is not null && !worker.CanGiveUdhaar)
            return Fail("You are not allowed to give Udhaar. Collect the full amount, or ask the owner.");

        // Udhaar rules: only trusted customers may carry a balance, and only up to their limit.
        if (balance > 0)
        {
            if (!cust.IsTrusted)
                return Fail("This customer is not marked as trusted, so the bill must be fully paid. "
                          + "Mark the customer trusted and set a credit limit to allow Udhaar.");

            var projected = cust.OutstandingBalance + balance;
            if (cust.CreditLimit > 0 && projected > cust.CreditLimit)
                return Fail($"Credit limit exceeded. Limit Rs.{cust.CreditLimit:N2}, "
                          + $"outstanding would become Rs.{projected:N2}.");
        }

        inv.PaidAmount    = paid;
        inv.BalanceAmount = balance;
        inv.Status = balance <= 0 ? InvoiceStatus.Paid
                   : paid > 0     ? InvoiceStatus.PartiallyPaid
                                  : InvoiceStatus.Credit;

        _db.Invoices.Add(inv);
        await _db.SaveChangesAsync(ct);

        // Ledger: the bill is a debit, anything collected now is an immediate credit.
        await _books.PostAsync(bizId.Value, cust.Id, "Invoice", inv.Id,
                               $"Bill {inv.InvoiceNumber}", inv.GrandTotal, 0, ct);

        var receipts = new List<Payment>();
        if (paid > 0)
        {
            // One receipt per tender, so the day's cash / UPI / card totals add up.
            var parts = tenders.Count > 0
                ? tenders
                : new List<TenderRequest>
                  {
                      new() { Mode = req.PaymentMode is "Credit" or "Split" ? "Cash" : req.PaymentMode, Amount = paid }
                  };

            var remaining = paid;
            foreach (var t in parts)
            {
                var amount = Math.Min(t.Amount, remaining);
                if (amount <= 0) break;
                remaining -= amount;

                var receipt = new Payment
                {
                    BusinessId      = bizId.Value,
                    CustomerId      = cust.Id,
                    InvoiceId       = inv.Id,
                    ReceiptNumber   = await _books.NextReceiptNumberAsync(bizId.Value, ct),
                    Amount          = amount,
                    Mode            = t.Mode,
                    ReferenceNo     = string.IsNullOrWhiteSpace(t.ReferenceNo) ? t.Card?.ApprovalCode : t.ReferenceNo.Trim(),
                    Note            = $"Against bill {inv.InvoiceNumber}",
                    CreatedByUserId = _me.UserId
                };
                ApplyCard(receipt, t.Mode == "Card" ? t.Card : null);
                _db.Payments.Add(receipt);
                await _db.SaveChangesAsync(ct);
                receipts.Add(receipt);

                await _books.PostAsync(bizId.Value, cust.Id, "Payment", receipt.Id,
                                       $"Payment {receipt.ReceiptNumber} ({receipt.Mode})", 0, amount, ct);
            }
        }

        cust.OutstandingBalance += balance;

        await _books.AuditAsync(bizId, _me.UserId, "CreateInvoice", "Invoice", inv.Id,
                                $"{inv.InvoiceNumber} total={inv.GrandTotal} balance={balance}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        string? waLink = null;
        var sentStatement = false;
        var waFailed = false;

        if (req.SendWhatsApp && !cust.IsWalkIn)
        {
            // If the customer is already carrying dues, send the running account -
            // this bill plus every earlier unpaid bill with its date - instead of a
            // bare invoice, so they see one combined amount owed.
            var unpaid = await StatementBuilder.UnpaidWithItemsAsync(_db, cust.Id, ct);
            var hasEarlier = unpaid.Any(i => i.Id != inv.Id);

            var body = hasEarlier
                ? MessageTemplates.Statement(biz, cust, unpaid, inv)
                : MessageTemplates.Bill(biz, cust, inv);

            var msg = await _wa.SendAsync(hasEarlier ? "Statement" : "Bill", cust.Mobile,
                                          body, biz.Id, cust.Id, ct);
            waLink = msg.DeepLink;
            sentStatement = hasEarlier;
            waFailed = msg.Status == "Failed";
        }

        inv.BilledByWorker = worker;
        return Ok(ToDto(inv, biz, cust, waLink, receipts),
                  !req.SendWhatsApp ? "Bill created."
                  : waFailed ? "Bill created, but WhatsApp delivery failed. Use Send on the bill to retry."
                  : sentStatement
                      ? "Bill created. Sent on WhatsApp with the earlier unpaid bills listed."
                      : "Bill created and sent on WhatsApp.");
    }

    /// <summary>Cancels a bill: stock goes back, ledger is reversed, the row is kept (FR-012).</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/cancel")]
    public async Task<IActionResult> Cancel(int id, [FromQuery] string? reason, CancellationToken ct)
    {
        var inv = await _db.Invoices.Include(i => i.Items).FirstOrDefaultAsync(i => i.Id == id, ct);
        if (inv is null) return NotFoundMsg("Bill not found.");
        if (!CanTouch(inv.BusinessId)) return Forbidden();
        if (inv.Status == InvoiceStatus.Cancelled) return Fail("This bill is already cancelled.");

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        foreach (var item in inv.Items.Where(i => i.ProductId != null))
        {
            var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == item.ProductId, ct);
            if (p is not null) p.StockQty += item.Quantity;
        }

        var cust = await _db.Customers.FirstOrDefaultAsync(c => c.Id == inv.CustomerId, ct);
        if (cust is not null)
        {
            cust.OutstandingBalance -= inv.BalanceAmount;
            if (cust.OutstandingBalance < 0) cust.OutstandingBalance = 0;
        }

        // Reverse the original debit, and the collection if there was one.
        await _books.PostAsync(inv.BusinessId, inv.CustomerId, "Invoice", inv.Id,
                               $"Cancelled bill {inv.InvoiceNumber}", 0, inv.GrandTotal, ct);
        if (inv.PaidAmount > 0)
            await _books.PostAsync(inv.BusinessId, inv.CustomerId, "Adjustment", inv.Id,
                                   $"Refund on cancelled bill {inv.InvoiceNumber}", inv.PaidAmount, 0, ct);

        inv.Status      = InvoiceStatus.Cancelled;
        inv.CancelledAt = DateTime.UtcNow;

        await _books.AuditAsync(inv.BusinessId, _me.UserId, "CancelInvoice", "Invoice", inv.Id,
                                reason, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        return Ok(true, "Bill cancelled and stock restored.");
    }

    /// <summary>Re-sends the bill on WhatsApp and returns a wa.me link the app can open.</summary>
    [HttpPost("{id:int}/send-whatsapp")]
    public async Task<IActionResult> SendWhatsApp(int id, CancellationToken ct)
    {
        var inv = await _db.Invoices.Include(i => i.Items).Include(i => i.Customer).Include(i => i.Business)
                           .FirstOrDefaultAsync(i => i.Id == id, ct);
        if (inv is null) return NotFoundMsg("Bill not found.");
        if (!CanTouch(inv.BusinessId)) return Forbidden();
        if (inv.Customer is null || inv.Business is null) return Fail("Bill is missing customer or business data.");
        if (inv.Status == InvoiceStatus.Cancelled)
            return Fail("This bill is cancelled. Cancelled bills are not sent to the customer.");
        if (inv.Customer.IsWalkIn)
            return Fail("This is a walk-in bill with no mobile number. Share the invoice picture or PDF instead.");

        var msg = await _wa.SendAsync("Bill", inv.Customer.Mobile,
                                      MessageTemplates.Bill(inv.Business, inv.Customer, inv),
                                      inv.BusinessId, inv.CustomerId, ct);

        if (msg.Status == "Failed")
            return Fail($"WhatsApp could not deliver the bill: {msg.ErrorMessage}", StatusCodes.Status502BadGateway);

        return Ok(new { msg.Status, msg.DeepLink, msg.Body },
                  msg.Provider == "Log" ? "Bill ready - opening WhatsApp." : "Bill sent on WhatsApp.");
    }

    private bool CanTouch(int businessId) => _me.IsSuperAdmin || _me.BusinessId == businessId;

    private static readonly string[] TenderModes = { "Cash", "UPI", "Card", "BankTransfer" };

    /// <summary>Null when the tender is fine, otherwise the message to show.</summary>
    internal static string? ValidateTender(TenderRequest t)
    {
        if (!TenderModes.Contains(t.Mode))
            return $"Unknown payment type '{t.Mode}'. Use Cash, UPI, Card or BankTransfer.";
        if (t.Mode != "Card") return null;
        return ValidateCard(t.Card);
    }

    internal static string? ValidateCard(CardDetails? c)
    {
        if (c is null) return null;
        if (!CardInfo.Scopes.Contains(c.Scope))
            return "Card must be Domestic or International.";
        if (c.Network is not null && !CardInfo.Networks.Contains(c.Network))
            return $"Unknown card network '{c.Network}'.";
        if (c.Type is not null && !CardInfo.Types.Contains(c.Type))
            return "Card type must be Debit, Credit or Prepaid.";
        if (!string.IsNullOrWhiteSpace(c.Last4) && (c.Last4.Length != 4 || !c.Last4.All(char.IsDigit)))
            return "Card last 4 must be exactly 4 digits. Never enter the full card number.";
        return null;
    }

    internal static void ApplyCard(Payment p, CardDetails? c)
    {
        if (c is null) return;
        p.CardScope        = c.Scope;
        p.CardNetwork      = c.Network;
        p.CardType         = c.Type;
        p.CardLast4        = string.IsNullOrWhiteSpace(c.Last4) ? null : c.Last4.Trim();
        p.CardApprovalCode = string.IsNullOrWhiteSpace(c.ApprovalCode) ? null : c.ApprovalCode.Trim();
    }
}
