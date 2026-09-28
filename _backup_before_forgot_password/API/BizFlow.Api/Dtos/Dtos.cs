using System.ComponentModel.DataAnnotations;

namespace BizFlow.Api.Dtos;

/// <summary>Uniform envelope for every endpoint (FRD FR-045).</summary>
public class ApiResponse<T>
{
    public bool Success { get; set; } = true;
    public string Message { get; set; } = "";
    public T? Data { get; set; }
    public object? Errors { get; set; }

    public static ApiResponse<T> Ok(T data, string message = "OK") => new() { Success = true, Data = data, Message = message };
    public static ApiResponse<T> Fail(string message, object? errors = null) => new() { Success = false, Message = message, Errors = errors };
}

public class PagedResult<T>
{
    public List<T> Items { get; set; } = new();
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalCount { get; set; }
    public int TotalPages => PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);
}

// ----------------------------- auth -----------------------------------

public class LoginRequest
{
    [Required, RegularExpression(@"^\d{10}$", ErrorMessage = "Mobile must be 10 digits.")]
    public string Mobile { get; set; } = "";
    [Required] public string Password { get; set; } = "";
}

public class RegisterBusinessRequest
{
    [Required, RegularExpression(@"^\d{10}$")] public string Mobile { get; set; } = "";
    [Required, MinLength(6)] public string Password { get; set; } = "";
    [Required] public string OwnerName { get; set; } = "";
    [Required] public string BusinessName { get; set; } = "";
    /// <summary>Supermarket, Mart, Kirana ... (optional, defaults to Retail).</summary>
    public string? BusinessType { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? GstNumber { get; set; }
}

/// <summary>A customer self-registers with the same mobile the shop already stored.</summary>
public class RegisterCustomerRequest
{
    [Required, RegularExpression(@"^\d{10}$")] public string Mobile { get; set; } = "";
    [Required, MinLength(6)] public string Password { get; set; } = "";
    [Required] public string FullName { get; set; } = "";
    public string? Email { get; set; }
}

public class ChangePasswordRequest
{
    [Required] public string CurrentPassword { get; set; } = "";
    [Required, MinLength(6)] public string NewPassword { get; set; } = "";
}

public class RefreshRequest
{
    [Required] public string RefreshToken { get; set; } = "";
}

public class AuthResponse
{
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public UserProfileDto User { get; set; } = new();
}

public class UserProfileDto
{
    public int Id { get; set; }
    public string Mobile { get; set; } = "";
    public string FullName { get; set; } = "";
    public string? Email { get; set; }
    public string Role { get; set; } = "";
    public int? BusinessId { get; set; }
    public string? BusinessName { get; set; }
    /// <summary>For a Worker login: their worker record and what they may do.</summary>
    public int? WorkerId { get; set; }
    public string? Designation { get; set; }
    public bool CanGiveUdhaar { get; set; }
    public string ThemeMode { get; set; } = "System";
    public string ThemeName { get; set; } = "Classic";
}

// --------------------------- customers ---------------------------------

public class CustomerRequest
{
    [Required, RegularExpression(@"^\d{10}$", ErrorMessage = "Mobile must be 10 digits.")]
    public string Mobile { get; set; } = "";
    [Required] public string Name { get; set; } = "";
    public string? Email { get; set; }
    public string? Address { get; set; }
    public bool IsTrusted { get; set; }
    [Range(0, 99999999)] public decimal CreditLimit { get; set; }
    /// <summary>Optional login PIN/password created for the customer app. Ignored if the account already exists.</summary>
    public string? InitialPassword { get; set; }
}

public class CustomerDto
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int? UserId { get; set; }
    public string Name { get; set; } = "";
    public string Mobile { get; set; } = "";
    public string? Email { get; set; }
    public string? Address { get; set; }
    public bool IsTrusted { get; set; }
    public decimal CreditLimit { get; set; }
    public decimal OutstandingBalance { get; set; }
    public decimal CreditBalance { get; set; }
    public bool HasAppAccount { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class LedgerEntryDto
{
    public int Id { get; set; }
    public DateTime EntryDate { get; set; }
    public string RefType { get; set; } = "";
    public int? RefId { get; set; }
    public string Description { get; set; } = "";
    public decimal Debit { get; set; }
    public decimal Credit { get; set; }
    public decimal RunningBalance { get; set; }
}

// ---------------------------- products ---------------------------------

public class ProductRequest
{
    [Required] public string Name { get; set; } = "";
    public string? Sku { get; set; }
    [MaxLength(64)] public string? Barcode { get; set; }
    public string Unit { get; set; } = "PCS";
    [Range(0, 99999999)] public decimal SellingPrice { get; set; }
    [Range(0, 99999999)] public decimal PurchasePrice { get; set; }
    [Range(0, 100)] public decimal TaxPercent { get; set; }
    public decimal StockQty { get; set; }
    public decimal MinStockQty { get; set; }
}

public class ProductDto
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string? Sku { get; set; }
    public string? Barcode { get; set; }
    public string Unit { get; set; } = "";
    public decimal SellingPrice { get; set; }
    public decimal PurchasePrice { get; set; }
    public decimal TaxPercent { get; set; }
    public decimal StockQty { get; set; }
    public decimal MinStockQty { get; set; }
    public bool IsLowStock { get; set; }
    public bool IsActive { get; set; }
}

// ---------------------------- invoices ---------------------------------

public class InvoiceItemRequest
{
    public int? ProductId { get; set; }
    public string? ProductName { get; set; }
    [Range(0.001, 999999)] public decimal Quantity { get; set; } = 1;
    [Range(0, 99999999)] public decimal UnitPrice { get; set; }
    public decimal DiscountAmount { get; set; }
    [Range(0, 100)] public decimal TaxPercent { get; set; }
}

public class CreateInvoiceRequest
{
    [Required] public int CustomerId { get; set; }
    [MinLength(1, ErrorMessage = "An invoice needs at least one item.")]
    public List<InvoiceItemRequest> Items { get; set; } = new();
    public decimal DiscountAmount { get; set; }
    /// <summary>Cash / UPI / Card / BankTransfer / Credit / Split</summary>
    public string PaymentMode { get; set; } = "Cash";
    /// <summary>Amount collected now. Remainder becomes the customer's outstanding (Udhaar).</summary>
    public decimal PaidAmount { get; set; }
    public string? Notes { get; set; }
    /// <summary>Send the bill to the customer on WhatsApp.</summary>
    public bool SendWhatsApp { get; set; } = true;
    /// <summary>
    /// Counter checkout: how the money was taken, e.g. Rs.300 cash + Rs.700 card.
    /// When given, PaidAmount / PaymentMode are worked out from these.
    /// </summary>
    public List<TenderRequest>? Tenders { get; set; }
    /// <summary>Cash the customer handed over, so the receipt can show the change.</summary>
    public decimal? CashTendered { get; set; }
}

/// <summary>One way the customer paid at the counter.</summary>
public class TenderRequest
{
    /// <summary>Cash / UPI / Card / BankTransfer</summary>
    [Required] public string Mode { get; set; } = "Cash";
    [Range(0.01, 99999999)] public decimal Amount { get; set; }
    /// <summary>UPI UTR or bank reference.</summary>
    public string? ReferenceNo { get; set; }
    public CardDetails? Card { get; set; }
}

/// <summary>
/// A card charged on the shop's card machine. Never the full card number -
/// only what is printed on the charge slip.
/// </summary>
public class CardDetails
{
    /// <summary>Domestic (Indian-issued) or International.</summary>
    public string Scope { get; set; } = "Domestic";
    /// <summary>Visa / Mastercard / RuPay / Amex / Diners / Discover / JCB / UnionPay / Maestro / Other</summary>
    public string? Network { get; set; }
    /// <summary>Debit / Credit / Prepaid</summary>
    public string? Type { get; set; }
    [RegularExpression(@"^\d{4}$", ErrorMessage = "Card last 4 must be 4 digits.")]
    public string? Last4 { get; set; }
    [StringLength(20)] public string? ApprovalCode { get; set; }
}

public class TenderDto
{
    public string ReceiptNumber { get; set; } = "";
    public string Mode { get; set; } = "";
    public decimal Amount { get; set; }
    public string? ReferenceNo { get; set; }
    public string? CardScope { get; set; }
    public string? CardNetwork { get; set; }
    public string? CardType { get; set; }
    public string? CardLast4 { get; set; }
    public string? CardApprovalCode { get; set; }
    public DateTime PaidOn { get; set; }
}

public class InvoiceItemDto
{
    public int Id { get; set; }
    public int? ProductId { get; set; }
    public string ProductName { get; set; } = "";
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal TaxPercent { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal LineTotal { get; set; }
}

public class InvoiceDto
{
    public int Id { get; set; }
    public string InvoiceNumber { get; set; } = "";
    public DateTime InvoiceDate { get; set; }
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    // Shop letterhead, so the app can print a proper invoice without a second call.
    public string BusinessMobile { get; set; } = "";
    public string? BusinessAddress { get; set; }
    public string? BusinessGstNumber { get; set; }
    /// <summary>The shop's UPI ID, so the bill can carry a scan-to-pay QR.</summary>
    public string? BusinessUpiId { get; set; }
    public string? BusinessUpiName { get; set; }
    // Bill design set by the shop in its profile.
    public string? BusinessType { get; set; }
    public string? BusinessTagline { get; set; }
    public string? BusinessEmail { get; set; }
    public string? LogoUrl { get; set; }
    public string? SignatureUrl { get; set; }
    public string? SignatoryName { get; set; }
    public string? InvoiceTerms { get; set; }
    public string? ReceiptFooter { get; set; }
    public bool ShowLogoOnReceipt { get; set; } = true;
    public bool ShowSignature { get; set; } = true;
    public int CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public string CustomerMobile { get; set; } = "";
    public string? CustomerAddress { get; set; }
    /// <summary>What the customer owes this shop in total, this bill included.</summary>
    public decimal CustomerOutstanding { get; set; }
    public decimal SubTotal { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal GrandTotal { get; set; }
    public decimal PaidAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public string PaymentMode { get; set; } = "";
    public string Status { get; set; } = "";
    public string? Notes { get; set; }
    public List<InvoiceItemDto> Items { get; set; } = new();
    public string? WhatsAppLink { get; set; }
    /// <summary>Worker who billed it; null means the owner.</summary>
    public int? BilledByWorkerId { get; set; }
    public string? BilledByName { get; set; }
    public decimal? CashTendered { get; set; }
    public decimal? ChangeReturned { get; set; }
    /// <summary>Every payment against this bill: cash, UPI, card (with card details).</summary>
    public List<TenderDto> Tenders { get; set; } = new();
}

// ---------------------------- payments ---------------------------------

public class RecordPaymentRequest
{
    [Required] public int CustomerId { get; set; }
    public int? InvoiceId { get; set; }
    [Range(0.01, 99999999)] public decimal Amount { get; set; }
    public string Mode { get; set; } = "Cash";
    public string? ReferenceNo { get; set; }
    public string? Note { get; set; }
    public bool SendWhatsApp { get; set; } = true;
    /// <summary>When Mode is Card: what the card machine slip shows.</summary>
    public CardDetails? Card { get; set; }
}

public class PaymentDto
{
    public int Id { get; set; }
    public string ReceiptNumber { get; set; } = "";
    public int CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public int? InvoiceId { get; set; }
    public decimal Amount { get; set; }
    public string Mode { get; set; } = "";
    public string? ReferenceNo { get; set; }
    public DateTime PaidOn { get; set; }
    public decimal OutstandingAfter { get; set; }
    public string? CardScope { get; set; }
    public string? CardNetwork { get; set; }
    public string? CardLast4 { get; set; }
}

// ----------------------------- credits ---------------------------------

public class IssueCreditRequest
{
    [Required] public int CustomerId { get; set; }
    [Range(1, 99999999)] public decimal Amount { get; set; }
    public string? Reason { get; set; }
    public DateOnly? ExpiryDate { get; set; }
    public bool SendWhatsApp { get; set; } = true;
}

public class CreditGrantDto
{
    public int Id { get; set; }
    public string CreditCode { get; set; } = "";
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    public int CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public string CustomerMobile { get; set; } = "";
    public decimal Amount { get; set; }
    public decimal ClaimedAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public string? Reason { get; set; }
    public DateOnly? ExpiryDate { get; set; }
    public string Status { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public string? WhatsAppLink { get; set; }
}

public class ClaimCreditRequest
{
    [Required] public int CreditGrantId { get; set; }
    /// <summary>Leave null or 0 to claim the whole remaining balance.</summary>
    public decimal? Amount { get; set; }
    public string? Remarks { get; set; }
}

public class ProcessClaimRequest
{
    public bool Approve { get; set; } = true;
    public string? Remarks { get; set; }
}

public class CreditClaimDto
{
    public int Id { get; set; }
    public int CreditGrantId { get; set; }
    public string CreditCode { get; set; } = "";
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    public int CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public string CustomerMobile { get; set; } = "";
    public decimal Amount { get; set; }
    public string Status { get; set; } = "";
    public string? Remarks { get; set; }
    public DateTime RequestedAt { get; set; }
    public DateTime? ProcessedAt { get; set; }
}

// --------------------------- dashboards --------------------------------

public class OwnerDashboardDto
{
    public string BusinessName { get; set; } = "";
    public decimal TodaySales { get; set; }
    public decimal MonthSales { get; set; }
    public decimal TotalReceivable { get; set; }
    public decimal TodayCollection { get; set; }
    public decimal OutstandingCreditIssued { get; set; }
    public int CustomerCount { get; set; }
    public int ProductCount { get; set; }
    public int LowStockCount { get; set; }
    public int PendingClaimCount { get; set; }
    public int InvoiceCountThisMonth { get; set; }
    public decimal MonthExpenses { get; set; }
    public List<InvoiceDto> RecentInvoices { get; set; } = new();
}

public class CustomerDashboardDto
{
    public string FullName { get; set; } = "";
    public string Mobile { get; set; } = "";
    public decimal TotalOutstanding { get; set; }
    public decimal TotalCreditAvailable { get; set; }
    public int BillCount { get; set; }
    public int ShopCount { get; set; }
    public List<CustomerShopSummaryDto> Shops { get; set; } = new();
}

public class CustomerShopSummaryDto
{
    public int CustomerId { get; set; }
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    public string BusinessMobile { get; set; } = "";
    public decimal Outstanding { get; set; }
    public decimal CreditAvailable { get; set; }
    public bool IsTrusted { get; set; }
}

public class AdminDashboardDto
{
    public int BusinessCount { get; set; }
    public int ActiveBusinessCount { get; set; }
    public int BusinessUserCount { get; set; }
    public int CustomerUserCount { get; set; }
    public int InvoiceCount { get; set; }
    public decimal TotalSales { get; set; }
    public decimal TotalReceivable { get; set; }
    public decimal TotalCreditIssued { get; set; }
    public decimal TotalCreditUnclaimed { get; set; }
    public int WhatsAppSent { get; set; }
    public int WhatsAppFailed { get; set; }
}

public class AdminBusinessDto
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string? OwnerName { get; set; }
    public string Mobile { get; set; } = "";
    public string? City { get; set; }
    public bool IsActive { get; set; }
    public int CustomerCount { get; set; }
    public int InvoiceCount { get; set; }
    public decimal TotalSales { get; set; }
    public decimal Receivable { get; set; }
    public DateTime CreatedAt { get; set; }
    public int OwnerUserId { get; set; }
    public string BusinessType { get; set; } = "Retail";
    public string? LogoUrl { get; set; }
    public int WorkerCount { get; set; }
}

public class AdminUserDto
{
    public int Id { get; set; }
    public string Mobile { get; set; } = "";
    public string FullName { get; set; } = "";
    public string Role { get; set; } = "";
    public int? BusinessId { get; set; }
    public string? BusinessName { get; set; }
    public bool IsActive { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class AdminResetPasswordRequest
{
    [Required, MinLength(6)] public string NewPassword { get; set; } = "";
}

public class WhatsAppMessageDto
{
    public int Id { get; set; }
    public int? BusinessId { get; set; }
    public string? BusinessName { get; set; }
    public string ToMobile { get; set; } = "";
    public string Template { get; set; } = "";
    public string Body { get; set; } = "";
    public string? DeepLink { get; set; }
    public string Status { get; set; } = "";
    public string? Provider { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? SentAt { get; set; }
}

// -------------------------- preferences --------------------------------

public class PreferencesRequest
{
    /// <summary>System | Light | Dark</summary>
    [Required] public string ThemeMode { get; set; } = "System";
    /// <summary>One of the preset palette keys.</summary>
    [Required] public string ThemeName { get; set; } = "Classic";
}

// ------------------------ admin drill-downs ----------------------------

public class AdminUserDetailDto
{
    public AdminUserDto Account { get; set; } = new();
    public AdminBusinessProfileDto? Business { get; set; }
    public AdminBusinessStatsDto Stats { get; set; } = new();
    public List<CustomerDto> Customers { get; set; } = new();
}

public class AdminBusinessProfileDto
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
    public string InvoicePrefix { get; set; } = "";
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    /// <summary>Address lines joined for display.</summary>
    public string FullAddress { get; set; } = "";
}

public class AdminBusinessStatsDto
{
    public int CustomerCount { get; set; }
    public int TrustedCustomerCount { get; set; }
    public int ProductCount { get; set; }
    public int LowStockCount { get; set; }
    public int InvoiceCount { get; set; }
    public decimal TotalSales { get; set; }
    public decimal TotalCollected { get; set; }
    public decimal Receivable { get; set; }
    public decimal CreditIssued { get; set; }
    public decimal CreditUnclaimed { get; set; }
    public int PendingClaimCount { get; set; }
    public int WhatsAppSent { get; set; }
    public DateTime? LastInvoiceOn { get; set; }
    public decimal TotalExpenses { get; set; }
    public decimal TotalDiscount { get; set; }
    public decimal TotalTax { get; set; }
    public decimal NetAfterExpenses { get; set; }
}

public class AdminCustomerDetailDto
{
    public CustomerDto Customer { get; set; } = new();
    public string BusinessName { get; set; } = "";
    public string BusinessMobile { get; set; } = "";
    public AdminUserDto? Account { get; set; }
    public CustomerInsightDto Insight { get; set; } = new();
    public List<CustomerShopSummaryDto> OtherShops { get; set; } = new();
    public List<InvoiceDto> Bills { get; set; } = new();
    public List<PaymentDto> Payments { get; set; } = new();
    public List<CreditGrantDto> Credits { get; set; } = new();
    public List<CreditClaimDto> Claims { get; set; } = new();
    public List<LedgerEntryDto> Ledger { get; set; } = new();
    public List<WhatsAppMessageDto> Messages { get; set; } = new();
}

// --------------------------- lookup ------------------------------------

public class CustomerInsightDto
{
    public bool Found { get; set; }
    public string Mobile { get; set; } = "";
    public string Name { get; set; } = "";
    public bool HasAppAccount { get; set; }
    public DateTime? MemberSince { get; set; }
    public decimal? Rating { get; set; }
    public string RatingLabel { get; set; } = "";
    public int ShopCount { get; set; }
    public int TotalBills { get; set; }
    public string PaymentSignal { get; set; } = "";
    public bool HasOverdueElsewhere { get; set; }
    public string Summary { get; set; } = "";
    public CustomerInsightLocalDto? ThisShop { get; set; }
}

public class CustomerInsightLocalDto
{
    public int CustomerId { get; set; }
    public string Name { get; set; } = "";
    public bool IsTrusted { get; set; }
    public decimal CreditLimit { get; set; }
    public decimal OutstandingBalance { get; set; }
    public decimal CreditBalance { get; set; }
    public int BillCount { get; set; }
    public DateTime? LastBillOn { get; set; }
}
