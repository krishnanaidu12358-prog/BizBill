namespace BizFlow.Api.Entities;

/// <summary>The account types in this product.</summary>
public static class Roles
{
    public const string SuperAdmin   = "SuperAdmin";
    public const string BusinessUser = "BusinessUser";
    public const string Customer     = "Customer";
    /// <summary>A shop's staff member: bills at the counter, marks own attendance.</summary>
    public const string Worker       = "Worker";

    /// <summary>For [Authorize]: shop owner and admin only.</summary>
    public const string Owners = BusinessUser + "," + SuperAdmin;
    /// <summary>For [Authorize]: owner, admin and the shop's workers.</summary>
    public const string Staff  = BusinessUser + "," + SuperAdmin + "," + Worker;
}

public static class InvoiceStatus
{
    public const string Draft         = "Draft";
    public const string Confirmed     = "Confirmed";
    public const string PartiallyPaid = "PartiallyPaid";
    public const string Paid          = "Paid";
    public const string Credit        = "Credit";
    public const string Cancelled     = "Cancelled";
}

public static class CreditStatus
{
    public const string Active           = "Active";
    public const string PartiallyClaimed = "PartiallyClaimed";
    public const string Claimed          = "Claimed";
    public const string Expired          = "Expired";
    public const string Cancelled        = "Cancelled";
}

public static class ClaimStatus
{
    public const string Pending   = "Pending";
    public const string Approved  = "Approved";
    public const string Rejected  = "Rejected";
    public const string Cancelled = "Cancelled";
}

