using System.ComponentModel.DataAnnotations;

namespace BizFlow.Api.Dtos;

// ----------------------------- expenses --------------------------------

public class ExpenseDto
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    public string Category { get; set; } = "";
    public decimal Amount { get; set; }
    public DateTime ExpenseDate { get; set; }
    public string PaymentMode { get; set; } = "";
    public string? PaidTo { get; set; }
    public string? Note { get; set; }
    public bool IsCancelled { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateExpenseRequest
{
    [Required, MaxLength(40)] public string Category { get; set; } = "";
    [Range(0.01, 99999999)] public decimal Amount { get; set; }
    public DateTime? ExpenseDate { get; set; }
    [MaxLength(20)] public string PaymentMode { get; set; } = "Cash";
    [MaxLength(120)] public string? PaidTo { get; set; }
    [MaxLength(250)] public string? Note { get; set; }
}

public class ExpenseSummaryDto
{
    public decimal Total { get; set; }
    public int Count { get; set; }
    public List<NamedAmountDto> ByCategory { get; set; } = new();
    public List<ExpenseDto> Items { get; set; } = new();
}

// ----------------------------- analytics -------------------------------

public class NamedAmountDto
{
    public string Name { get; set; } = "";
    public decimal Amount { get; set; }
    public int Count { get; set; }
}

/// <summary>One bucket (a day or a month) on the trend chart.</summary>
public class TrendPointDto
{
    public string Label { get; set; } = "";
    public DateTime Start { get; set; }
    public decimal Sales { get; set; }
    public decimal Collected { get; set; }
    public decimal Expenses { get; set; }
    public int Bills { get; set; }
    public int NewCustomers { get; set; }
}

public class ShopPerformanceDto
{
    public int BusinessId { get; set; }
    public int OwnerUserId { get; set; }
    public string ShopName { get; set; } = "";
    public string? OwnerName { get; set; }
    public string? City { get; set; }
    public decimal Sales { get; set; }
    public decimal Expenses { get; set; }
    public decimal Net { get; set; }
    public decimal Receivable { get; set; }
    public int Bills { get; set; }
    public int Customers { get; set; }
}

public class AnalyticsKpiDto
{
    public decimal GrossSales { get; set; }
    public decimal Discounts { get; set; }
    public decimal Tax { get; set; }
    public decimal Collected { get; set; }
    public decimal Expenditure { get; set; }
    /// <summary>Gross sales minus expenditure.</summary>
    public decimal Net { get; set; }
    public decimal Receivable { get; set; }
    public decimal CreditIssued { get; set; }
    public int Bills { get; set; }
    public decimal AverageBill { get; set; }
    public int Shops { get; set; }
    public int ActiveShops { get; set; }
    public int ShopOwners { get; set; }
    /// <summary>Distinct people by mobile - one person at three shops counts once.</summary>
    public int Customers { get; set; }
    /// <summary>Shop-customer links; a person at three shops counts three times.</summary>
    public int CustomerRecords { get; set; }
    public int CustomersWithApp { get; set; }
    public int MultiShopCustomers { get; set; }
}

public class AnalyticsDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    /// <summary>"Day" or "Month".</summary>
    public string Granularity { get; set; } = "Day";
    public int? BusinessId { get; set; }
    public AnalyticsKpiDto Kpis { get; set; } = new();
    public List<TrendPointDto> Trend { get; set; } = new();
    public List<ShopPerformanceDto> TopShops { get; set; } = new();
    public List<NamedAmountDto> PaymentModes { get; set; } = new();
    public List<NamedAmountDto> ExpenseCategories { get; set; } = new();
    public List<NamedAmountDto> BillStatus { get; set; } = new();
    public List<NamedAmountDto> TopProducts { get; set; } = new();
}

// --------------------- customers grouped by person ---------------------

/// <summary>A real person (one mobile) and how many shops they buy from.</summary>
public class CustomerPersonDto
{
    public string Mobile { get; set; } = "";
    public string Name { get; set; } = "";
    public int ShopCount { get; set; }
    public decimal TotalOutstanding { get; set; }
    public decimal TotalCredit { get; set; }
    public decimal TotalBilled { get; set; }
    public int BillCount { get; set; }
    public bool HasAppAccount { get; set; }
    public bool IsTrustedAnywhere { get; set; }
    public DateTime FirstSeen { get; set; }
}

public class CustomerPersonShopDto
{
    public int CustomerId { get; set; }
    public int BusinessId { get; set; }
    public string ShopName { get; set; } = "";
    public string ShopMobile { get; set; } = "";
    public string? ShopCity { get; set; }
    public int OwnerUserId { get; set; }
    public string? OwnerName { get; set; }
    public string NameAtShop { get; set; } = "";
    public bool IsTrusted { get; set; }
    public decimal CreditLimit { get; set; }
    public decimal Outstanding { get; set; }
    public decimal CreditAvailable { get; set; }
    public decimal TotalBilled { get; set; }
    public decimal TotalPaid { get; set; }
    public int BillCount { get; set; }
    public DateTime? LastBillOn { get; set; }
    public DateTime CustomerSince { get; set; }
}

public class CustomerPersonDetailDto
{
    public CustomerPersonDto Person { get; set; } = new();
    public AdminUserDto? Account { get; set; }
    public CustomerInsightDto Insight { get; set; } = new();
    public List<CustomerPersonShopDto> Shops { get; set; } = new();
    public List<InvoiceDto> RecentBills { get; set; } = new();
}
