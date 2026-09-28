using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>Stock. Workers can look products up and scan barcodes; only the owner edits them.</summary>
[Authorize(Roles = Roles.Staff)]
public class ProductsController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;

    public ProductsController(AppDbContext db, ICurrentUser me, IBookkeepingService books)
    {
        _db = db; _me = me; _books = books;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? search, [FromQuery] bool? lowStockOnly,
                                          [FromQuery] int? businessId,
                                          [FromQuery] int page = 1, [FromQuery] int pageSize = 50,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        var q = _db.Products.AsNoTracking().Where(p => p.IsActive);
        if (bizId is not null) q = q.Where(p => p.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(p => p.Name.Contains(search) || (p.Sku != null && p.Sku.Contains(search))
                                                     || (p.Barcode != null && p.Barcode == search));
        if (lowStockOnly == true) q = q.Where(p => p.StockQty <= p.MinStockQty);

        var total = await q.CountAsync(ct);
        var items = await q.OrderBy(p => p.Name)
                           .Skip((page - 1) * pageSize).Take(pageSize)
                           .ToListAsync(ct);

        return Ok(new PagedResult<ProductDto>
        {
            Items = items.Select(ToDto).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    /// <summary>
    /// Counter scanning: a USB / Bluetooth scanner or the phone camera reads the pack's
    /// barcode and the bill looks the product up here (barcode first, then SKU).
    /// </summary>
    [HttpGet("barcode/{code}")]
    public async Task<IActionResult> ByBarcode(string code, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var clean = code.Trim();
        var p = await _db.Products.AsNoTracking()
                         .Where(x => x.BusinessId == bizId && x.IsActive &&
                                     (x.Barcode == clean || x.Sku == clean))
                         .OrderBy(x => x.Barcode == clean ? 0 : 1)
                         .FirstOrDefaultAsync(ct);

        return p is null
            ? NotFoundMsg($"No product with barcode {clean}. Add it under Stock first.")
            : Ok(ToDto(p));
    }

    [HttpGet("low-stock")]
    public async Task<IActionResult> LowStock([FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null && !_me.IsSuperAdmin) return Forbidden();

        var q = _db.Products.AsNoTracking().Where(p => p.IsActive && p.StockQty <= p.MinStockQty);
        if (bizId is not null) q = q.Where(p => p.BusinessId == bizId);

        var items = await q.OrderBy(p => p.StockQty).Take(100).ToListAsync(ct);
        return Ok(items.Select(ToDto).ToList());
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPost]
    public async Task<IActionResult> Create(ProductRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        if (!string.IsNullOrWhiteSpace(req.Sku) &&
            await _db.Products.AnyAsync(p => p.BusinessId == bizId && p.Sku == req.Sku, ct))
            return Fail("This SKU is already used by another product.");

        var barcode = string.IsNullOrWhiteSpace(req.Barcode) ? null : req.Barcode.Trim();
        if (barcode is not null &&
            await _db.Products.AnyAsync(p => p.BusinessId == bizId && p.IsActive && p.Barcode == barcode, ct))
            return Fail("This barcode is already on another product.");

        var p = new Product
        {
            BusinessId    = bizId.Value,
            Name          = req.Name.Trim(),
            Sku           = string.IsNullOrWhiteSpace(req.Sku) ? null : req.Sku.Trim(),
            Barcode       = barcode,
            Unit          = req.Unit,
            SellingPrice  = req.SellingPrice,
            PurchasePrice = req.PurchasePrice,
            TaxPercent    = req.TaxPercent,
            StockQty      = req.StockQty,
            MinStockQty   = req.MinStockQty
        };
        _db.Products.Add(p);
        await _books.AuditAsync(bizId, _me.UserId, "CreateProduct", "Product", null, p.Name, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(p), "Product added.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, ProductRequest req, CancellationToken ct)
    {
        var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return NotFoundMsg("Product not found.");
        if (!CanTouch(p.BusinessId)) return Forbidden();

        var barcode = string.IsNullOrWhiteSpace(req.Barcode) ? null : req.Barcode.Trim();
        if (barcode is not null &&
            await _db.Products.AnyAsync(x => x.BusinessId == p.BusinessId && x.IsActive &&
                                             x.Barcode == barcode && x.Id != p.Id, ct))
            return Fail("This barcode is already on another product.");

        p.Name          = req.Name.Trim();
        p.Sku           = string.IsNullOrWhiteSpace(req.Sku) ? null : req.Sku.Trim();
        p.Barcode       = barcode;
        p.Unit          = req.Unit;
        p.SellingPrice  = req.SellingPrice;
        p.PurchasePrice = req.PurchasePrice;
        p.TaxPercent    = req.TaxPercent;
        p.MinStockQty   = req.MinStockQty;

        await _books.AuditAsync(p.BusinessId, _me.UserId, "UpdateProduct", "Product", p.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(p), "Product updated.");
    }

    /// <summary>Stock correction with a mandatory reason (FR-022).</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/adjust-stock")]
    public async Task<IActionResult> AdjustStock(int id, [FromQuery] decimal quantity,
                                                 [FromQuery] string reason, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(reason)) return Fail("A reason is required for a stock adjustment.");

        var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return NotFoundMsg("Product not found.");
        if (!CanTouch(p.BusinessId)) return Forbidden();

        var before = p.StockQty;
        p.StockQty += quantity;
        await _books.AuditAsync(p.BusinessId, _me.UserId, "AdjustStock", "Product", p.Id,
                                $"{before} -> {p.StockQty}: {reason}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(p), "Stock adjusted.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Deactivate(int id, CancellationToken ct)
    {
        var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (p is null) return NotFoundMsg("Product not found.");
        if (!CanTouch(p.BusinessId)) return Forbidden();

        p.IsActive = false;
        await _books.AuditAsync(p.BusinessId, _me.UserId, "DeactivateProduct", "Product", p.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Product deactivated.");
    }

    private bool CanTouch(int businessId) => _me.IsSuperAdmin || _me.BusinessId == businessId;
}
