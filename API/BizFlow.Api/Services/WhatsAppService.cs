using System.Text;
using System.Text.Json;
using BizFlow.Api.Data;
using BizFlow.Api.Entities;

namespace BizFlow.Api.Services;

public class WhatsAppOptions
{
    /// <summary>"Log" (default, dev) or "MetaCloud" (WhatsApp Business Cloud API).</summary>
    public string Provider { get; set; } = "Log";
    public string CountryCode { get; set; } = "91";
    // Meta WhatsApp Cloud API settings - fill these in to send for real.
    public string ApiBaseUrl { get; set; } = "https://graph.facebook.com/v21.0";
    public string PhoneNumberId { get; set; } = "";
    public string AccessToken { get; set; } = "";
}

public interface IWhatsAppService
{
    /// <summary>Queues + attempts delivery, and always records the message in the outbox.</summary>
    Task<WhatsAppMessage> SendAsync(string template, string toMobile, string body,
                                    int? businessId = null, int? customerId = null,
                                    CancellationToken ct = default);
}

public class WhatsAppService : IWhatsAppService
{
    private readonly AppDbContext _db;
    private readonly WhatsAppOptions _opt;
    private readonly IHttpClientFactory _http;
    private readonly ILogger<WhatsAppService> _log;

    public WhatsAppService(AppDbContext db, WhatsAppOptions opt,
                           IHttpClientFactory http, ILogger<WhatsAppService> log)
    {
        _db = db; _opt = opt; _http = http; _log = log;
    }

    public async Task<WhatsAppMessage> SendAsync(string template, string toMobile, string body,
                                                 int? businessId = null, int? customerId = null,
                                                 CancellationToken ct = default)
    {
        var msg = new WhatsAppMessage
        {
            BusinessId = businessId,
            CustomerId = customerId,
            ToMobile   = toMobile,
            Template   = template,
            Body       = body,
            DeepLink   = BuildDeepLink(toMobile, body),
            Provider   = _opt.Provider,
            Status     = "Queued"
        };
        _db.WhatsAppMessages.Add(msg);
        await _db.SaveChangesAsync(ct);

        try
        {
            if (_opt.Provider.Equals("MetaCloud", StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(_opt.AccessToken)
                && !string.IsNullOrWhiteSpace(_opt.PhoneNumberId))
            {
                msg.ProviderMessageId = await SendViaMetaCloudAsync(toMobile, body, ct);
            }
            else
            {
                // Dev mode: nothing is actually transmitted. The message body and the
                // wa.me deep link are stored so the mobile app can open WhatsApp itself.
                _log.LogInformation("[WhatsApp:{Template}] -> +{Cc}{Mobile}\n{Body}",
                                    template, _opt.CountryCode, toMobile, body);
                msg.Provider = "Log";
            }

            msg.Status = "Sent";
            msg.SentAt = DateTime.UtcNow;
        }
        catch (Exception ex)
        {
            msg.Status = "Failed";
            msg.ErrorMessage = ex.Message.Length > 500 ? ex.Message[..500] : ex.Message;
            _log.LogError(ex, "WhatsApp send failed for {Mobile}", toMobile);
        }

        await _db.SaveChangesAsync(ct);
        return msg;
    }

    private string BuildDeepLink(string mobile, string body)
    {
        var digits = new string(mobile.Where(char.IsDigit).ToArray());
        if (digits.Length == 10) digits = _opt.CountryCode + digits;
        return $"https://wa.me/{digits}?text={Uri.EscapeDataString(body)}";
    }

    private async Task<string?> SendViaMetaCloudAsync(string mobile, string body, CancellationToken ct)
    {
        var digits = new string(mobile.Where(char.IsDigit).ToArray());
        if (digits.Length == 10) digits = _opt.CountryCode + digits;

        var payload = new
        {
            messaging_product = "whatsapp",
            to = digits,
            type = "text",
            text = new { preview_url = false, body }
        };

        var client = _http.CreateClient();
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _opt.AccessToken);

        var url = $"{_opt.ApiBaseUrl.TrimEnd('/')}/{_opt.PhoneNumberId}/messages";
        using var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var res = await client.PostAsync(url, content, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);

        if (!res.IsSuccessStatusCode)
            throw new InvalidOperationException($"WhatsApp API {(int)res.StatusCode}: {raw}");

        using var doc = JsonDocument.Parse(raw);
        return doc.RootElement.TryGetProperty("messages", out var arr) && arr.GetArrayLength() > 0
            ? arr[0].GetProperty("id").GetString()
            : null;
    }
}

