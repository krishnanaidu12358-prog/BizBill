using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// The shop's profile and bill design: name, type (supermarket, mart, kirana ...),
/// address, GSTIN, logo, signature, terms. Everything here prints on the bills.
/// The owner edits their own shop; the Super Admin can edit any shop (?businessId=).
/// Route: /api/business-profile
/// </summary>
[Authorize]
[Route("api/business-profile")]
public class BusinessProfileController : ApiControllerBase
{
    private static readonly HashSet<string> ImageTypes = new(StringComparer.OrdinalIgnoreCase)
        { "image/png", "image/jpeg", "image/jpg" };

    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IFileStorageService _files;

    public BusinessProfileController(AppDbContext db, ICurrentUser me, IBookkeepingService books,
                                     IFileStorageService files)
    {
        _db = db; _me = me; _books = books; _files = files;
    }

    [Authorize(Roles = Roles.Staff)]
    [HttpGet]
    public async Task<IActionResult> Get([FromQuery] int? businessId, CancellationToken ct)
    {
        var biz = await FindAsync(businessId, tracked: false, ct);
        return biz is null ? Fail("A business must be selected.") : Ok(ToProfile(biz));
    }

    [AllowAnonymous]
    [HttpGet("types")]
    public IActionResult Types() => Ok(BusinessTypes.All.ToList());

    [Authorize(Roles = Roles.Owners)]
    [HttpPut]
    public async Task<IActionResult> Save(BusinessProfileRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var biz = await FindAsync(businessId, tracked: true, ct);
        if (biz is null) return Fail("A business must be selected.");
        if (!BusinessTypes.All.Contains(req.BusinessType))
            return Fail("Pick a business type from the list.");

        biz.Name              = req.Name.Trim();
        biz.BusinessType      = req.BusinessType;
        biz.Tagline           = Clean(req.Tagline);
        biz.OwnerName         = Clean(req.OwnerName);
        biz.Email             = Clean(req.Email);
        biz.AddressLine       = Clean(req.AddressLine);
        biz.City              = Clean(req.City);
        biz.State             = Clean(req.State);
        biz.Pincode           = Clean(req.Pincode);
        biz.GstNumber         = Clean(req.GstNumber)?.ToUpperInvariant();
        biz.InvoicePrefix     = req.InvoicePrefix.Trim().ToUpperInvariant();
        biz.SignatoryName     = Clean(req.SignatoryName);
        biz.InvoiceTerms      = Clean(req.InvoiceTerms);
        biz.ReceiptFooter     = Clean(req.ReceiptFooter);
        biz.ShowLogoOnReceipt = req.ShowLogoOnReceipt;
        biz.ShowSignature     = req.ShowSignature;

        await _books.AuditAsync(biz.Id, _me.UserId, "UpdateBusinessProfile", "Business", biz.Id,
                                _me.IsSuperAdmin ? "by Super Admin" : null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToProfile(biz), "Shop profile saved. New bills will print with these details.");
    }

    // ------------------------------------------------------------ images

    [Authorize(Roles = Roles.Owners)]
    [HttpPost("logo")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    public Task<IActionResult> UploadLogo(IFormFile file, [FromQuery] int? businessId, CancellationToken ct) =>
        UploadAsync(file, businessId, "logo", ct);

    [Authorize(Roles = Roles.Owners)]
    [HttpPost("signature")]
    [RequestSizeLimit(6 * 1024 * 1024)]
    public Task<IActionResult> UploadSignature(IFormFile file, [FromQuery] int? businessId, CancellationToken ct) =>
        UploadAsync(file, businessId, "signature", ct);

    [Authorize(Roles = Roles.Owners)]
    [HttpDelete("logo")]
    public Task<IActionResult> RemoveLogo([FromQuery] int? businessId, CancellationToken ct) =>
        RemoveAsync(businessId, "logo", ct);

    [Authorize(Roles = Roles.Owners)]
    [HttpDelete("signature")]
    public Task<IActionResult> RemoveSignature([FromQuery] int? businessId, CancellationToken ct) =>
        RemoveAsync(businessId, "signature", ct);

    /// <summary>
    /// The logo / signature image. Readable by the admin, the shop's owner and
    /// workers, and customers who buy from that shop (their bills print it).
    /// </summary>
    [HttpGet("{businessId:int}/{kind:regex(^(logo|signature)$)}")]
    public async Task<IActionResult> Image(int businessId, string kind, CancellationToken ct)
    {
        var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == businessId, ct);
        if (biz is null) return NotFoundMsg("Shop not found.");

        var allowed = _me.IsSuperAdmin || _me.BusinessId == businessId ||
                      (_me.Role == Roles.Customer &&
                       await _db.Customers.AnyAsync(c => c.BusinessId == businessId && c.UserId == _me.UserId, ct));
        if (!allowed) return Forbidden();

        var (path, type) = kind == "logo"
            ? (biz.LogoPath, biz.LogoContentType)
            : (biz.SignaturePath, biz.SignatureContentType);
        var full = _files.ResolvePath(path);
        if (full is null) return NotFoundMsg($"No {kind} uploaded.");

        Response.Headers.CacheControl = "private, max-age=86400";
        return PhysicalFile(full, type ?? "image/png");
    }

