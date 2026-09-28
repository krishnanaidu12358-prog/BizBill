using BizFlow.Api.Data;
using BizFlow.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Services;

/// <summary>
/// Cross-shop reputation for a mobile number. Deliberately exposes no rupee
/// amounts or shop names belonging to other businesses - only a score, a count
/// and a coarse payment signal. The requesting shop's own figures come back in
/// full, because it already owns that data.
/// </summary>
public class CustomerInsight
{
    public bool Found { get; set; }
    public string Mobile { get; set; } = "";
    public string Name { get; set; } = "";
    public bool HasAppAccount { get; set; }
    public DateTime? MemberSince { get; set; }

    /// <summary>1.0 - 5.0, or null when there is no billing history to judge.</summary>
    public decimal? Rating { get; set; }
    public string RatingLabel { get; set; } = "New customer";

    /// <summary>How many shops on the platform bill this number.</summary>
    public int ShopCount { get; set; }
    public int TotalBills { get; set; }

    /// <summary>Good | Watch | Overdue</summary>
    public string PaymentSignal { get; set; } = "Good";
    public bool HasOverdueElsewhere { get; set; }
    public string Summary { get; set; } = "";

    /// <summary>Null when this number does not buy from the requesting shop yet.</summary>
    public CustomerInsightLocal? ThisShop { get; set; }
}

public class CustomerInsightLocal
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

public interface ICustomerInsightService
{
    Task<CustomerInsight> LookupAsync(string mobile, int? requestingBusinessId, CancellationToken ct = default);
}

public class CustomerInsightService : ICustomerInsightService
{
    private readonly AppDbContext _db;

    public CustomerInsightService(AppDbContext db) => _db = db;

    public async Task<CustomerInsight> LookupAsync(string mobile, int? requestingBusinessId,
                                                   CancellationToken ct = default)
    {
        var rows = await _db.Customers.AsNoTracking()
                            .Where(c => c.Mobile == mobile)
                            .ToListAsync(ct);

        if (rows.Count == 0)
            return new CustomerInsight
            {
                Found = false,
                Mobile = mobile,
                Summary = "No shop on BizBill has billed this number yet."
            };

        var ids = rows.Select(c => c.Id).ToList();

        var invoices = await _db.Invoices.AsNoTracking()
                                .Where(i => ids.Contains(i.CustomerId) && i.Status != InvoiceStatus.Cancelled)
                                .Select(i => new
                                {
                                    i.CustomerId,
                                    i.BusinessId,
                                    i.GrandTotal,
                                    i.BalanceAmount,
                                    i.InvoiceDate
                                })
                                .ToListAsync(ct);

        var totalBilled  = invoices.Sum(i => i.GrandTotal);
        var outstanding  = rows.Sum(c => c.OutstandingBalance);
        var unpaid       = invoices.Where(i => i.BalanceAmount > 0).ToList();
        var oldestUnpaid = unpaid.Count == 0 ? (DateTime?)null : unpaid.Min(i => i.InvoiceDate);
        var overdueDays  = oldestUnpaid is null ? 0 : (int)(DateTime.UtcNow - oldestUnpaid.Value).TotalDays;

        var insight = new CustomerInsight
        {
            Found         = true,
            Mobile        = mobile,
            Name          = rows.OrderBy(c => c.Id).First().Name,
            HasAppAccount = rows.Any(c => c.UserId != null),
            MemberSince   = rows.Min(c => c.CreatedAt),
            ShopCount     = rows.Select(c => c.BusinessId).Distinct().Count(),
            TotalBills    = invoices.Count
        };

        // --- score -------------------------------------------------------
        if (totalBilled > 0)
        {
            var settled  = Math.Max(0, totalBilled - outstanding);
            var payRatio = Math.Clamp(settled / totalBilled, 0m, 1m);

            var penalty = overdueDays switch
            {
                > 90 => 1.5m,
                > 60 => 1.0m,
                > 30 => 0.5m,
                _    => 0m
            };

            var score = Math.Clamp(1m + 4m * payRatio - penalty, 1m, 5m);
            insight.Rating = Math.Round(score, 1);
            insight.RatingLabel = score switch
            {
                >= 4.5m => "Excellent payer",
                >= 3.5m => "Good payer",
                >= 2.5m => "Fair",
                >= 1.5m => "Slow payer",
                _       => "High risk"
            };
        }
        else
        {
            insight.RatingLabel = "New customer";
        }

        // --- signal ------------------------------------------------------
        insight.PaymentSignal = overdueDays switch
        {
            > 60 => "Overdue",
            > 30 => "Watch",
            _    => "Good"
        };

        insight.HasOverdueElsewhere = unpaid.Any(i =>
            i.BusinessId != requestingBusinessId &&
            (DateTime.UtcNow - i.InvoiceDate).TotalDays > 30);

        insight.Summary = BuildSummary(insight, overdueDays);

        // --- the requesting shop's own record, in full --------------------
        if (requestingBusinessId is { } bizId)
        {
            var mine = rows.FirstOrDefault(c => c.BusinessId == bizId);
            if (mine is not null)
            {
                var myInvoices = invoices.Where(i => i.CustomerId == mine.Id).ToList();
                insight.ThisShop = new CustomerInsightLocal
                {
                    CustomerId         = mine.Id,
                    Name               = mine.Name,
                    IsTrusted          = mine.IsTrusted,
                    CreditLimit        = mine.CreditLimit,
                    OutstandingBalance = mine.OutstandingBalance,
                    CreditBalance      = mine.CreditBalance,
                    BillCount          = myInvoices.Count,
                    LastBillOn         = myInvoices.Count == 0
                        ? null
                        : myInvoices.Max(i => i.InvoiceDate)
                };
            }
        }

        return insight;
    }

    private static string BuildSummary(CustomerInsight i, int overdueDays)
    {
        var shops = i.ShopCount == 1 ? "1 shop" : $"{i.ShopCount} shops";

        if (i.Rating is null)
            return $"Known to {shops}, but has no billing history yet.";

        var text = $"{i.RatingLabel} - buys from {shops}, {i.TotalBills} bill(s) so far.";
        if (overdueDays > 30)
            text += $" Oldest unpaid bill is about {overdueDays} days old.";
        return text;
    }
}
