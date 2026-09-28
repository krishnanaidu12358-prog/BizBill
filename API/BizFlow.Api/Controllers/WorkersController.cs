using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>
/// HRMS for the shop: workers, counter logins, attendance, salary advances,
/// monthly payroll and who-sold-what. The owner manages everything here; a
/// worker only reaches the /me endpoints (their own day and check-in).
/// Route: /api/workers
/// </summary>
[Authorize]
public class WorkersController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;

    public WorkersController(AppDbContext db, ICurrentUser me, IBookkeepingService books)
    {
        _db = db; _me = me; _books = books;
    }

    private static DateOnly Today => DateOnly.FromDateTime(IndiaTime.Today);

    // =================================================================== workers

    [Authorize(Roles = Roles.Owners)]
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] bool includeInactive = false, [FromQuery] int? businessId = null,
                                          CancellationToken ct = default)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var q = _db.Workers.AsNoTracking().Include(w => w.User).Where(w => w.BusinessId == bizId);
        if (!includeInactive) q = q.Where(w => w.IsActive);
        var workers = await q.OrderByDescending(w => w.IsActive).ThenBy(w => w.Name).ToListAsync(ct);

        var ids = workers.Select(w => w.Id).ToList();
        var today = Today;
        var todayRows = await _db.WorkerAttendance.AsNoTracking()
                                 .Where(a => ids.Contains(a.WorkerId) && a.WorkDate == today)
                                 .ToDictionaryAsync(a => a.WorkerId, ct);
        var open = await OutstandingAdvancesAsync(ids, ct);

        return Ok(workers.Select(w => ToDto(w, todayRows.GetValueOrDefault(w.Id), open.GetValueOrDefault(w.Id)))
                         .ToList());
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id, CancellationToken ct)
    {
        var w = await _db.Workers.AsNoTracking().Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();

        var today = Today;
        var att = await _db.WorkerAttendance.AsNoTracking()
                           .FirstOrDefaultAsync(a => a.WorkerId == id && a.WorkDate == today, ct);
        var open = await OutstandingAdvancesAsync(new List<int> { id }, ct);
        return Ok(ToDto(w, att, open.GetValueOrDefault(id)));
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPost]
    public async Task<IActionResult> Create(WorkerRequest req, [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");
        if (ValidateWorker(req) is { } problem) return Fail(problem);

        var mobile = AuthController.Normalize(req.Mobile);
        if (await _db.Workers.AnyAsync(w => w.BusinessId == bizId && w.Mobile == mobile, ct))
            return Fail("A worker with this mobile number is already in your shop.");

        var wantsLogin = !string.IsNullOrWhiteSpace(req.LoginPassword);
        if (wantsLogin)
        {
            if (req.LoginPassword!.Length < 6) return Fail("The login password needs at least 6 characters.");
            if (await _db.Users.AnyAsync(u => u.Mobile == mobile, ct))
                return Fail("This mobile number already has a BizBill login (as an owner, customer or at another shop). "
                          + "Add the worker without a login, or use a different number.");
        }

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        AppUser? user = null;
        if (wantsLogin)
        {
            user = new AppUser
            {
                BusinessId   = bizId,
                Mobile       = mobile,
                FullName     = req.Name.Trim(),
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.LoginPassword),
                Role         = Roles.Worker
            };
            _db.Users.Add(user);
            await _db.SaveChangesAsync(ct);
        }

        var w = new Worker
        {
            BusinessId    = bizId.Value,
            UserId        = user?.Id,
            Name          = req.Name.Trim(),
            Mobile        = mobile,
            Designation   = Clean(req.Designation),
            SalaryType    = req.SalaryType,
            SalaryAmount  = req.SalaryAmount,
            JoinDate      = req.JoinDate ?? Today,
            Address       = Clean(req.Address),
            CanGiveUdhaar = req.CanGiveUdhaar
        };
        _db.Workers.Add(w);
        await _db.SaveChangesAsync(ct);
        await _books.AuditAsync(bizId, _me.UserId, "CreateWorker", "Worker", w.Id,
                                $"{w.Name} login={(user is null ? "no" : "yes")}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        w.User = user;
        return Ok(ToDto(w, null, 0), user is null
            ? "Worker added."
            : $"Worker added. They can log in with {mobile} and the password you set.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, WorkerRequest req, CancellationToken ct)
    {
        var w = await _db.Workers.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();
        if (ValidateWorker(req) is { } problem) return Fail(problem);

        var mobile = AuthController.Normalize(req.Mobile);
        if (mobile != w.Mobile)
        {
            if (w.UserId is not null)
                return Fail("This worker logs in with their mobile number, so it cannot be changed here. "
                          + "Switch this worker off and add them again with the new number.");
            if (await _db.Workers.AnyAsync(x => x.BusinessId == w.BusinessId && x.Mobile == mobile && x.Id != id, ct))
                return Fail("Another worker already has this mobile number.");
        }

        w.Name          = req.Name.Trim();
        w.Mobile        = mobile;
        w.Designation   = Clean(req.Designation);
        w.SalaryType    = req.SalaryType;
        w.SalaryAmount  = req.SalaryAmount;
        w.JoinDate      = req.JoinDate ?? w.JoinDate;
        w.Address       = Clean(req.Address);
        w.CanGiveUdhaar = req.CanGiveUdhaar;
        if (w.User is not null) w.User.FullName = w.Name;

        await _books.AuditAsync(w.BusinessId, _me.UserId, "UpdateWorker", "Worker", w.Id, w.Name, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(ToDto(w, null, 0), "Worker updated.");
    }

    /// <summary>Switches a worker off (and their login) or back on. Records are kept.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/toggle-active")]
    public async Task<IActionResult> ToggleActive(int id, CancellationToken ct)
    {
        var w = await _db.Workers.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();

        w.IsActive = !w.IsActive;
        if (w.User is not null)
        {
            w.User.IsActive = w.IsActive;
            if (!w.IsActive)
            {
                var tokens = await _db.RefreshTokens.Where(t => t.UserId == w.User.Id && t.RevokedAt == null)
                                      .ToListAsync(ct);
                foreach (var t in tokens) t.RevokedAt = DateTime.UtcNow;
            }
        }

        await _books.AuditAsync(w.BusinessId, _me.UserId, w.IsActive ? "ActivateWorker" : "DeactivateWorker",
                                "Worker", w.Id, w.Name, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(w.IsActive, w.IsActive ? $"{w.Name} is active again." : $"{w.Name} is switched off and logged out.");
    }

    /// <summary>Creates the worker's counter login, or sets a new password on it.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/login")]
    public async Task<IActionResult> SetLogin(int id, WorkerLoginRequest req, CancellationToken ct)
    {
        var w = await _db.Workers.Include(x => x.User).FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();
        if (!w.IsActive) return Fail("Switch the worker on first.");

        if (w.User is not null)
        {
            w.User.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password);
            w.User.IsActive = true;
            await _books.AuditAsync(w.BusinessId, _me.UserId, "ResetWorkerPassword", "Worker", w.Id, null, ClientIp, ct);
            await _db.SaveChangesAsync(ct);
            return Ok(true, $"New password set for {w.Name}.");
        }

        if (await _db.Users.AnyAsync(u => u.Mobile == w.Mobile, ct))
            return Fail("This mobile number already has a BizBill login (as an owner, customer or at another shop).");

        var user = new AppUser
        {
            BusinessId   = w.BusinessId,
            Mobile       = w.Mobile,
            FullName     = w.Name,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password),
            Role         = Roles.Worker
        };
        _db.Users.Add(user);
        await _db.SaveChangesAsync(ct);
        w.UserId = user.Id;
        await _books.AuditAsync(w.BusinessId, _me.UserId, "CreateWorkerLogin", "Worker", w.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, $"{w.Name} can now log in with {w.Mobile}.");
    }

    // ================================================================ attendance

    /// <summary>Every active worker with their status for one day (default today).</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpGet("attendance")]
    public async Task<IActionResult> AttendanceForDay([FromQuery] DateOnly? date, [FromQuery] int? businessId,
                                                      CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");
        var day = date ?? Today;

        var workers = await _db.Workers.AsNoTracking()
                               .Where(w => w.BusinessId == bizId && w.IsActive && w.JoinDate <= day)
                               .OrderBy(w => w.Name).ToListAsync(ct);
        var ids = workers.Select(w => w.Id).ToList();
        var marks = await _db.WorkerAttendance.AsNoTracking()
                             .Where(a => ids.Contains(a.WorkerId) && a.WorkDate == day)
                             .ToDictionaryAsync(a => a.WorkerId, ct);

        return Ok(workers.Select(w => Row(w, day, marks.GetValueOrDefault(w.Id))).ToList());
    }

    /// <summary>Marks attendance for many workers at once.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPut("attendance")]
    public async Task<IActionResult> MarkAttendance(AttendanceBulkRequest req, [FromQuery] int? businessId,
                                                    CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");
        if (req.Date > Today) return Fail("Attendance cannot be marked for a future date.");

        var ids = req.Rows.Select(r => r.WorkerId).Distinct().ToList();
        var workers = await _db.Workers.Where(w => ids.Contains(w.Id) && w.BusinessId == bizId)
                               .ToDictionaryAsync(w => w.Id, ct);
        var existing = await _db.WorkerAttendance
                                .Where(a => ids.Contains(a.WorkerId) && a.WorkDate == req.Date)
                                .ToDictionaryAsync(a => a.WorkerId, ct);

        var saved = 0;
        foreach (var r in req.Rows)
        {
            if (!workers.ContainsKey(r.WorkerId)) return Fail($"Worker #{r.WorkerId} is not in your shop.");
            var status = string.IsNullOrWhiteSpace(r.Status) ? null : r.Status.Trim();
            if (status is not null && !AttendanceStatus.All.Contains(status))
                return Fail($"Unknown attendance status '{status}'.");

            existing.TryGetValue(r.WorkerId, out var row);
            if (status is null)
            {
                if (row is not null) _db.WorkerAttendance.Remove(row);
                continue;
            }
            if (row is null)
            {
                row = new WorkerAttendance { BusinessId = bizId.Value, WorkerId = r.WorkerId, WorkDate = req.Date };
                _db.WorkerAttendance.Add(row);
            }
            row.Status = status;
            row.Note = Clean(r.Note);
            row.MarkedByUserId = _me.UserId;
            row.UpdatedAt = DateTime.UtcNow;
            saved++;
        }

        await _db.SaveChangesAsync(ct);
        return Ok(saved, $"Attendance saved for {req.Date:dd MMM yyyy}.");
    }

    /// <summary>One worker's month: every day plus the totals.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpGet("{id:int}/attendance")]
    public async Task<IActionResult> AttendanceMonth(int id, [FromQuery] int? year, [FromQuery] int? month,
                                                     CancellationToken ct)
    {
        var w = await _db.Workers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();
        return Ok(await MonthAsync(w, year ?? Today.Year, month ?? Today.Month, ct));
    }

    // ------------------------------------------------------------ worker self

    /// <summary>The signed-in worker's day: attendance plus what they have sold.</summary>
    [Authorize(Roles = Roles.Worker)]
    [HttpGet("me/today")]
    public async Task<IActionResult> MyToday(CancellationToken ct)
    {
        var w = await MeAsync(ct);
        if (w is null) return Forbidden("Your worker account is not active.");

        var today = Today;
        var att = await _db.WorkerAttendance.AsNoTracking()
                           .FirstOrDefaultAsync(a => a.WorkerId == w.Id && a.WorkDate == today, ct);

        var fromUtc = IndiaTime.ToUtc(today.ToDateTime(TimeOnly.MinValue));
        var toUtc = fromUtc.AddDays(1);
        var bills = await _db.Invoices.AsNoTracking()
                             .Where(i => i.BilledByWorkerId == w.Id && i.InvoiceDate >= fromUtc &&
                                         i.InvoiceDate < toUtc && i.Status != InvoiceStatus.Cancelled)
                             .Select(i => new { i.Id, i.GrandTotal }).ToListAsync(ct);
        var billIds = bills.Select(b => b.Id).ToList();
        var pays = await _db.Payments.AsNoTracking()
                            .Where(p => p.InvoiceId != null && billIds.Contains(p.InvoiceId.Value))
                            .GroupBy(p => p.Mode).Select(g => new { Mode = g.Key, Amount = g.Sum(p => p.Amount) })
                            .ToListAsync(ct);

        return Ok(new WorkerTodayDto
        {
            Worker     = ToDto(w, att, 0),
            Status     = att?.Status,
            CheckIn    = att?.CheckIn,
            CheckOut   = att?.CheckOut,
            BillsToday = bills.Count,
            SalesToday = bills.Sum(b => b.GrandTotal),
            CashToday  = pays.Where(p => p.Mode == "Cash").Sum(p => p.Amount),
            UpiToday   = pays.Where(p => p.Mode == "UPI").Sum(p => p.Amount),
            CardToday  = pays.Where(p => p.Mode == "Card").Sum(p => p.Amount)
        });
    }

    [Authorize(Roles = Roles.Worker)]
    [HttpPost("me/check-in")]
    public async Task<IActionResult> CheckIn(CancellationToken ct)
    {
        var w = await MeAsync(ct);
        if (w is null) return Forbidden("Your worker account is not active.");

        var today = Today;
        var row = await _db.WorkerAttendance.FirstOrDefaultAsync(a => a.WorkerId == w.Id && a.WorkDate == today, ct);
        if (row?.CheckIn is not null)
            return Fail($"You already checked in at {IndiaTime.FromUtc(row.CheckIn.Value):hh:mm tt}.");

        if (row is null)
        {
            row = new WorkerAttendance { BusinessId = w.BusinessId, WorkerId = w.Id, WorkDate = today };
            _db.WorkerAttendance.Add(row);
        }
        row.Status = AttendanceStatus.Present;
        row.CheckIn = DateTime.UtcNow;
        row.MarkedByUserId = _me.UserId;
        row.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return Ok(Row(w, today, row), $"Checked in at {IndiaTime.FromUtc(row.CheckIn.Value):hh:mm tt}. Have a good day!");
    }

    [Authorize(Roles = Roles.Worker)]
    [HttpPost("me/check-out")]
    public async Task<IActionResult> CheckOut(CancellationToken ct)
    {
        var w = await MeAsync(ct);
        if (w is null) return Forbidden("Your worker account is not active.");

        var today = Today;
        var row = await _db.WorkerAttendance.FirstOrDefaultAsync(a => a.WorkerId == w.Id && a.WorkDate == today, ct);
        if (row?.CheckIn is null) return Fail("Check in first.");
        row.CheckOut = DateTime.UtcNow;
        row.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return Ok(Row(w, today, row), $"Checked out at {IndiaTime.FromUtc(row.CheckOut.Value):hh:mm tt}.");
    }

    [Authorize(Roles = Roles.Worker)]
    [HttpGet("me/attendance")]
    public async Task<IActionResult> MyAttendance([FromQuery] int? year, [FromQuery] int? month, CancellationToken ct)
    {
        var w = await MeAsync(ct);
        if (w is null) return Forbidden("Your worker account is not active.");
        return Ok(await MonthAsync(w, year ?? Today.Year, month ?? Today.Month, ct));
    }

    // ================================================================= advances

    [Authorize(Roles = Roles.Owners)]
    [HttpGet("{id:int}/advances")]
    public async Task<IActionResult> Advances(int id, CancellationToken ct)
    {
        var w = await _db.Workers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();

        var rows = await _db.WorkerAdvances.AsNoTracking().Where(a => a.WorkerId == id)
                            .OrderBy(a => a.AdvanceDate).ThenBy(a => a.Id).ToListAsync(ct);
        var recovered = await _db.WorkerPayrolls.Where(p => p.WorkerId == id).SumAsync(p => p.AdvanceDeducted, ct);

        // Oldest advances are recovered first.
        var list = new List<AdvanceDto>();
        foreach (var a in rows)
        {
            var isRecovered = false;
            if (!a.IsCancelled && recovered >= a.Amount) { recovered -= a.Amount; isRecovered = true; }
            else if (!a.IsCancelled) recovered = 0;
            list.Add(new AdvanceDto
            {
                Id = a.Id, WorkerId = w.Id, WorkerName = w.Name, AdvanceDate = a.AdvanceDate, Amount = a.Amount,
                PaymentMode = a.PaymentMode, Note = a.Note, Recovered = isRecovered, IsCancelled = a.IsCancelled
            });
        }
        list.Reverse();
        return Ok(list);
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/advances")]
    public async Task<IActionResult> GiveAdvance(int id, AdvanceRequest req, CancellationToken ct)
    {
        var w = await _db.Workers.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();
        if (!w.IsActive) return Fail("This worker is switched off.");

        await using var tx = await _db.Database.BeginTransactionAsync(ct);
        var when = req.Date is { } d ? DateTime.SpecifyKind(d, DateTimeKind.Utc) : DateTime.UtcNow;

        // The advance is money out of the shop today, so it shows in Expenses too.
        var exp = new Expense
        {
            BusinessId = w.BusinessId, Category = "Salary", Amount = req.Amount, ExpenseDate = when,
            PaymentMode = req.PaymentMode, PaidTo = w.Name,
            Note = "Salary advance" + (string.IsNullOrWhiteSpace(req.Note) ? "" : $" - {req.Note.Trim()}"),
            CreatedByUserId = _me.UserId
        };
        _db.Expenses.Add(exp);
        await _db.SaveChangesAsync(ct);

        var adv = new WorkerAdvance
        {
            BusinessId = w.BusinessId, WorkerId = w.Id, AdvanceDate = when, Amount = req.Amount,
            PaymentMode = req.PaymentMode, Note = Clean(req.Note), ExpenseId = exp.Id, CreatedByUserId = _me.UserId
        };
        _db.WorkerAdvances.Add(adv);
        await _books.AuditAsync(w.BusinessId, _me.UserId, "WorkerAdvance", "Worker", w.Id,
                                $"{w.Name} {req.Amount}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        var open = await OutstandingAdvancesAsync(new List<int> { w.Id }, ct);
        return Ok(open.GetValueOrDefault(w.Id),
                  $"Advance of Rs.{req.Amount:N2} given to {w.Name}. It will be taken from the next salary.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpPost("advances/{advanceId:int}/cancel")]
    public async Task<IActionResult> CancelAdvance(int advanceId, CancellationToken ct)
    {
        var a = await _db.WorkerAdvances.FirstOrDefaultAsync(x => x.Id == advanceId, ct);
        if (a is null) return NotFoundMsg("Advance not found.");
        if (!CanTouch(a.BusinessId)) return Forbidden();
        if (a.IsCancelled) return Fail("Already cancelled.");

        var open = await OutstandingAdvancesAsync(new List<int> { a.WorkerId }, ct);
        if (open.GetValueOrDefault(a.WorkerId) < a.Amount)
            return Fail("Part of this advance was already taken back from a salary, so it cannot be cancelled.");

        a.IsCancelled = true;
        if (a.ExpenseId is { } expId)
        {
            var exp = await _db.Expenses.FirstOrDefaultAsync(e => e.Id == expId, ct);
            if (exp is not null) exp.IsCancelled = true;
        }
        await _books.AuditAsync(a.BusinessId, _me.UserId, "CancelWorkerAdvance", "WorkerAdvance", a.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Advance cancelled.");
    }

    // ================================================================== payroll

    /// <summary>Salary sheet for a month: paid rows as saved, unpaid rows worked out from attendance.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpGet("payroll")]
    public async Task<IActionResult> PayrollSheet([FromQuery] int? year, [FromQuery] int? month,
                                                  [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");
        var y = year ?? Today.Year;
        var m = month ?? Today.Month;
        var monthEnd = new DateOnly(y, m, DateTime.DaysInMonth(y, m));

        var paid = await _db.WorkerPayrolls.AsNoTracking().Include(p => p.Worker)
                            .Where(p => p.BusinessId == bizId && p.Year == y && p.Month == m)
                            .ToListAsync(ct);
        var paidIds = paid.Select(p => p.WorkerId).ToHashSet();

        var workers = await _db.Workers.AsNoTracking()
                               .Where(w => w.BusinessId == bizId && w.IsActive && w.JoinDate <= monthEnd)
                               .OrderBy(w => w.Name).ToListAsync(ct);
        var unpaid = workers.Where(w => !paidIds.Contains(w.Id)).ToList();
        var open = await OutstandingAdvancesAsync(workers.Select(w => w.Id).ToList(), ct);

        var rows = paid.Select(p => ToDto(p, open.GetValueOrDefault(p.WorkerId))).ToList();
        foreach (var w in unpaid)
            rows.Add(await ComputeAsync(w, y, m, null, 0, 0, null, open.GetValueOrDefault(w.Id), ct));

        return Ok(rows.OrderBy(r => r.IsPaid).ThenBy(r => r.WorkerName).ToList());
    }

    /// <summary>Works the salary out with the owner's changes, without saving (for the pay screen).</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/payroll/preview")]
    public async Task<IActionResult> PreviewPayroll(int id, PayrollPayRequest req, CancellationToken ct)
    {
        var w = await _db.Workers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();

        var open = await OutstandingAdvancesAsync(new List<int> { id }, ct);
        return Ok(await ComputeAsync(w, req.Year, req.Month, req.PayableDays, req.Bonus, req.OtherDeductions,
                                     req.AdvanceDeducted, open.GetValueOrDefault(id), ct));
    }

    /// <summary>Pays one worker's salary for the month and records it as a Salary expense.</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpPost("{id:int}/payroll")]
    public async Task<IActionResult> PayPayroll(int id, PayrollPayRequest req, CancellationToken ct)
    {
        var w = await _db.Workers.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();
        if (await _db.WorkerPayrolls.AnyAsync(p => p.WorkerId == id && p.Year == req.Year && p.Month == req.Month, ct))
            return Fail($"{w.Name}'s salary for {new DateTime(req.Year, req.Month, 1):MMMM yyyy} is already paid.");

        var open = await OutstandingAdvancesAsync(new List<int> { id }, ct);
        var calc = await ComputeAsync(w, req.Year, req.Month, req.PayableDays, req.Bonus, req.OtherDeductions,
                                      req.AdvanceDeducted, open.GetValueOrDefault(id), ct);
        if (calc.NetPay < 0) return Fail("Deductions are more than the salary. Reduce the deductions or advance recovery.");

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        Expense? exp = null;
        if (calc.NetPay > 0)
        {
            exp = new Expense
            {
                BusinessId = w.BusinessId, Category = "Salary", Amount = calc.NetPay, ExpenseDate = DateTime.UtcNow,
                PaymentMode = req.PaymentMode, PaidTo = w.Name,
                Note = $"Salary {new DateTime(req.Year, req.Month, 1):MMM yyyy}"
                     + (calc.AdvanceDeducted > 0 ? $" (advance Rs.{calc.AdvanceDeducted:N0} recovered)" : ""),
                CreatedByUserId = _me.UserId
            };
            _db.Expenses.Add(exp);
            await _db.SaveChangesAsync(ct);
        }

        var p = new WorkerPayroll
        {
            BusinessId = w.BusinessId, WorkerId = w.Id, Year = req.Year, Month = req.Month,
            SalaryType = w.SalaryType, SalaryAmount = w.SalaryAmount, DaysInMonth = calc.DaysInMonth,
            PresentDays = calc.PresentDays, HalfDays = calc.HalfDays, LeaveDays = calc.LeaveDays,
            AbsentDays = calc.AbsentDays, PayableDays = calc.PayableDays, GrossPay = calc.GrossPay,
            Bonus = calc.Bonus, OtherDeductions = calc.OtherDeductions, AdvanceDeducted = calc.AdvanceDeducted,
            NetPay = calc.NetPay, PaymentMode = req.PaymentMode, Note = Clean(req.Note),
            PaidOn = DateTime.UtcNow, ExpenseId = exp?.Id, CreatedByUserId = _me.UserId
        };
        _db.WorkerPayrolls.Add(p);
        await _books.AuditAsync(w.BusinessId, _me.UserId, "PayWorkerSalary", "Worker", w.Id,
                                $"{req.Year}-{req.Month:00} net={calc.NetPay}", ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        p.Worker = w;
        return Ok(ToDto(p, calc.OutstandingAdvance - calc.AdvanceDeducted),
                  $"Salary of Rs.{calc.NetPay:N2} paid to {w.Name}.");
    }

    [Authorize(Roles = Roles.Owners)]
    [HttpGet("{id:int}/payroll")]
    public async Task<IActionResult> PayrollHistory(int id, CancellationToken ct)
    {
        var w = await _db.Workers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (w is null) return NotFoundMsg("Worker not found.");
        if (!CanTouch(w.BusinessId)) return Forbidden();

        var rows = await _db.WorkerPayrolls.AsNoTracking().Include(p => p.Worker).Where(p => p.WorkerId == id)
                            .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month).ToListAsync(ct);
        return Ok(rows.Select(p => ToDto(p, 0)).ToList());
    }

    // ============================================================= sales report

    /// <summary>Who sold what: bills, sales and cash / UPI / card per worker (and the owner).</summary>
    [Authorize(Roles = Roles.Owners)]
    [HttpGet("sales")]
    public async Task<IActionResult> Sales([FromQuery] DateOnly? from, [FromQuery] DateOnly? to,
                                           [FromQuery] int? businessId, CancellationToken ct)
    {
        var bizId = ResolveBusinessId(_me, businessId);
        if (bizId is null) return Fail("A business must be selected.");

        var f = from ?? Today;
        var t = to ?? f;
        if (t < f) (f, t) = (t, f);
        var fromUtc = IndiaTime.ToUtc(f.ToDateTime(TimeOnly.MinValue));
        var toUtc = IndiaTime.ToUtc(t.AddDays(1).ToDateTime(TimeOnly.MinValue));

        var bills = await _db.Invoices.AsNoTracking()
                             .Where(i => i.BusinessId == bizId && i.InvoiceDate >= fromUtc && i.InvoiceDate < toUtc)
                             .Select(i => new { i.Id, i.BilledByWorkerId, i.GrandTotal, i.PaidAmount, i.BalanceAmount, i.Status })
                             .ToListAsync(ct);
        var liveIds = bills.Where(b => b.Status != InvoiceStatus.Cancelled).Select(b => b.Id).ToList();
        var pays = await _db.Payments.AsNoTracking()
                            .Where(p => p.InvoiceId != null && liveIds.Contains(p.InvoiceId.Value))
                            .Select(p => new { InvoiceId = p.InvoiceId!.Value, p.Mode, p.Amount, p.CardScope })
                            .ToListAsync(ct);
        var workerOf = bills.ToDictionary(b => b.Id, b => b.BilledByWorkerId);

        var workers = await _db.Workers.AsNoTracking().Where(w => w.BusinessId == bizId).ToListAsync(ct);
        var ownerName = await _db.Users.AsNoTracking()
                                 .Where(u => u.BusinessId == bizId && u.Role == Roles.BusinessUser)
                                 .Select(u => u.FullName).FirstOrDefaultAsync(ct);

        WorkerSalesRowDto Build(int? workerId, string name, string? designation)
        {
            var mine = bills.Where(b => b.BilledByWorkerId == workerId).ToList();
            var live = mine.Where(b => b.Status != InvoiceStatus.Cancelled).ToList();
            var myPays = pays.Where(p => workerOf.GetValueOrDefault(p.InvoiceId) == workerId).ToList();
            var sales = live.Sum(b => b.GrandTotal);
            return new WorkerSalesRowDto
            {
                WorkerId = workerId, Name = name, Designation = designation,
                Bills = live.Count, CancelledBills = mine.Count - live.Count,
                Sales = sales,
                Collected = live.Sum(b => b.PaidAmount),
                Udhaar = live.Sum(b => b.BalanceAmount),
                Cash = myPays.Where(p => p.Mode == "Cash").Sum(p => p.Amount),
                Upi = myPays.Where(p => p.Mode == "UPI").Sum(p => p.Amount),
                Card = myPays.Where(p => p.Mode == "Card").Sum(p => p.Amount),
                CardInternational = myPays.Where(p => p.Mode == "Card" && p.CardScope == "International").Sum(p => p.Amount),
                Other = myPays.Where(p => p.Mode is not ("Cash" or "UPI" or "Card")).Sum(p => p.Amount),
                AverageBill = live.Count == 0 ? 0 : decimal.Round(sales / live.Count, 2)
            };
        }

        var rows = new List<WorkerSalesRowDto> { Build(null, $"{ownerName ?? "Owner"} (owner)", "Owner") };
        foreach (var w in workers.Where(w => w.IsActive || bills.Any(b => b.BilledByWorkerId == w.Id))
                                 .OrderBy(w => w.Name))
            rows.Add(Build(w.Id, w.Name, w.Designation));

        return Ok(new WorkerSalesReportDto
        {
            From = f.ToDateTime(TimeOnly.MinValue), To = t.ToDateTime(TimeOnly.MinValue),
            Rows = rows.OrderByDescending(r => r.Sales).ToList(),
            TotalSales = rows.Sum(r => r.Sales), TotalBills = rows.Sum(r => r.Bills)
        });
    }

    // ================================================================== helpers

    private bool CanTouch(int businessId) => _me.IsSuperAdmin || _me.BusinessId == businessId;

    private Task<Worker?> MeAsync(CancellationToken ct) =>
        _db.Workers.AsNoTracking().FirstOrDefaultAsync(w => w.UserId == _me.UserId && w.IsActive, ct);

    private static string? Clean(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    private static string? ValidateWorker(WorkerRequest r)
    {
        if (string.IsNullOrWhiteSpace(r.Name)) return "Enter the worker's name.";
        if (r.SalaryType is not (SalaryTypes.Monthly or SalaryTypes.Daily)) return "Salary type must be Monthly or Daily.";
        return null;
    }

    /// <summary>Advances given minus what payrolls have already taken back, per worker.</summary>
    private async Task<Dictionary<int, decimal>> OutstandingAdvancesAsync(List<int> workerIds, CancellationToken ct)
    {
        var given = await _db.WorkerAdvances.AsNoTracking()
                             .Where(a => workerIds.Contains(a.WorkerId) && !a.IsCancelled)
                             .GroupBy(a => a.WorkerId).Select(g => new { g.Key, Sum = g.Sum(a => a.Amount) })
                             .ToDictionaryAsync(x => x.Key, x => x.Sum, ct);
        var taken = await _db.WorkerPayrolls.AsNoTracking()
                             .Where(p => workerIds.Contains(p.WorkerId))
                             .GroupBy(p => p.WorkerId).Select(g => new { g.Key, Sum = g.Sum(p => p.AdvanceDeducted) })
                             .ToDictionaryAsync(x => x.Key, x => x.Sum, ct);
        return workerIds.ToDictionary(id => id,
            id => Math.Max(0, given.GetValueOrDefault(id) - taken.GetValueOrDefault(id)));
    }

    private async Task<AttendanceMonthDto> MonthAsync(Worker w, int year, int month, CancellationToken ct)
    {
        if (month is < 1 or > 12) month = Today.Month;
        var first = new DateOnly(year, month, 1);
        var days = DateTime.DaysInMonth(year, month);
        var last = new DateOnly(year, month, days);
        var marks = await _db.WorkerAttendance.AsNoTracking()
                             .Where(a => a.WorkerId == w.Id && a.WorkDate >= first && a.WorkDate <= last)
                             .ToDictionaryAsync(a => a.WorkDate, ct);

        var dto = new AttendanceMonthDto
        {
            WorkerId = w.Id, WorkerName = w.Name, Year = year, Month = month, DaysInMonth = days
        };
        var today = Today;
        for (var d = first; d <= last; d = d.AddDays(1))
        {
            marks.TryGetValue(d, out var a);
            dto.Days.Add(Row(w, d, a));
            switch (a?.Status)
            {
                case AttendanceStatus.Present: dto.Present++; break;
                case AttendanceStatus.HalfDay: dto.HalfDay++; break;
                case AttendanceStatus.Absent:  dto.Absent++;  break;
                case AttendanceStatus.Leave:   dto.Leave++;   break;
                case AttendanceStatus.WeekOff: dto.WeekOff++; break;
                case null when d <= today && d >= w.JoinDate: dto.NotMarked++; break;
            }
        }
        return dto;
    }

    /// <summary>
    /// Salary maths. Monthly: salary x paid days / days in month. Daily: rate x paid days.
    /// Present, Leave and WeekOff are paid days, HalfDay is half, Absent and unmarked days are unpaid
    /// (the owner can override the paid days when attendance was not kept).
    /// </summary>
    private async Task<PayrollDto> ComputeAsync(Worker w, int year, int month, decimal? payableOverride,
                                                decimal bonus, decimal otherDeductions, decimal? advanceWanted,
                                                decimal outstandingAdvance, CancellationToken ct)
    {
        var att = await MonthAsync(w, year, month, ct);
        var paidDays = att.Present + att.HalfDay * 0.5m + att.Leave + att.WeekOff;
        var payable = Math.Clamp(payableOverride ?? paidDays, 0, att.DaysInMonth);

        var gross = w.SalaryType == SalaryTypes.Daily
            ? w.SalaryAmount * payable
            : w.SalaryAmount * payable / att.DaysInMonth;
        gross = decimal.Round(gross, 0, MidpointRounding.AwayFromZero);

        var beforeAdvance = gross + bonus - otherDeductions;
        var advance = Math.Clamp(advanceWanted ?? outstandingAdvance, 0, Math.Min(outstandingAdvance, Math.Max(0, beforeAdvance)));

        return new PayrollDto
        {
            WorkerId = w.Id, WorkerName = w.Name, Designation = w.Designation, Year = year, Month = month,
            SalaryType = w.SalaryType, SalaryAmount = w.SalaryAmount, DaysInMonth = att.DaysInMonth,
            PresentDays = att.Present, HalfDays = att.HalfDay, LeaveDays = att.Leave + att.WeekOff,
            AbsentDays = att.Absent, NotMarkedDays = att.NotMarked, PayableDays = payable,
            GrossPay = gross, Bonus = bonus, OtherDeductions = otherDeductions,
            AdvanceDeducted = advance, OutstandingAdvance = outstandingAdvance,
            NetPay = beforeAdvance - advance, IsPaid = false
        };
    }

    private static PayrollDto ToDto(WorkerPayroll p, decimal outstanding) => new()
    {
        Id = p.Id, WorkerId = p.WorkerId, WorkerName = p.Worker?.Name ?? "", Designation = p.Worker?.Designation,
        Year = p.Year, Month = p.Month, SalaryType = p.SalaryType, SalaryAmount = p.SalaryAmount,
        DaysInMonth = p.DaysInMonth, PresentDays = p.PresentDays, HalfDays = p.HalfDays, LeaveDays = p.LeaveDays,
        AbsentDays = p.AbsentDays, PayableDays = p.PayableDays, GrossPay = p.GrossPay, Bonus = p.Bonus,
        OtherDeductions = p.OtherDeductions, AdvanceDeducted = p.AdvanceDeducted, OutstandingAdvance = outstanding,
        NetPay = p.NetPay, IsPaid = true, PaidOn = p.PaidOn, PaymentMode = p.PaymentMode, Note = p.Note
    };

    private static WorkerDto ToDto(Worker w, WorkerAttendance? today, decimal openAdvance) => new()
    {
        Id = w.Id, Name = w.Name, Mobile = w.Mobile, Designation = w.Designation, SalaryType = w.SalaryType,
        SalaryAmount = w.SalaryAmount, JoinDate = w.JoinDate, Address = w.Address, CanGiveUdhaar = w.CanGiveUdhaar,
        IsActive = w.IsActive, HasLogin = w.UserId != null, LoginActive = w.User?.IsActive ?? w.UserId != null,
        TodayStatus = today?.Status, TodayCheckIn = today?.CheckIn, TodayCheckOut = today?.CheckOut,
        OutstandingAdvance = openAdvance
    };

    private static AttendanceRowDto Row(Worker w, DateOnly day, WorkerAttendance? a) => new()
    {
        WorkerId = w.Id, WorkerName = w.Name, Designation = w.Designation, WorkDate = day,
        Status = a?.Status, CheckIn = a?.CheckIn, CheckOut = a?.CheckOut, Note = a?.Note
    };
}