    // ------------------------------------------------------------ helpers

    private async Task<IActionResult> UploadAsync(IFormFile? file, int? businessId, string kind, CancellationToken ct)
    {
        var biz = await FindAsync(businessId, tracked: true, ct);
        if (biz is null) return Fail("A business must be selected.");
        if (file is null || file.Length == 0) return Fail($"Choose a {kind} image.");
        if (!ImageTypes.Contains(file.ContentType ?? ""))
            return Fail($"Upload the {kind} as a PNG or JPG image.");

        StoredFile stored;
        try
        {
            stored = await _files.SaveImageAsync(file, $"branding{biz.Id}", ct, kind);
        }
        catch (InvalidOperationException ex)
        {
            return Fail(ex.Message);
        }

        string? old;
        if (kind == "logo")
        {
            old = biz.LogoPath;
            biz.LogoPath = stored.RelativePath;
            biz.LogoContentType = stored.ContentType;
        }
        else
        {
            old = biz.SignaturePath;
            biz.SignaturePath = stored.RelativePath;
            biz.SignatureContentType = stored.ContentType;
        }
        biz.BrandingUpdatedAt = DateTime.UtcNow;

        await _books.AuditAsync(biz.Id, _me.UserId, kind == "logo" ? "UploadLogo" : "UploadSignature",
                                "Business", biz.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        _files.Delete(old);

        return Ok(ToProfile(biz), kind == "logo" ? "Logo saved." : "Signature saved.");
    }

    private async Task<IActionResult> RemoveAsync(int? businessId, string kind, CancellationToken ct)
    {
        var biz = await FindAsync(businessId, tracked: true, ct);
        if (biz is null) return Fail("A business must be selected.");

        string? old;
        if (kind == "logo")
        {
            old = biz.LogoPath;
            biz.LogoPath = null;
            biz.LogoContentType = null;
        }
        else
        {
            old = biz.SignaturePath;
            biz.SignaturePath = null;
            biz.SignatureContentType = null;
        }
        biz.BrandingUpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        _files.Delete(old);
        return Ok(ToProfile(biz), kind == "logo" ? "Logo removed." : "Signature removed.");
    }

    private async Task<Business?> FindAsync(int? requested, bool tracked, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, requested);
        if (bizId is null) return null;
        var q = tracked ? _db.Businesses : _db.Businesses.AsNoTracking();
        return await q.FirstOrDefaultAsync(b => b.Id == bizId, ct);
    }

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    private static BusinessProfileDto ToProfile(Business b) => new()
    {
        Id = b.Id, Name = b.Name, BusinessType = b.BusinessType, Tagline = b.Tagline, OwnerName = b.OwnerName,
        Mobile = b.Mobile, Email = b.Email, AddressLine = b.AddressLine, City = b.City, State = b.State,
        Pincode = b.Pincode, GstNumber = b.GstNumber, InvoicePrefix = b.InvoicePrefix,
        UpiId = b.UpiId, UpiName = b.UpiName, SignatoryName = b.SignatoryName,
        InvoiceTerms = b.InvoiceTerms, ReceiptFooter = b.ReceiptFooter,
        ShowLogoOnReceipt = b.ShowLogoOnReceipt, ShowSignature = b.ShowSignature,
        LogoUrl = BrandingUrl(b, "logo"), SignatureUrl = BrandingUrl(b, "signature"),
        IsActive = b.IsActive, BusinessTypes = BusinessTypes.All.ToList()
    };
}