public class Business
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string? OwnerName { get; set; }
    public string Mobile { get; set; } = "";
    public string? Email { get; set; }
    public string? AddressLine { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? Pincode { get; set; }
    public string? GstNumber { get; set; }
    public string InvoicePrefix { get; set; } = "INV";
    public string Currency { get; set; } = "INR";
    /// <summary>The shop's UPI ID (VPA), e.g. shopname@okaxis. Customers pay to this.</summary>
    public string? UpiId { get; set; }
    /// <summary>Name shown in the customer's UPI app. Defaults to the shop name.</summary>
    public string? UpiName { get; set; }

    // ---- shop profile and bill design (printed on every bill)
    /// <summary>Supermarket, Mart, Kirana, Electricals, ... (see BusinessTypes).</summary>
    public string BusinessType { get; set; } = "Retail";
    /// <summary>One line under the shop name, e.g. "Fresh groceries daily".</summary>
    public string? Tagline { get; set; }
    public string? LogoPath { get; set; }
    public string? LogoContentType { get; set; }
    public string? SignaturePath { get; set; }
    public string? SignatureContentType { get; set; }
    /// <summary>Printed under the signature, e.g. "For Kittu Kirana Store, Proprietor".</summary>
    public string? SignatoryName { get; set; }
    /// <summary>Terms &amp; conditions on the A4 invoice.</summary>
    public string? InvoiceTerms { get; set; }
    /// <summary>Last line of the till receipt, e.g. "Thank you! Visit again".</summary>
    public string? ReceiptFooter { get; set; }
    public bool ShowLogoOnReceipt { get; set; } = true;
    public bool ShowSignature { get; set; } = true;
    /// <summary>Changes whenever the logo or signature changes, so apps refetch the images.</summary>
    public DateTime? BrandingUpdatedAt { get; set; }

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public static class BusinessTypes
{
    public static readonly string[] All =
    {
        "Supermarket", "Mart", "Kirana", "Retail", "Electricals", "Hardware", "Pharmacy",
        "Restaurant", "Bakery", "Textiles", "Footwear", "Mobile shop", "Stationery",
        "Wholesale", "Services", "Other"
    };
}

public class AppUser
{
    public int Id { get; set; }
    public int? BusinessId { get; set; }
    public string Mobile { get; set; } = "";
    public string FullName { get; set; } = "";
    public string? Email { get; set; }
    public string PasswordHash { get; set; } = "";
    public string Role { get; set; } = Roles.Customer;
    public bool IsActive { get; set; } = true;
    public DateTime? LastLoginAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>System | Light | Dark</summary>
    public string ThemeMode { get; set; } = "System";
    /// <summary>Key of one of the preset palettes, e.g. Classic, Indigo, Maroon.</summary>
    public string ThemeName { get; set; } = "Classic";

    public Business? Business { get; set; }
}

/// <summary>
/// A "forgot password" code. Only a hash of the 6-digit code is kept, it lasts
/// ten minutes, and it stops working after five wrong tries or once used.
/// </summary>
public class PasswordReset
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string CodeHash { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public int Attempts { get; set; }
    public DateTime? UsedAt { get; set; }
    public string? RequestIp { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class RefreshToken
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Token { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Customer
{
    /// <summary>
    /// Mobile used for the per-shop "Walk-in customer" - counter sales to people
    /// who do not give a number (supermarket, bar, mart style). Never messaged.
    /// </summary>
    public const string WalkInMobile = "0000000000";
    public bool IsWalkIn => Mobile == WalkInMobile;

    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int? UserId { get; set; }
    public string Name { get; set; } = "";
    public string Mobile { get; set; } = "";
    public string? Email { get; set; }
    public string? Address { get; set; }
    public bool IsTrusted { get; set; }
    public decimal CreditLimit { get; set; }
    /// <summary>What the customer still owes the shop.</summary>
    public decimal OutstandingBalance { get; set; }
    /// <summary>Unclaimed store credit the shop has granted.</summary>
    public decimal CreditBalance { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Business? Business { get; set; }
    public AppUser? User { get; set; }
}

public class Product
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public string Name { get; set; } = "";
    public string? Sku { get; set; }
    /// <summary>EAN-13 / UPC / Code-128 printed on the pack. Scanned at the counter.</summary>
    public string? Barcode { get; set; }
    public string Unit { get; set; } = "PCS";
    public decimal SellingPrice { get; set; }
    public decimal PurchasePrice { get; set; }
    public decimal TaxPercent { get; set; }
    public decimal StockQty { get; set; }
    public decimal MinStockQty { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Invoice
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int CustomerId { get; set; }
    public string InvoiceNumber { get; set; } = "";
    public DateTime InvoiceDate { get; set; } = DateTime.UtcNow;
    public decimal SubTotal { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal GrandTotal { get; set; }
    public decimal PaidAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public string PaymentMode { get; set; } = "Cash";
    public string Status { get; set; } = InvoiceStatus.Confirmed;
    public string? Notes { get; set; }
    public int? CreatedByUserId { get; set; }
    /// <summary>The worker who made the bill; null when the owner billed it.</summary>
    public int? BilledByWorkerId { get; set; }
    /// <summary>Cash the customer handed over (for the change line on the receipt).</summary>
    public decimal? CashTendered { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? CancelledAt { get; set; }

    public Worker? BilledByWorker { get; set; }

    public Customer? Customer { get; set; }
    public Business? Business { get; set; }
    public List<InvoiceItem> Items { get; set; } = new();
}

public class InvoiceItem
{
    public int Id { get; set; }
    public int InvoiceId { get; set; }
    public int? ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal TaxPercent { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal LineTotal { get; set; }
}

public class Payment
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int CustomerId { get; set; }
    public int? InvoiceId { get; set; }
    public string ReceiptNumber { get; set; } = "";
    public decimal Amount { get; set; }
    public string Mode { get; set; } = "Cash";
    public string? ReferenceNo { get; set; }
    public string? Note { get; set; }
    // Card taken on the counter card machine. Only the last 4 digits are ever stored.
    public string? CardScope { get; set; }
    public string? CardNetwork { get; set; }
    public string? CardType { get; set; }
    public string? CardLast4 { get; set; }
    public string? CardApprovalCode { get; set; }
    public DateTime PaidOn { get; set; } = DateTime.UtcNow;
    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Customer? Customer { get; set; }
}

/// <summary>Store credit / Udhaar the shop grants to a trusted customer.</summary>
public class CreditGrant
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int CustomerId { get; set; }
    public string CreditCode { get; set; } = "";
    public decimal Amount { get; set; }
    public decimal ClaimedAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public string? Reason { get; set; }
    public DateOnly? ExpiryDate { get; set; }
    public string Status { get; set; } = CreditStatus.Active;
    public int? IssuedByUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Customer? Customer { get; set; }
    public Business? Business { get; set; }
}

/// <summary>A customer's request to use part of a credit grant.</summary>
public class CreditClaim
{
    public int Id { get; set; }
    public int CreditGrantId { get; set; }
    public int BusinessId { get; set; }
    public int CustomerId { get; set; }
    public decimal Amount { get; set; }
    public string Status { get; set; } = ClaimStatus.Pending;
    public string? Remarks { get; set; }
    public DateTime RequestedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ProcessedAt { get; set; }
    public int? ProcessedByUserId { get; set; }
    public int? InvoiceId { get; set; }

    public CreditGrant? CreditGrant { get; set; }
    public Customer? Customer { get; set; }
    public Business? Business { get; set; }
}

public class LedgerEntry
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int CustomerId { get; set; }
    public DateTime EntryDate { get; set; } = DateTime.UtcNow;
    public string RefType { get; set; } = "Adjustment";
    public int? RefId { get; set; }
    public string Description { get; set; } = "";
    public decimal Debit { get; set; }
    public decimal Credit { get; set; }
    public decimal RunningBalance { get; set; }
}

public class WhatsAppMessage
{
    public int Id { get; set; }
    public int? BusinessId { get; set; }
    public int? CustomerId { get; set; }
    public string ToMobile { get; set; } = "";
    public string Template { get; set; } = "";
    public string Body { get; set; } = "";
    public string? DeepLink { get; set; }
    public string Status { get; set; } = "Queued";
    public string? Provider { get; set; }
    public string? ProviderMessageId { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? SentAt { get; set; }
}

public class AuditLog
{
    public int Id { get; set; }
    public int? BusinessId { get; set; }
    public int? UserId { get; set; }
    public string Action { get; set; } = "";
    public string? EntityName { get; set; }
    public int? EntityId { get; set; }
    public string? Details { get; set; }
    public string? IpAddress { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>Money a shop spends. Cancelled, never deleted, like bills.</summary>
public class Expense
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public string Category { get; set; } = "Other";
    public decimal Amount { get; set; }
    public DateTime ExpenseDate { get; set; } = DateTime.UtcNow;
    public string PaymentMode { get; set; } = "Cash";
    public string? PaidTo { get; set; }
    public string? Note { get; set; }
    public bool IsCancelled { get; set; }
    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Business? Business { get; set; }
}

public static class ExpenseCategories
{
    public static readonly string[] All =
        { "Stock purchase", "Rent", "Salary", "Electricity", "Transport", "Maintenance", "Marketing", "Other" };
}

public static class ProofStatus
{
    public const string Pending   = "Pending";
    public const string Approved  = "Approved";
    public const string Rejected  = "Rejected";
    public const string Cancelled = "Cancelled";
}

/// <summary>
/// A customer's UPI payment screenshot waiting for the shop to confirm it.
/// Approving one records a real Payment and re-issues the bill.
/// </summary>
public class PaymentProof
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int CustomerId { get; set; }
    public int? InvoiceId { get; set; }
    public decimal Amount { get; set; }
    public string Method { get; set; } = "UPI";
    public string? ReferenceNo { get; set; }
    public string? Note { get; set; }

    public string? FileName { get; set; }
    public string? ContentType { get; set; }
    public int? FileSize { get; set; }
    public string? StoredPath { get; set; }

    public string Status { get; set; } = ProofStatus.Pending;
    public string? Remarks { get; set; }
    public DateTime SubmittedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ProcessedAt { get; set; }
    public int? ProcessedByUserId { get; set; }
    public int? PaymentId { get; set; }

    public Customer? Customer { get; set; }
    public Business? Business { get; set; }
    public Invoice? Invoice { get; set; }
}
