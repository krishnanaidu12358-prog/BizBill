using BizFlow.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Business> Businesses => Set<Business>();
    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<Invoice> Invoices => Set<Invoice>();
    public DbSet<InvoiceItem> InvoiceItems => Set<InvoiceItem>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<CreditGrant> CreditGrants => Set<CreditGrant>();
    public DbSet<CreditClaim> CreditClaims => Set<CreditClaim>();
    public DbSet<LedgerEntry> LedgerEntries => Set<LedgerEntry>();
    public DbSet<WhatsAppMessage> WhatsAppMessages => Set<WhatsAppMessage>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<PaymentProof> PaymentProofs => Set<PaymentProof>();
    public DbSet<Expense> Expenses => Set<Expense>();

    /// <summary>
    /// Every timestamp is written as UTC, but SQL Server hands DATETIME2 back with no
    /// kind, so it serialised without a trailing "Z" and phones showed UTC as local
    /// time (5h30m early in India). Stamping the kind on read fixes every endpoint.
    /// </summary>
    protected override void ConfigureConventions(ModelConfigurationBuilder cb)
    {
        cb.Properties<DateTime>().HaveConversion<UtcDateTimeConverter>();
        cb.Properties<DateTime?>().HaveConversion<NullableUtcDateTimeConverter>();
    }

    private sealed class UtcDateTimeConverter()
        : Microsoft.EntityFrameworkCore.Storage.ValueConversion.ValueConverter<DateTime, DateTime>(
            v => v.Kind == DateTimeKind.Local ? v.ToUniversalTime() : v,
            v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

    private sealed class NullableUtcDateTimeConverter()
        : Microsoft.EntityFrameworkCore.Storage.ValueConversion.ValueConverter<DateTime?, DateTime?>(
            v => v.HasValue && v.Value.Kind == DateTimeKind.Local ? v.Value.ToUniversalTime() : v,
            v => v.HasValue ? DateTime.SpecifyKind(v.Value, DateTimeKind.Utc) : v);

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Expense>(e =>
        {
            e.ToTable("Expenses");
            e.Property(x => x.Category).HasMaxLength(40);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.PaymentMode).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.PaidTo).HasMaxLength(120);
            e.Property(x => x.Note).HasMaxLength(250);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
        });

        b.Entity<Business>(e =>
        {
            e.ToTable("Businesses");
            e.HasIndex(x => x.Mobile).IsUnique();
            e.Property(x => x.Name).HasMaxLength(150);
            e.Property(x => x.Mobile).HasMaxLength(15).IsUnicode(false);
            e.Property(x => x.InvoicePrefix).HasMaxLength(10).IsUnicode(false);
            e.Property(x => x.Currency).HasMaxLength(5).IsUnicode(false);
            e.Property(x => x.Pincode).HasMaxLength(10).IsUnicode(false);
            e.Property(x => x.GstNumber).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.UpiId).HasMaxLength(100).IsUnicode(false);
            e.Property(x => x.UpiName).HasMaxLength(100);
        });

        b.Entity<AppUser>(e =>
        {
            e.ToTable("AppUsers");
            e.HasIndex(x => x.Mobile).IsUnique();
            e.Property(x => x.Mobile).HasMaxLength(15).IsUnicode(false);
            e.Property(x => x.FullName).HasMaxLength(120);
            e.Property(x => x.PasswordHash).HasMaxLength(200);
            e.Property(x => x.Role).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.ThemeMode).HasMaxLength(10).IsUnicode(false);
            e.Property(x => x.ThemeName).HasMaxLength(30).IsUnicode(false);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
        });

        b.Entity<RefreshToken>(e =>
        {
            e.ToTable("RefreshTokens");
            e.HasIndex(x => x.Token).IsUnique();
            e.Property(x => x.Token).HasMaxLength(100).IsUnicode(false);
        });

        b.Entity<Customer>(e =>
        {
            e.ToTable("Customers");
            e.Ignore(x => x.IsWalkIn);
            e.HasIndex(x => new { x.BusinessId, x.Mobile }).IsUnique();
            e.Property(x => x.Name).HasMaxLength(120);
            e.Property(x => x.Mobile).HasMaxLength(15).IsUnicode(false);
            e.Property(x => x.CreditLimit).HasPrecision(18, 2);
            e.Property(x => x.OutstandingBalance).HasPrecision(18, 2);
            e.Property(x => x.CreditBalance).HasPrecision(18, 2);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId);
        });

        b.Entity<Product>(e =>
        {
            e.ToTable("Products");
            e.Property(x => x.Name).HasMaxLength(150);
            e.Property(x => x.Sku).HasMaxLength(50).IsUnicode(false);
            e.Property(x => x.Barcode).HasMaxLength(64).IsUnicode(false);
            e.Property(x => x.Unit).HasMaxLength(20);
            e.Property(x => x.SellingPrice).HasPrecision(18, 2);
            e.Property(x => x.PurchasePrice).HasPrecision(18, 2);
            e.Property(x => x.TaxPercent).HasPrecision(5, 2);
            e.Property(x => x.StockQty).HasPrecision(18, 3);
            e.Property(x => x.MinStockQty).HasPrecision(18, 3);
        });

        b.Entity<Invoice>(e =>
        {
            e.ToTable("Invoices");
            e.HasIndex(x => new { x.BusinessId, x.InvoiceNumber }).IsUnique();
            e.Property(x => x.InvoiceNumber).HasMaxLength(30).IsUnicode(false);
            e.Property(x => x.PaymentMode).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Status).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Notes).HasMaxLength(500);
            foreach (var p in new[] { nameof(Invoice.SubTotal), nameof(Invoice.DiscountAmount),
                                      nameof(Invoice.TaxAmount), nameof(Invoice.GrandTotal),
                                      nameof(Invoice.PaidAmount), nameof(Invoice.BalanceAmount) })
                e.Property(p).HasPrecision(18, 2);
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
            e.HasMany(x => x.Items).WithOne().HasForeignKey(x => x.InvoiceId);
        });

        b.Entity<InvoiceItem>(e =>
        {
            e.ToTable("InvoiceItems");
            e.Property(x => x.ProductName).HasMaxLength(150);
            e.Property(x => x.Quantity).HasPrecision(18, 3);
            e.Property(x => x.UnitPrice).HasPrecision(18, 2);
            e.Property(x => x.DiscountAmount).HasPrecision(18, 2);
            e.Property(x => x.TaxPercent).HasPrecision(5, 2);
            e.Property(x => x.TaxAmount).HasPrecision(18, 2);
            e.Property(x => x.LineTotal).HasPrecision(18, 2);
        });

        b.Entity<Payment>(e =>
        {
            e.ToTable("Payments");
            e.HasIndex(x => new { x.BusinessId, x.ReceiptNumber }).IsUnique();
            e.Property(x => x.ReceiptNumber).HasMaxLength(30).IsUnicode(false);
            e.Property(x => x.Mode).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.ReferenceNo).HasMaxLength(80);
            e.Property(x => x.Note).HasMaxLength(250);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId);
        });

        b.Entity<CreditGrant>(e =>
        {
            e.ToTable("CreditGrants");
            e.HasIndex(x => x.CreditCode).IsUnique();
            e.Property(x => x.CreditCode).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Reason).HasMaxLength(250);
            e.Property(x => x.Status).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.ClaimedAmount).HasPrecision(18, 2);
            e.Property(x => x.BalanceAmount).HasPrecision(18, 2);
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
        });

        b.Entity<CreditClaim>(e =>
        {
            e.ToTable("CreditClaims");
            e.Property(x => x.Status).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Remarks).HasMaxLength(250);
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.HasOne(x => x.CreditGrant).WithMany().HasForeignKey(x => x.CreditGrantId);
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
        });

        b.Entity<LedgerEntry>(e =>
        {
            e.ToTable("LedgerEntries");
            e.Property(x => x.RefType).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Description).HasMaxLength(250);
            e.Property(x => x.Debit).HasPrecision(18, 2);
            e.Property(x => x.Credit).HasPrecision(18, 2);
            e.Property(x => x.RunningBalance).HasPrecision(18, 2);
        });

        b.Entity<WhatsAppMessage>(e =>
        {
            e.ToTable("WhatsAppMessages");
            e.Property(x => x.ToMobile).HasMaxLength(15).IsUnicode(false);
            e.Property(x => x.Template).HasMaxLength(40).IsUnicode(false);
            e.Property(x => x.DeepLink).HasMaxLength(1000);
            e.Property(x => x.Status).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Provider).HasMaxLength(30).IsUnicode(false);
            e.Property(x => x.ProviderMessageId).HasMaxLength(120);
            e.Property(x => x.ErrorMessage).HasMaxLength(500);
        });

        b.Entity<AuditLog>(e =>
        {
            e.ToTable("AuditLogs");
            e.Property(x => x.Action).HasMaxLength(60).IsUnicode(false);
            e.Property(x => x.EntityName).HasMaxLength(60).IsUnicode(false);
            e.Property(x => x.IpAddress).HasMaxLength(45).IsUnicode(false);
        });

        b.Entity<PaymentProof>(e =>
        {
            e.ToTable("PaymentProofs");
            e.Property(x => x.Amount).HasPrecision(18, 2);
            e.Property(x => x.Method).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.ReferenceNo).HasMaxLength(80);
            e.Property(x => x.Note).HasMaxLength(250);
            e.Property(x => x.FileName).HasMaxLength(200);
            e.Property(x => x.ContentType).HasMaxLength(100).IsUnicode(false);
            e.Property(x => x.StoredPath).HasMaxLength(400);
            e.Property(x => x.Status).HasMaxLength(20).IsUnicode(false);
            e.Property(x => x.Remarks).HasMaxLength(250);
            e.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId);
            e.HasOne(x => x.Business).WithMany().HasForeignKey(x => x.BusinessId);
            e.HasOne(x => x.Invoice).WithMany().HasForeignKey(x => x.InvoiceId);
        });
    }
}