/// <summary>Plain-text WhatsApp bodies. Kept in one place so wording stays consistent.</summary>
public static class MessageTemplates
{
    private static string Rs(decimal v) => "Rs." + v.ToString("N2");
    private static DateTime Ist(DateTime utc) => IndiaTime.FromUtc(utc);

    // WhatsApp cannot colour text, so bills use its own formatting instead:
    // *bold*, a ``` monospace block for the item table (columns line up on every
    // phone) and coloured emoji markers for paid / due.
    private const int TableWidth = 30;
    private static string Amt(decimal v) => v.ToString("N2");
    private static string Rule(char c = '-') => new string(c, TableWidth);

    private static IEnumerable<string> Wrap(string text, int width)
    {
        var words = (text ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var line = "";
        foreach (var w0 in words)
        {
            var w = w0;
            while (w.Length > width) { if (line.Length > 0) { yield return line; line = ""; } yield return w[..width]; w = w[width..]; }
            if (line.Length == 0) line = w;
            else if (line.Length + 1 + w.Length <= width) line += " " + w;
            else { yield return line; line = w; }
        }
        if (line.Length > 0) yield return line;
    }

    private static string TotalLine(string label, string value) =>
        label + value.PadLeft(Math.Max(1, TableWidth - label.Length));

    public static string Bill(Business biz, Customer cust, Invoice inv)
    {
        const int nameW = 12, qtyW = 5, amtW = 10;   // 3 + 12 + 5 + 10 = 30

        var sb = new StringBuilder();
        sb.AppendLine($"🧾 *{biz.Name.ToUpperInvariant()}*");
        var contact = string.IsNullOrWhiteSpace(biz.City) ? $"📞 {biz.Mobile}" : $"📍 {biz.City}  ·  📞 {biz.Mobile}";
        sb.AppendLine(contact);
        if (!string.IsNullOrWhiteSpace(biz.GstNumber)) sb.AppendLine($"GSTIN: {biz.GstNumber}");
        sb.AppendLine("━━━━━━━━━━━━━━━━━━");
        sb.AppendLine($"Hello *{cust.Name}* 🙏, here is your bill.");
        sb.AppendLine($"🔖 Bill No : *{inv.InvoiceNumber}*");
        sb.AppendLine($"📅 Date    : {Ist(inv.InvoiceDate):dd-MMM-yyyy hh:mm tt}");
        sb.AppendLine();

        sb.AppendLine("```");
        sb.AppendLine("#  " + "ITEM".PadRight(nameW) + "QTY".PadLeft(qtyW) + "AMOUNT".PadLeft(amtW));
        sb.AppendLine(Rule());
        var n = 1;
        foreach (var it in inv.Items)
        {
            var nameLines = Wrap(it.ProductName, nameW).ToList();
            if (nameLines.Count == 0) nameLines.Add("-");
            var idx = n++.ToString().PadRight(3);
            sb.AppendLine(idx + nameLines[0].PadRight(nameW)
                              + it.Quantity.ToString("0.###").PadLeft(qtyW)
                              + Amt(it.LineTotal).PadLeft(amtW));
            foreach (var extra in nameLines.Skip(1)) sb.AppendLine("   " + extra);
            var detail = $"   @{Amt(it.UnitPrice)}" + (it.TaxPercent > 0 ? $" +{it.TaxPercent:0.##}%GST" : "");
            sb.AppendLine(detail);
        }
        sb.AppendLine(Rule());
        sb.AppendLine(TotalLine("Sub Total", Amt(inv.SubTotal)));
        if (inv.DiscountAmount > 0) sb.AppendLine(TotalLine("Discount", "-" + Amt(inv.DiscountAmount)));
        if (inv.TaxAmount > 0)      sb.AppendLine(TotalLine("GST", Amt(inv.TaxAmount)));
        sb.AppendLine(Rule('='));
        sb.AppendLine(TotalLine("TOTAL", Rs(inv.GrandTotal)));
        sb.AppendLine("```");

        sb.AppendLine($"💰 *Total : {Rs(inv.GrandTotal)}*");
        sb.AppendLine($"✅ Paid  : {Rs(inv.PaidAmount)}" + (inv.PaidAmount > 0 ? $" ({inv.PaymentMode})" : ""));
        if (inv.BalanceAmount > 0)
            sb.AppendLine($"🔴 *Balance (Udhaar) : {Rs(inv.BalanceAmount)}*");
        else
            sb.AppendLine("🟢 *PAID IN FULL*");
        if (cust.OutstandingBalance > inv.BalanceAmount)
            sb.AppendLine($"🟠 Total outstanding (all bills): *{Rs(cust.OutstandingBalance)}*");
        if (inv.BalanceAmount > 0 && !string.IsNullOrWhiteSpace(biz.UpiId))
        {
            sb.AppendLine();
            sb.AppendLine($"💳 *Pay by UPI:* {biz.UpiId}");
            sb.AppendLine("Or open the BizBill app -> Pay to pay with one tap.");
        }
        sb.AppendLine("━━━━━━━━━━━━━━━━━━");
        sb.AppendLine("Thank you for your business! 🙏");
        return sb.ToString();
    }

    public static string CreditIssued(Business biz, Customer cust, CreditGrant grant)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"*{biz.Name}*");
        sb.AppendLine("--------------------------------");
        sb.AppendLine($"Hello {cust.Name},");
        sb.AppendLine($"You have received credit of *{Rs(grant.Amount)}*.");
        sb.AppendLine($"Credit Code : {grant.CreditCode}");
        if (!string.IsNullOrWhiteSpace(grant.Reason)) sb.AppendLine($"Reason      : {grant.Reason}");
        if (grant.ExpiryDate.HasValue)                sb.AppendLine($"Valid Till  : {grant.ExpiryDate:dd-MMM-yyyy}");
        sb.AppendLine("--------------------------------");
        sb.AppendLine("Open the BizBill app -> My Credits -> Claim to use this amount on your next purchase.");
        return sb.ToString();
    }

    public static string ClaimRequested(Business biz, Customer cust, CreditClaim claim, CreditGrant grant) =>
        $"*{biz.Name}*\n{cust.Name} ({cust.Mobile}) has requested to claim {Rs(claim.Amount)} "
      + $"from credit {grant.CreditCode}.\nApprove it in the BizBill app -> Credits -> Claims.";

    public static string ClaimApproved(Business biz, Customer cust, CreditClaim claim, CreditGrant grant)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"*{biz.Name}*");
        sb.AppendLine($"Hello {cust.Name},");
        sb.AppendLine($"Your credit claim of *{Rs(claim.Amount)}* (code {grant.CreditCode}) is APPROVED.");
        sb.AppendLine($"Remaining credit : {Rs(grant.BalanceAmount)}");
        sb.AppendLine($"Your outstanding : {Rs(cust.OutstandingBalance)}");
        return sb.ToString();
    }

    public static string ClaimRejected(Business biz, Customer cust, CreditClaim claim) =>
        $"*{biz.Name}*\nHello {cust.Name}, your credit claim of {Rs(claim.Amount)} was not approved."
      + (string.IsNullOrWhiteSpace(claim.Remarks) ? "" : $"\nReason: {claim.Remarks}");

    public static string PaymentReceipt(Business biz, Customer cust, Payment pay)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"*{biz.Name}* - Payment Receipt");
        sb.AppendLine("--------------------------------");
        sb.AppendLine($"Receipt No : {pay.ReceiptNumber}");
        sb.AppendLine($"Date       : {pay.PaidOn.ToLocalTime():dd-MMM-yyyy hh:mm tt}");
        sb.AppendLine($"Received   : *{Rs(pay.Amount)}* ({pay.Mode})");
        if (!string.IsNullOrWhiteSpace(pay.ReferenceNo)) sb.AppendLine($"Reference  : {pay.ReferenceNo}");
        sb.AppendLine("--------------------------------");
        sb.AppendLine($"Balance outstanding : {Rs(cust.OutstandingBalance)}");
        sb.AppendLine("Thank you!");
        return sb.ToString();
    }

    /// <summary>
    /// The bill re-issued after a payment lands: same bill, updated figures, so the
    /// customer sees Total - Paid = Remaining without a second sale being invented.
    /// </summary>
    public static string ReIssuedBill(Business biz, Customer cust, Invoice inv, decimal paidNow)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"*{biz.Name}*");
        sb.AppendLine("UPDATED BILL");
        sb.AppendLine("--------------------------------");
        sb.AppendLine($"Hello {cust.Name}, we received {Rs(paidNow)}. Thank you.");
        sb.AppendLine($"Bill No : {inv.InvoiceNumber}");
        sb.AppendLine($"Date    : {inv.InvoiceDate.ToLocalTime():dd-MMM-yyyy}");
        sb.AppendLine("--------------------------------");
        sb.AppendLine($"Bill Total    : {Rs(inv.GrandTotal)}");
        sb.AppendLine($"Total Paid    : {Rs(inv.PaidAmount)}");
        sb.AppendLine($"*Remaining    : {Rs(inv.BalanceAmount)}*");
        sb.AppendLine("--------------------------------");
        sb.AppendLine(inv.BalanceAmount <= 0
            ? "This bill is fully settled. Thank you!"
            : $"Your total outstanding with us: {Rs(cust.OutstandingBalance)}");
        return sb.ToString();
    }

    /// <summary>
    /// A running account: the new bill plus every earlier unpaid bill with its date,
    /// so the customer sees one combined amount due.
    /// </summary>
    public static string Statement(Business biz, Customer cust, IEnumerable<Invoice> unpaid,
                                   Invoice? newest = null)
    {
        var rows = unpaid.OrderBy(i => i.InvoiceDate).ToList();

        var sb = new StringBuilder();
        sb.AppendLine($"*{biz.Name}*");
        sb.AppendLine("ACCOUNT STATEMENT");
        sb.AppendLine($"Date: {DateTime.UtcNow.ToLocalTime():dd-MMM-yyyy}");
        sb.AppendLine("--------------------------------");
        sb.AppendLine($"Hello {cust.Name}, here is your account.");
        sb.AppendLine();

        if (newest is not null)
        {
            sb.AppendLine("*NEW BILL*");
            sb.AppendLine($"{newest.InvoiceDate.ToLocalTime():dd-MMM-yyyy}  {newest.InvoiceNumber}");
            foreach (var it in newest.Items)
                sb.AppendLine($"  {it.ProductName} x {it.Quantity:0.###} = {Rs(it.LineTotal)}");
            sb.AppendLine($"  Bill total : {Rs(newest.GrandTotal)}");
            if (newest.PaidAmount > 0) sb.AppendLine($"  Paid now   : {Rs(newest.PaidAmount)}");
            sb.AppendLine($"  Due        : {Rs(newest.BalanceAmount)}");
            sb.AppendLine();
        }

        var earlier = newest is null ? rows : rows.Where(i => i.Id != newest.Id).ToList();
        if (earlier.Count > 0)
        {
            sb.AppendLine("*EARLIER UNPAID BILLS*");
            foreach (var i in earlier)
                sb.AppendLine($"  {i.InvoiceDate.ToLocalTime():dd-MMM-yyyy}  {i.InvoiceNumber}"
                            + $"  due {Rs(i.BalanceAmount)}");
            sb.AppendLine($"  Earlier due : {Rs(earlier.Sum(i => i.BalanceAmount))}");
            sb.AppendLine();
        }

        sb.AppendLine("--------------------------------");
        sb.AppendLine($"*TOTAL AMOUNT DUE : {Rs(cust.OutstandingBalance)}*");
        if (cust.CreditBalance > 0)
            sb.AppendLine($"Credit you can claim: {Rs(cust.CreditBalance)}");
        sb.AppendLine("--------------------------------");
        sb.AppendLine("Pay by UPI and send the screenshot in the BizBill app.");
        return sb.ToString();
    }

    public static string ProofReceived(Business biz, Customer cust, decimal amount, string? reference,
                                       string? invoiceNumber = null, bool hasScreenshot = false) =>
        $"💰 *Payment received - {biz.Name}*\n"
      + $"*{cust.Name}* ({cust.Mobile}) says they paid *{Rs(amount)}* by UPI."
      + (string.IsNullOrWhiteSpace(invoiceNumber) ? "" : $"\n🧾 Bill: {invoiceNumber}")
      + (string.IsNullOrWhiteSpace(reference) ? "" : $"\n🔖 UPI ref (UTR): {reference}")
      + (hasScreenshot ? "\n📎 Screenshot attached in the app." : "")
      + $"\n📊 Their balance before this: {Rs(cust.OutstandingBalance)}"
      + "\n\nCheck your bank/UPI app, then open BizBill -> Customer payments to approve it.";

    public static string ProofRejected(Business biz, Customer cust, decimal amount, string? remarks) =>
        $"*{biz.Name}*\nHello {cust.Name}, we could not confirm your payment of {Rs(amount)}."
      + (string.IsNullOrWhiteSpace(remarks) ? "" : $"\nReason: {remarks}")
      + "\nPlease check the reference and send it again.";

    public static string Welcome(Business biz, Customer cust) =>
        $"*{biz.Name}*\nHello {cust.Name}, your customer account is ready.\n"
      + $"Login to the BizBill app with your mobile number {cust.Mobile} to see your bills and credits.";
}
