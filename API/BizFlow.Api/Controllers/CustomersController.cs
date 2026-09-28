using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

[Authorize(Roles = Roles.Staff)]
public class CustomersController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _wa;

    public CustomersController(AppDbContext db, ICurrentUser me, IBookkeepingService books, IWhatsAppService wa)
    {
        _db = db; _me = me; _books = books; _wa = wa;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? search, [FromQuery] bool? trustedOnly,
                                          [FromQuery] bool? withDues, [FromQuery] int? businessId,
                                          [FromQuery] int page = 1, [FromQuery] int pageSize = 25,
                                          CancellationToken ct = default)
    {
        var q = _db.Customers.AsNoTracking().Where(c => c.IsActive);

        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is not null) q = q.Where(c => c.BusinessId == bizId);
        else if (!_me.IsSuperAdmin) return Forbidden();

        if (!string.IsNullOrWhiteSpace(search))
            q = q.Where(c => c.Name.Contains(search) || c.Mobile.Contains(search));
        if (trustedOnly == true) q = q.Where(c => c.IsTrusted);
        if (withDues == true)    q = q.Where(c => c.OutstandingBalance > 0);

        var total = await q.CountAsync(ct);
        var items = await q.OrderBy(c => c.Name)
                           .Skip((page - 1) * pageSize).Take(pageSize)
                           .ToListAsync(ct);

        return Ok(new PagedResult<CustomerDto>
        {
            Items = items.Select(ToDto).ToList(),
            Page = page, PageSize = pageSize, TotalCount = total
        });
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id, CancellationToken ct)
    {
        var c = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();
        return Ok(ToDto(c));
    }

    /// <summary>
    /// The shop's "Walk-in customer" for quick counter sales (no name or number),
    /// created on first use. Udhaar is never allowed on it and it is never messaged.
    /// </summary>
    [HttpPost("walk-in")]
    public async Task<IActionResult> WalkIn([FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var cust = await _db.Customers.FirstOrDefaultAsync(
            c => c.BusinessId == bizId && c.Mobile == Customer.WalkInMobile, ct);
        if (cust is null)
        {
            cust = new Customer
            {
                BusinessId  = bizId.Value,
                Name        = "Walk-in Customer",
                Mobile      = Customer.WalkInMobile,
                IsTrusted   = false,
                CreditLimit = 0
            };
            _db.Customers.Add(cust);
            await _db.SaveChangesAsync(ct);
        }
        else if (!cust.IsActive)
        {
            cust.IsActive = true;
            await _db.SaveChangesAsync(ct);
        }

        return Ok(ToDto(cust));
    }

    /// <summary>
    /// Adds a customer. The mobile number is the account key: if that number has no
    /// app login yet and InitialPassword is supplied, a Customer account is created too.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> Create(CustomerRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var mobile = AuthController.Normalize(req.Mobile);
        if (await _db.Customers.AnyAsync(c => c.BusinessId == bizId && c.Mobile == mobile, ct))
            return Fail("A customer with this mobile number already exists in your business.");

        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == bizId, ct);
        if (biz is null) return NotFoundMsg("Business not found.");

        // One login per mobile number, shared across every shop that number buys from.
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Mobile == mobile, ct);
        if (user is null && !string.IsNullOrWhiteSpace(req.InitialPassword))
        {
            user = new AppUser
            {
                Mobile       = mobile,
                FullName     = req.Name.Trim(),
                Email        = req.Email,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.InitialPassword),
                Role         = Roles.Customer
            };
            _db.Users.Add(user);
            await _db.SaveChangesAsync(ct);
        }

        var cust = new Customer
        {
            BusinessId  = bizId.Value,
            UserId      = user?.Role == Roles.Customer ? user.Id : null,
            Name        = req.Name.Trim(),
            Mobile      = mobile,
            Email       = req.Email,
            Address     = req.Address,
            IsTrusted   = req.IsTrusted,
            CreditLimit = req.CreditLimit
        };
        _db.Customers.Add(cust);
        await _books.AuditAsync(bizId, _me.UserId, "CreateCustomer", "Customer", null, cust.Mobile, ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        await _wa.SendAsync("Welcome", cust.Mobile, MessageTemplates.Welcome(biz, cust), biz.Id, cust.Id, ct);

        return Ok(ToDto(cust), "Customer added.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, CustomerRequest req, CancellationToken ct)
    {
        var c = await _db.Customers.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();

        var mobile = AuthController.Normalize(req.Mobile);
        if (mobile != c.Mobile &&
            await _db.Customers.AnyAsync(x => x.BusinessId == c.BusinessId && x.Mobile == mobile && x.Id != id, ct))
            return Fail("Another customer already uses this mobile number.");

        c.Name        = req.Name.Trim();
        c.Mobile      = mobile;
        c.Email       = req.Email;
        c.Address     = req.Address;
        c.IsTrusted   = req.IsTrusted;
        c.CreditLimit = req.CreditLimit;

        await _books.AuditAsync(c.BusinessId, _me.UserId, "UpdateCustomer", "Customer", c.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(c), "Customer updated.");
    }

    /// <summary>Soft delete (FR-044) - history stays intact.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Deactivate(int id, CancellationToken ct)
    {
        var c = await _db.Customers.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();
        if (c.OutstandingBalance > 0)
            return Fail($"Customer still owes Rs.{c.OutstandingBalance:N2}. Settle the account first.");

        c.IsActive = false;
        await _books.AuditAsync(c.BusinessId, _me.UserId, "DeactivateCustomer", "Customer", c.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Customer deactivated.");
    }

    /// <summary>Marks a customer trusted and sets the credit ceiling used when issuing credit.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/trust")]
    public async Task<IActionResult> SetTrust(int id, [FromQuery] bool trusted, [FromQuery] decimal creditLimit,
                                              CancellationToken ct)
    {
        var c = await _db.Customers.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();

        c.IsTrusted   = trusted;
        c.CreditLimit = trusted ? creditLimit : 0;
        await _books.AuditAsync(c.BusinessId, _me.UserId, "SetCustomerTrust", "Customer", c.Id,
                                $"trusted={trusted}, limit={creditLimit}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(c), trusted ? "Customer marked as trusted." : "Trusted status removed.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpGet("{id:int}/ledger")]
    public async Task<IActionResult> Ledger(int id, CancellationToken ct)
    {
        var c = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();

        var rows = await _db.LedgerEntries.AsNoTracking()
                            .Where(l => l.CustomerId == id)
                            .OrderByDescending(l => l.Id)
                            .Take(200)
                            .Select(l => new LedgerEntryDto
                            {
                                Id = l.Id, EntryDate = l.EntryDate, RefType = l.RefType, RefId = l.RefId,
                                Description = l.Description, Debit = l.Debit, Credit = l.Credit,
                                RunningBalance = l.RunningBalance
                            })
                            .ToListAsync(ct);
        return Ok(rows);
    }

    /// <summary>Running account: every unpaid bill with its date and the combined total due.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpGet("{id:int}/statement")]
    public async Task<IActionResult> Statement(int id, CancellationToken ct)
    {
        var c = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();

        var biz = await _db.Businesses.AsNoTracking().FirstOrDefaultAsync(b => b.Id == c.BusinessId, ct);
        return Ok(await StatementBuilder.BuildAsync(_db, c, biz, ct));
    }

    /// <summary>Sends the whole running account on WhatsApp - all unpaid bills, dated.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/send-statement")]
    public async Task<IActionResult> SendStatement(int id, CancellationToken ct)
    {
        var c = await _db.Customers.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (c is null) return NotFoundMsg("Customer not found.");
        if (!CanTouch(c.BusinessId)) return Forbidden();

        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == c.BusinessId, ct);
        if (biz is null) return NotFoundMsg("Business not found.");

        var unpaid = await StatementBuilder.UnpaidWithItemsAsync(_db, c.Id, ct);
        if (unpaid.Count == 0) return Fail("This customer has no unpaid bills.");

        var msg = await _wa.SendAsync("Statement", c.Mobile,
                                      MessageTemplates.Statement(biz, c, unpaid),
                                      biz.Id, c.Id, ct);

        return Ok(new { msg.Status, msg.DeepLink, msg.Body }, "Statement sent on WhatsApp.");
    }

    private bool CanTouch(int businessId) => _me.IsSuperAdmin || _me.BusinessId == businessId;
}
