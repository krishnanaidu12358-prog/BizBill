using BizFlow.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Data;

/// <summary>
/// Creates the demo tenants, logins and a little history so the mobile app has
/// something to show on first run. Runs only when the database has no users.
/// </summary>
public static class DataSeeder
{
    public const string AdminPassword    = "Admin@123";
    public const string OwnerPassword    = "User@123";
    public const string CustomerPassword = "Cust@123";

    public static async Task SeedAsync(AppDbContext db, ILogger logger)
    {
        if (await db.Users.AnyAsync())
        {
            logger.LogInformation("Seed skipped - accounts already exist.");
            return;
        }

        logger.LogInformation("Seeding demo accounts ...");
        var hash = (string p) => BCrypt.Net.BCrypt.HashPassword(p);

        // ---------------------------------------------------------- admin
        db.Users.Add(new AppUser
        {
            Mobile = "9999900001", FullName = "Platform Super Admin",
            Email = "admin@bizflow.local", PasswordHash = hash(AdminPassword),
            Role = Roles.SuperAdmin
        });

        // ------------------------------------------------------- businesses
        var electricals = new Business
        {
            Name = "Sri Lakshmi Electricals", OwnerName = "Rajesh Kumar", Mobile = "9999911111",
            Email = "rajesh@srilakshmi.local", AddressLine = "12-3-45, Main Bazaar Road",
            City = "Hyderabad", State = "Telangana", Pincode = "500001",
            GstNumber = "36ABCDE1234F1Z5", InvoicePrefix = "SLE"
        };
        var kirana = new Business
        {
            Name = "Kittu Kirana Store", OwnerName = "Kittu Reddy", Mobile = "9999922222",
            Email = "kittu@kirana.local", AddressLine = "Shop 7, Gandhi Nagar",
            City = "Vijayawada", State = "Andhra Pradesh", Pincode = "520003",
            InvoicePrefix = "KKS"
        };
        db.Businesses.AddRange(electricals, kirana);
        await db.SaveChangesAsync();

        db.Users.AddRange(
            new AppUser
            {
                BusinessId = electricals.Id, Mobile = electricals.Mobile, FullName = "Rajesh Kumar",
                Email = electricals.Email, PasswordHash = hash(OwnerPassword), Role = Roles.BusinessUser
            },
            new AppUser
            {
                BusinessId = kirana.Id, Mobile = kirana.Mobile, FullName = "Kittu Reddy",
                Email = kirana.Email, PasswordHash = hash(OwnerPassword), Role = Roles.BusinessUser
            });

        // --------------------------------------------------- customer logins
        var rameshUser = new AppUser
        {
            Mobile = "9876500001", FullName = "Ramesh Kumar",
            PasswordHash = hash(CustomerPassword), Role = Roles.Customer
        };
        var sureshUser = new AppUser
        {
            Mobile = "9876500002", FullName = "Suresh Babu",
            PasswordHash = hash(CustomerPassword), Role = Roles.Customer
        };
        var lakshmiUser = new AppUser
        {
            Mobile = "9876500003", FullName = "Lakshmi Devi",
            PasswordHash = hash(CustomerPassword), Role = Roles.Customer
        };
        db.Users.AddRange(rameshUser, sureshUser, lakshmiUser);
        await db.SaveChangesAsync();

        // ------------------------------------------------------- customers
        // Ramesh buys from both shops - one login, two shop records.
        var rameshAtElec = NewCustomer(electricals, rameshUser, "Ramesh Kumar", "9876500001",
                                       "Flat 301, Sai Residency, Ameerpet", true, 10000);
        var sureshAtElec = NewCustomer(electricals, sureshUser, "Suresh Babu", "9876500002",
                                       "H.No 8-2-120, Banjara Hills", true, 5000);
        var anitaAtElec  = NewCustomer(electricals, null, "Anita Sharma", "9876500004",
                                       "Plot 45, Kukatpally", false, 0);
        var rameshAtKir  = NewCustomer(kirana, rameshUser, "Ramesh Kumar", "9876500001",
                                       "Flat 301, Sai Residency", true, 5000);
        var lakshmiAtKir = NewCustomer(kirana, lakshmiUser, "Lakshmi Devi", "9876500003",
                                       "D.No 22-14, Gandhi Nagar", true, 3000);
        db.Customers.AddRange(rameshAtElec, sureshAtElec, anitaAtElec, rameshAtKir, lakshmiAtKir);

        // -------------------------------------------------------- products
        var bulb   = NewProduct(electricals, "LED Bulb 9W",            "SLE-BULB-9",  "PCS", 120,  85,  12, 200, 25);
        var wire   = NewProduct(electricals, "Copper Wire 1.0sqmm 90m", "SLE-WIRE-1",  "ROLL", 1450, 1180, 12, 30, 5);
        var switch6= NewProduct(electricals, "Modular Switch 6A",       "SLE-SW-6",    "PCS", 45,   28,  12, 300, 50);
        var fan    = NewProduct(electricals, "Ceiling Fan 1200mm",      "SLE-FAN-12",  "PCS", 2350, 1850, 12, 12, 3);
        var mcb    = NewProduct(electricals, "MCB 32A Single Pole",     "SLE-MCB-32",  "PCS", 380,  260,  18, 40, 10);

        var rice   = NewProduct(kirana, "Sona Masoori Rice 25kg", "KKS-RICE-25", "BAG", 1450, 1290, 0, 25, 5);
        var sugar  = NewProduct(kirana, "Sugar 1kg",              "KKS-SUG-1",   "KG",  48,   42,   0, 120, 20);
        var dal    = NewProduct(kirana, "Toor Dal 1kg",           "KKS-DAL-1",   "KG",  165,  142,  0, 60, 10);
        var oil    = NewProduct(kirana, "Sunflower Oil 1L",       "KKS-OIL-1",   "LTR", 140,  122,  5, 80, 15);
        var tea    = NewProduct(kirana, "Tea Powder 250g",        "KKS-TEA-250", "PKT", 135,  108,  5, 50, 10);

        db.Products.AddRange(bulb, wire, switch6, fan, mcb, rice, sugar, dal, oil, tea);
        await db.SaveChangesAsync();

        // -------------------------------------------------------- invoices
        var seq = new Dictionary<int, int>();
        await AddInvoiceAsync(db, seq, electricals, rameshAtElec, "Cash",
            paid: null, // fully paid
            lines: new[] { (bulb, 2m), (mcb, 1m) });

        await AddInvoiceAsync(db, seq, electricals, rameshAtElec, "UPI",
            paid: 1000m,
            lines: new[] { (fan, 1m) });

        await AddInvoiceAsync(db, seq, electricals, sureshAtElec, "Credit",
            paid: 0m,
            lines: new[] { (switch6, 5m), (bulb, 1m) });

        await AddInvoiceAsync(db, seq, kirana, rameshAtKir, "Cash",
            paid: 546m,
            lines: new[] { (rice, 1m), (sugar, 2m) });

        await AddInvoiceAsync(db, seq, kirana, lakshmiAtKir, "UPI",
            paid: null,
            lines: new[] { (oil, 2m), (tea, 1m) });

        // ------------------------------------------------- credits + a claim
        var g1 = await AddCreditAsync(db, electricals, rameshAtElec, 500m, "Diwali festival credit");
        var g2 = await AddCreditAsync(db, electricals, sureshAtElec, 250m, "Loyalty bonus");
        var g3 = await AddCreditAsync(db, kirana,      rameshAtKir,  300m, "Referral reward");

        db.CreditClaims.Add(new CreditClaim
        {
            CreditGrantId = g1.Id, BusinessId = electricals.Id, CustomerId = rameshAtElec.Id,
            Amount = 500m, Status = ClaimStatus.Pending,
            Remarks = "Please adjust against my fan bill."
        });

        await db.SaveChangesAsync();
        logger.LogInformation("Seed complete: 2 businesses, {Users} logins, {Inv} bills, 3 credits.",
                              await db.Users.CountAsync(), await db.Invoices.CountAsync());
    }

