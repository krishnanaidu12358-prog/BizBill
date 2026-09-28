using System.Text.RegularExpressions;
using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// The shop owner's UPI ID. Customers see it as a QR and a "Pay with UPI app"
/// button, so money goes straight into the shop's own bank account.
/// Route: /api/shopupi
/// </summary>
[Authorize(Roles = Roles.BusinessUser)]
public partial class ShopUpiController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;

    public ShopUpiController(AppDbContext db, ICurrentUser me, IBookkeepingService books)
    {
        _db = db; _me = me; _books = books;
    }

    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        if (_me.BusinessId is not { } bizId) return Forbidden();
        var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == bizId, ct);
        if (biz is null) return NotFoundMsg("Shop not found.");

        return Ok(new ShopUpiDto
        {
            BusinessId   = biz.Id,
            BusinessName = biz.Name,
            UpiId        = biz.UpiId,
            UpiName      = string.IsNullOrWhiteSpace(biz.UpiName) ? biz.Name : biz.UpiName
        });
    }

    [HttpPut]
    public async Task<IActionResult> Save(ShopUpiRequest req, CancellationToken ct)
    {
        if (_me.BusinessId is not { } bizId) return Forbidden();
        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == bizId, ct);
        if (biz is null) return NotFoundMsg("Shop not found.");

        var upi = (req.UpiId ?? "").Trim();
        if (upi.Length > 0 && !UpiPattern().IsMatch(upi))
            return Fail("That does not look like a UPI ID. It should look like name@bank, e.g. lakshmistores@okaxis.");

        var before = biz.UpiId;
        biz.UpiId   = upi.Length == 0 ? null : upi;
        biz.UpiName = string.IsNullOrWhiteSpace(req.UpiName) ? null : req.UpiName.Trim();

        await _books.AuditAsync(biz.Id, _me.UserId, "UpdateUpi", "Business", biz.Id,
                                $"{before ?? "-"} -> {biz.UpiId ?? "-"}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(new ShopUpiDto
        {
            BusinessId   = biz.Id,
            BusinessName = biz.Name,
            UpiId        = biz.UpiId,
            UpiName      = string.IsNullOrWhiteSpace(biz.UpiName) ? biz.Name : biz.UpiName
        }, biz.UpiId is null
            ? "UPI payments turned off."
            : "UPI ID saved. Customers can now pay you directly from the app.");
    }

    [GeneratedRegex(@"^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z][a-zA-Z0-9]{1,63}$")]
    private static partial Regex UpiPattern();
}
