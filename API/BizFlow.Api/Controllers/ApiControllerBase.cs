using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public abstract class ApiControllerBase : ControllerBase
{
    protected IActionResult Ok<T>(T data, string message = "OK") =>
        base.Ok(ApiResponse<T>.Ok(data, message));

    protected IActionResult Fail(string message, int statusCode = StatusCodes.Status400BadRequest, object? errors = null) =>
        StatusCode(statusCode, ApiResponse<object>.Fail(message, errors));

    protected IActionResult NotFoundMsg(string message) => Fail(message, StatusCodes.Status404NotFound);
    protected IActionResult Forbidden(string message = "You are not allowed to access this resource.") =>
        Fail(message, StatusCodes.Status403Forbidden);

    protected string? ClientIp => HttpContext.Connection.RemoteIpAddress?.ToString();

    /// <summary>
    /// The business a BusinessUser is acting on. SuperAdmin may target any business
    /// by passing ?businessId=. Everyone else is pinned to their own tenant.
    /// </summary>
    protected int? ResolveBusinessId(ICurrentUser me, int? requested)
    {
        if (me.Role == Roles.BusinessUser) return me.BusinessId;
        // A worker is pinned to the shop they work at, exactly like the owner.
        if (me.Role == Roles.Worker) return me.BusinessId;
        if (me.IsSuperAdmin) return requested;
        return null;
    }

    /// <summary>The signed-in worker's record, or null for owners / admin (and for a deactivated worker).</summary>
    protected static Task<Worker?> CurrentWorkerAsync(AppDbContext db, ICurrentUser me, CancellationToken ct) =>
        me.Role == Roles.Worker
            ? db.Workers.AsNoTracking().FirstOrDefaultAsync(w => w.UserId == me.UserId && w.IsActive, ct)
            : Task.FromResult<Worker?>(null);

    protected static TenderDto ToTender(Payment p) => new()
    {
        ReceiptNumber = p.ReceiptNumber, Mode = p.Mode, Amount = p.Amount, ReferenceNo = p.ReferenceNo,
        CardScope = p.CardScope, CardNetwork = p.CardNetwork, CardType = p.CardType,
        CardLast4 = p.CardLast4, CardApprovalCode = p.CardApprovalCode, PaidOn = p.PaidOn
    };

    protected static ProductDto ToDto(Product p) => new()
    {
        Id = p.Id, Name = p.Name, Sku = p.Sku, Barcode = p.Barcode, Unit = p.Unit,
        SellingPrice = p.SellingPrice, PurchasePrice = p.PurchasePrice,
        TaxPercent = p.TaxPercent, StockQty = p.StockQty, MinStockQty = p.MinStockQty,
        IsLowStock = p.StockQty <= p.MinStockQty, IsActive = p.IsActive
    };

    protected static CustomerDto ToDto(Customer c) => new()
    {
        Id = c.Id, BusinessId = c.BusinessId, UserId = c.UserId, Name = c.Name,
        Mobile = c.Mobile, Email = c.Email, Address = c.Address, IsTrusted = c.IsTrusted,
        CreditLimit = c.CreditLimit, OutstandingBalance = c.OutstandingBalance,
        CreditBalance = c.CreditBalance, HasAppAccount = c.UserId != null,
        IsActive = c.IsActive, CreatedAt = c.CreatedAt
    };

    protected static InvoiceDto ToDto(Invoice inv, Business? biz, Customer? cust, string? waLink = null,
                                      IEnumerable<Payment>? payments = null)
    {
        var dto = ToDtoCore(inv, biz, cust, waLink);
        dto.BilledByWorkerId = inv.BilledByWorkerId;
        dto.BilledByName = inv.BilledByWorker?.Name;
        dto.CashTendered = inv.CashTendered;
        if (payments is not null) dto.Tenders = payments.OrderBy(p => p.Id).Select(ToTender).ToList();
        if (inv.CashTendered is { } given)
        {
            var cash = payments?.Where(p => p.Mode == "Cash").Sum(p => p.Amount)
                       ?? (inv.PaymentMode == "Cash" ? inv.PaidAmount : 0);
            if (given > cash) dto.ChangeReturned = given - cash;
        }
        return dto;
    }

    /// <summary>Image URL with a version stamp, so a changed logo is fetched again.</summary>
    protected static string? BrandingUrl(Business? b, string kind)
    {
        if (b is null) return null;
        var has = kind == "logo" ? b.LogoPath : b.SignaturePath;
        if (string.IsNullOrEmpty(has)) return null;
        return $"/api/business-profile/{b.Id}/{kind}?v={(b.BrandingUpdatedAt ?? b.CreatedAt).Ticks}";
    }

    private static InvoiceDto ToDtoCore(Invoice inv, Business? biz, Customer? cust, string? waLink) => new()
    {
        BusinessType = biz?.BusinessType, BusinessTagline = biz?.Tagline, BusinessEmail = biz?.Email,
        LogoUrl = BrandingUrl(biz, "logo"), SignatureUrl = BrandingUrl(biz, "signature"),
        SignatoryName = biz?.SignatoryName, InvoiceTerms = biz?.InvoiceTerms, ReceiptFooter = biz?.ReceiptFooter,
        ShowLogoOnReceipt = biz?.ShowLogoOnReceipt ?? true, ShowSignature = biz?.ShowSignature ?? true,
        Id = inv.Id, InvoiceNumber = inv.InvoiceNumber, InvoiceDate = inv.InvoiceDate,
        BusinessId = inv.BusinessId, BusinessName = biz?.Name ?? "",
        BusinessMobile = biz?.Mobile ?? "", BusinessGstNumber = biz?.GstNumber,
        BusinessUpiId = biz?.UpiId,
        BusinessUpiName = string.IsNullOrWhiteSpace(biz?.UpiName) ? biz?.Name : biz!.UpiName,
        BusinessAddress = biz is null ? null : NullIfEmpty(string.Join(", ",
            new[] { biz.AddressLine, biz.City, biz.State, biz.Pincode }
                .Where(x => !string.IsNullOrWhiteSpace(x)))),
        CustomerId = inv.CustomerId, CustomerName = cust?.Name ?? "", CustomerMobile = cust?.Mobile ?? "",
        CustomerAddress = cust?.Address, CustomerOutstanding = cust?.OutstandingBalance ?? 0,
        SubTotal = inv.SubTotal, DiscountAmount = inv.DiscountAmount, TaxAmount = inv.TaxAmount,
        GrandTotal = inv.GrandTotal, PaidAmount = inv.PaidAmount, BalanceAmount = inv.BalanceAmount,
        PaymentMode = inv.PaymentMode, Status = inv.Status, Notes = inv.Notes,
        WhatsAppLink = waLink,
        Items = inv.Items.Select(i => new InvoiceItemDto
        {
            Id = i.Id, ProductId = i.ProductId, ProductName = i.ProductName,
            Quantity = i.Quantity, UnitPrice = i.UnitPrice, DiscountAmount = i.DiscountAmount,
            TaxPercent = i.TaxPercent, TaxAmount = i.TaxAmount, LineTotal = i.LineTotal
        }).ToList()
    };

    private static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s;

    protected static CreditGrantDto ToDto(CreditGrant g, Business? biz, Customer? cust, string? waLink = null) => new()
    {
        Id = g.Id, CreditCode = g.CreditCode, BusinessId = g.BusinessId, BusinessName = biz?.Name ?? "",
        CustomerId = g.CustomerId, CustomerName = cust?.Name ?? "", CustomerMobile = cust?.Mobile ?? "",
        Amount = g.Amount, ClaimedAmount = g.ClaimedAmount, BalanceAmount = g.BalanceAmount,
        Reason = g.Reason, ExpiryDate = g.ExpiryDate, Status = g.Status, CreatedAt = g.CreatedAt,
        WhatsAppLink = waLink
    };

    protected static CreditClaimDto ToDto(CreditClaim c, CreditGrant? g, Business? biz, Customer? cust) => new()
    {
        Id = c.Id, CreditGrantId = c.CreditGrantId, CreditCode = g?.CreditCode ?? "",
        BusinessId = c.BusinessId, BusinessName = biz?.Name ?? "",
        CustomerId = c.CustomerId, CustomerName = cust?.Name ?? "", CustomerMobile = cust?.Mobile ?? "",
        Amount = c.Amount, Status = c.Status, Remarks = c.Remarks,
        RequestedAt = c.RequestedAt, ProcessedAt = c.ProcessedAt
    };
}