    // ------------------------------------------------------------------

    private static Customer NewCustomer(Business biz, AppUser? user, string name, string mobile,
                                        string address, bool trusted, decimal limit) => new()
    {
        BusinessId = biz.Id, UserId = user?.Id, Name = name, Mobile = mobile,
        Address = address, IsTrusted = trusted, CreditLimit = limit
    };

    private static Product NewProduct(Business biz, string name, string sku, string unit,
                                      decimal sell, decimal buy, decimal tax,
                                      decimal stock, decimal minStock) => new()
    {
        BusinessId = biz.Id, Name = name, Sku = sku, Unit = unit,
        SellingPrice = sell, PurchasePrice = buy, TaxPercent = tax,
        StockQty = stock, MinStockQty = minStock
    };

    /// <summary>Mirrors InvoicesController.Create so seeded history stays internally consistent.</summary>
    private static async Task AddInvoiceAsync(AppDbContext db, Dictionary<int, int> seq,
                                              Business biz, Customer cust, string mode,
                                              decimal? paid, (Product product, decimal qty)[] lines)
    {
        seq[biz.Id] = seq.TryGetValue(biz.Id, out var n) ? n + 1 : 1;

        var inv = new Invoice
        {
            BusinessId    = biz.Id,
            CustomerId    = cust.Id,
            InvoiceNumber = $"{biz.InvoicePrefix}-{biz.Id:D3}-{seq[biz.Id]:D5}",
            InvoiceDate   = DateTime.UtcNow.AddDays(-seq[biz.Id]),
            PaymentMode   = mode
        };

        decimal sub = 0, tax = 0;
        foreach (var (product, qty) in lines)
        {
            var gross   = decimal.Round(product.SellingPrice * qty, 2);
            var lineTax = decimal.Round(gross * product.TaxPercent / 100m, 2);

            inv.Items.Add(new InvoiceItem
            {
                ProductId = product.Id, ProductName = product.Name, Quantity = qty,
                UnitPrice = product.SellingPrice, TaxPercent = product.TaxPercent,
                TaxAmount = lineTax, LineTotal = gross + lineTax
            });

            sub += gross;
            tax += lineTax;
            product.StockQty -= qty;
        }

        inv.SubTotal   = sub;
        inv.TaxAmount  = tax;
        inv.GrandTotal = decimal.Round(sub + tax, 2);

        var paidAmount = Math.Clamp(paid ?? inv.GrandTotal, 0, inv.GrandTotal);
        inv.PaidAmount    = paidAmount;
        inv.BalanceAmount = decimal.Round(inv.GrandTotal - paidAmount, 2);
        inv.Status = inv.BalanceAmount <= 0 ? InvoiceStatus.Paid
                   : paidAmount > 0         ? InvoiceStatus.PartiallyPaid
                                            : InvoiceStatus.Credit;

        db.Invoices.Add(inv);
        await db.SaveChangesAsync();

        AddLedger(db, biz.Id, cust.Id, "Invoice", inv.Id, $"Bill {inv.InvoiceNumber}", inv.GrandTotal, 0);

        if (paidAmount > 0)
        {
            var receiptSeq = await db.Payments.CountAsync(p => p.BusinessId == biz.Id) + 1;
            var pay = new Payment
            {
                BusinessId    = biz.Id,
                CustomerId    = cust.Id,
                InvoiceId     = inv.Id,
                ReceiptNumber = $"RCP-{biz.Id:D3}-{receiptSeq:D5}",
                Amount        = paidAmount,
                Mode          = mode == "Credit" ? "Cash" : mode,
                Note          = $"Against bill {inv.InvoiceNumber}",
                PaidOn        = inv.InvoiceDate
            };
            db.Payments.Add(pay);
            await db.SaveChangesAsync();

            AddLedger(db, biz.Id, cust.Id, "Payment", pay.Id, $"Payment {pay.ReceiptNumber}", 0, paidAmount);
        }

        cust.OutstandingBalance += inv.BalanceAmount;
        await db.SaveChangesAsync();
    }

