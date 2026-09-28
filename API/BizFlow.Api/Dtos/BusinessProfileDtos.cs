using System.ComponentModel.DataAnnotations;

namespace BizFlow.Api.Dtos;

/// <summary>Everything a shop prints on its bills, plus its settings.</summary>
public class BusinessProfileDto
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string BusinessType { get; set; } = "Retail";
    public string? Tagline { get; set; }
    public string? OwnerName { get; set; }
    /// <summary>Owner's login mobile; printed as the shop phone.</summary>
    public string Mobile { get; set; } = "";
    public string? Email { get; set; }
    public string? AddressLine { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? Pincode { get; set; }
    public string? GstNumber { get; set; }
    public string InvoicePrefix { get; set; } = "INV";
    public string? UpiId { get; set; }
    public string? UpiName { get; set; }
    public string? SignatoryName { get; set; }
    public string? InvoiceTerms { get; set; }
    public string? ReceiptFooter { get; set; }
    public bool ShowLogoOnReceipt { get; set; }
    public bool ShowSignature { get; set; }
    /// <summary>Relative URL of the logo image, with a version so apps refetch after a change.</summary>
    public string? LogoUrl { get; set; }
    public string? SignatureUrl { get; set; }
    public bool IsActive { get; set; }
    public List<string> BusinessTypes { get; set; } = new();
}

public class BusinessProfileRequest
{
    [Required, StringLength(150, MinimumLength = 2)] public string Name { get; set; } = "";
    [Required] public string BusinessType { get; set; } = "Retail";
    [StringLength(150)] public string? Tagline { get; set; }
    [StringLength(120)] public string? OwnerName { get; set; }
    [EmailAddress] public string? Email { get; set; }
    [StringLength(250)] public string? AddressLine { get; set; }
    [StringLength(80)] public string? City { get; set; }
    [StringLength(80)] public string? State { get; set; }
    [RegularExpression(@"^\d{6}$", ErrorMessage = "Pincode must be 6 digits.")] public string? Pincode { get; set; }
    [RegularExpression(@"^[0-9]{2}[A-Z0-9]{13}$", ErrorMessage = "GSTIN must be 15 characters, e.g. 36ABCDE1234F1Z5.")]
    public string? GstNumber { get; set; }
    [Required, RegularExpression(@"^[A-Za-z0-9]{1,10}$", ErrorMessage = "Bill prefix: 1-10 letters or digits.")]
    public string InvoicePrefix { get; set; } = "INV";
    [StringLength(120)] public string? SignatoryName { get; set; }
    [StringLength(1000)] public string? InvoiceTerms { get; set; }
    [StringLength(200)] public string? ReceiptFooter { get; set; }
    public bool ShowLogoOnReceipt { get; set; } = true;
    public bool ShowSignature { get; set; } = true;
}