    private static async Task<CreditGrant> AddCreditAsync(AppDbContext db, Business biz, Customer cust,
                                                          decimal amount, string reason)
    {
        var seq = await db.CreditGrants.CountAsync(g => g.BusinessId == biz.Id) + 1;
        var grant = new CreditGrant
        {
            BusinessId    = biz.Id,
            CustomerId    = cust.Id,
            CreditCode    = $"CR-{biz.Id:D3}-{seq:D5}",
            Amount        = amount,
            BalanceAmount = amount,
            Reason        = reason,
            ExpiryDate    = DateOnly.FromDateTime(DateTime.Today.AddMonths(3)),
            Status        = CreditStatus.Active
        };
        db.CreditGrants.Add(grant);
        cust.CreditBalance += amount;
        await db.SaveChangesAsync();
        return grant;
    }

    private static void AddLedger(AppDbContext db, int bizId, int custId, string refType, int refId,
                                  string description, decimal debit, decimal credit)
    {
        var last = db.LedgerEntries.Where(l => l.CustomerId == custId)
                                   .OrderByDescending(l => l.Id)
                                   .Select(l => (decimal?)l.RunningBalance)
                                   .FirstOrDefault() ?? 0m;

        db.LedgerEntries.Add(new LedgerEntry
        {
            BusinessId = bizId, CustomerId = custId, RefType = refType, RefId = refId,
            Description = description, Debit = debit, Credit = credit,
            RunningBalance = last + debit - credit
        });
    }
}
