using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Controllers;

/// <summary>Every account - admin, shop owner and customer - logs in with a 10-digit mobile number.</summary>
public class AuthController : ApiControllerBase
{
    private readonly AppDbContext _db;
    private readonly ITokenService _tokens;
    private readonly JwtOptions _jwt;
    private readonly ICurrentUser _me;
    private readonly IBookkeepingService _books;
    private readonly IWhatsAppService _whatsApp;
    private readonly ILogger<AuthController> _log;

    /// <summary>How long a forgot-password code works.</summary>
    private static readonly TimeSpan ResetCodeLife = TimeSpan.FromMinutes(10);
    /// <summary>Wrong tries allowed on one code before it stops working.</summary>
    private const int ResetMaxAttempts = 5;
    /// <summary>Codes one account may ask for in <see cref="ResetWindow"/>.</summary>
    private const int ResetMaxPerWindow = 3;
    private static readonly TimeSpan ResetWindow = TimeSpan.FromMinutes(30);

    /// <summary>Who may reset their own password: shop owners and customers.</summary>
    private static readonly string[] SelfResetRoles = { Roles.BusinessUser, Roles.Customer };

    public AuthController(AppDbContext db, ITokenService tokens, JwtOptions jwt,
                          ICurrentUser me, IBookkeepingService books,
                          IWhatsAppService whatsApp, ILogger<AuthController> log)
    {
        _db = db; _tokens = tokens; _jwt = jwt; _me = me; _books = books;
        _whatsApp = whatsApp; _log = log;
    }

    [AllowAnonymous]
    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest req, CancellationToken ct)
    {
        var mobile = Normalize(req.Mobile);
        var user = await _db.Users.Include(u => u.Business)
                                  .FirstOrDefaultAsync(u => u.Mobile == mobile, ct);

        if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
            return Fail("Invalid mobile number or password.", StatusCodes.Status401Unauthorized);

        if (!user.IsActive)
            return Fail("This account has been deactivated. Contact support.", StatusCodes.Status403Forbidden);

        if ((user.Role == Roles.BusinessUser || user.Role == Roles.Worker) && user.Business is { IsActive: false })
            return Fail("Your business account is suspended. Contact the administrator.", StatusCodes.Status403Forbidden);

        if (user.Role == Roles.Worker &&
            !await _db.Workers.AnyAsync(w => w.UserId == user.Id && w.IsActive, ct))
            return Fail("Your worker account is switched off. Ask the shop owner.", StatusCodes.Status403Forbidden);

        user.LastLoginAt = DateTime.UtcNow;
        await _books.AuditAsync(user.BusinessId, user.Id, "Login", "AppUser", user.Id, null, ClientIp, ct);

        var auth = await IssueTokensAsync(user, ct);
        return Ok(auth, "Login successful.");
    }

    /// <summary>A shop owner signs up; this creates the business tenant and the BusinessUser account.</summary>
    [AllowAnonymous]
    [HttpPost("register-business")]
    public async Task<IActionResult> RegisterBusiness(RegisterBusinessRequest req, CancellationToken ct)
    {
        var mobile = Normalize(req.Mobile);
        if (await _db.Users.AnyAsync(u => u.Mobile == mobile, ct))
            return Fail("An account already exists for this mobile number. Please log in.");

        var biz = new Business
        {
            Name      = req.BusinessName.Trim(),
            OwnerName = req.OwnerName.Trim(),
            Mobile    = mobile,
            Email     = req.Email,
            City      = req.City,
            State     = req.State,
            GstNumber = req.GstNumber,
            BusinessType = req.BusinessType is { } t && BusinessTypes.All.Contains(t) ? t : "Retail"
        };
        _db.Businesses.Add(biz);
        await _db.SaveChangesAsync(ct);

        var user = new AppUser
        {
            BusinessId   = biz.Id,
            Mobile       = mobile,
            FullName     = req.OwnerName.Trim(),
            Email        = req.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password),
            Role         = Roles.BusinessUser
        };
        _db.Users.Add(user);
        await _books.AuditAsync(biz.Id, null, "RegisterBusiness", "Business", biz.Id, biz.Name, ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        user.Business = biz;
        var auth = await IssueTokensAsync(user, ct);
        return Ok(auth, "Business registered successfully.");
    }

    /// <summary>
    /// A customer activates the app account for their mobile number. If a shop already
    /// added them as a customer, those records are linked to the new login automatically.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("register-customer")]
    public async Task<IActionResult> RegisterCustomer(RegisterCustomerRequest req, CancellationToken ct)
    {
        var mobile = Normalize(req.Mobile);
        if (await _db.Users.AnyAsync(u => u.Mobile == mobile, ct))
            return Fail("An account already exists for this mobile number. Please log in.");

        var user = new AppUser
        {
            Mobile       = mobile,
            FullName     = req.FullName.Trim(),
            Email        = req.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password),
            Role         = Roles.Customer
        };
        _db.Users.Add(user);
        await _db.SaveChangesAsync(ct);

        // Link every shop record that already uses this number.
        var existing = await _db.Customers.Where(c => c.Mobile == mobile && c.UserId == null).ToListAsync(ct);
        foreach (var c in existing) c.UserId = user.Id;

        await _books.AuditAsync(null, user.Id, "RegisterCustomer", "AppUser", user.Id,
                                $"linked {existing.Count} shop record(s)", ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        var auth = await IssueTokensAsync(user, ct);
        return Ok(auth, existing.Count > 0
            ? $"Account created and linked to {existing.Count} shop(s)."
            : "Account created successfully.");
    }

    [AllowAnonymous]
    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(RefreshRequest req, CancellationToken ct)
    {
        var token = await _db.RefreshTokens.FirstOrDefaultAsync(t => t.Token == req.RefreshToken, ct);
        if (token is null || token.RevokedAt != null || token.ExpiresAt <= DateTime.UtcNow)
            return Fail("Refresh token is invalid or expired.", StatusCodes.Status401Unauthorized);

        var user = await _db.Users.Include(u => u.Business).FirstOrDefaultAsync(u => u.Id == token.UserId, ct);
        if (user is null || !user.IsActive)
            return Fail("Account is no longer active.", StatusCodes.Status401Unauthorized);

        token.RevokedAt = DateTime.UtcNow;
        var auth = await IssueTokensAsync(user, ct);
        return Ok(auth, "Token refreshed.");
    }

    [Authorize]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(CancellationToken ct)
    {
        var active = await _db.RefreshTokens
                              .Where(t => t.UserId == _me.UserId && t.RevokedAt == null)
                              .ToListAsync(ct);
        foreach (var t in active) t.RevokedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Logged out.");
    }

    [Authorize]
    [HttpGet("me")]
    public async Task<IActionResult> Me(CancellationToken ct)
    {
        var user = await _db.Users.Include(u => u.Business)
                                  .FirstOrDefaultAsync(u => u.Id == _me.UserId, ct);
        if (user is null) return NotFoundMsg("Account not found.");
        return Ok(await ProfileAsync(user, ct));
    }

    [Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest req, CancellationToken ct)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == _me.UserId, ct);
        if (user is null) return NotFoundMsg("Account not found.");

        if (!BCrypt.Net.BCrypt.Verify(req.CurrentPassword, user.PasswordHash))
            return Fail("Current password is incorrect.");

        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
        await _books.AuditAsync(user.BusinessId, user.Id, "ChangePassword", "AppUser", user.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);
        return Ok(true, "Password changed.");
    }

    // ------------------------------------------------------------ forgot password

    /// <summary>
    /// Step 1 of "Forgot password": sends a 6-digit code to the account's mobile on
    /// WhatsApp. For shop owners and customers. The answer is the same whether or
    /// not the number has an account, so nobody can use this to find out who is
    /// registered.
    /// </summary>
    [AllowAnonymous]
    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword(ForgotPasswordRequest req, CancellationToken ct)
    {
        const string reply =
            "If this number has a shop owner or customer account, a 6-digit code has been sent to it on WhatsApp. " +
            "The code works for 10 minutes.";

        var mobile = Normalize(req.Mobile);
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Mobile == mobile, ct);

        if (user is null || !user.IsActive || !SelfResetRoles.Contains(user.Role))
        {
            if (user is { Role: Roles.Worker })
                _log.LogInformation("Password reset asked for worker account {UserId}; the shop owner resets workers.", user.Id);
            return Ok(true, reply);
        }

        var now = DateTime.UtcNow;
        var recent = await _db.PasswordResets
            .Where(r => r.UserId == user.Id && r.CreatedAt > now - ResetWindow)
            .OrderByDescending(r => r.CreatedAt)
            .ToListAsync(ct);

        // One code a minute, three in half an hour - enough for a slow WhatsApp,
        // not enough to flood somebody's phone.
        if (recent.Count >= ResetMaxPerWindow ||
            (recent.Count > 0 && recent[0].CreatedAt > now.AddMinutes(-1)))
        {
            _log.LogInformation("Password reset for user {UserId} throttled.", user.Id);
            return Ok(true, reply);
        }

        // Only the newest code counts.
        foreach (var old in recent.Where(r => r.UsedAt == null)) old.UsedAt = now;

        var code = System.Security.Cryptography.RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        _db.PasswordResets.Add(new PasswordReset
        {
            UserId    = user.Id,
            CodeHash  = BCrypt.Net.BCrypt.HashPassword(code),
            ExpiresAt = now + ResetCodeLife,
            RequestIp = ClientIp
        });
        await _books.AuditAsync(user.BusinessId, user.Id, "ForgotPassword", "AppUser", user.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        await _whatsApp.SendAsync("password_reset", user.Mobile,
            $"BizBill: your password reset code is {code}. It works for 10 minutes. " +
            "Do not share it with anyone - BizBill staff will never ask for it.",
            businessId: user.BusinessId, ct: ct);

        return Ok(true, reply);
    }

    /// <summary>Step 2: the code from WhatsApp plus a new password.</summary>
    [AllowAnonymous]
    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword(ResetPasswordRequest req, CancellationToken ct)
    {
        const string wrong = "That code is wrong or has expired. Ask for a new code.";

        var mobile = Normalize(req.Mobile);
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Mobile == mobile, ct);
        if (user is null || !user.IsActive || !SelfResetRoles.Contains(user.Role))
            return Fail(wrong);

        var now = DateTime.UtcNow;
        var reset = await _db.PasswordResets
            .Where(r => r.UserId == user.Id && r.UsedAt == null && r.ExpiresAt > now)
            .OrderByDescending(r => r.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (reset is null) return Fail(wrong);

        if (!BCrypt.Net.BCrypt.Verify(req.Code.Trim(), reset.CodeHash))
        {
            reset.Attempts++;
            if (reset.Attempts >= ResetMaxAttempts) reset.UsedAt = now;
            await _db.SaveChangesAsync(ct);
            return Fail(reset.UsedAt is null
                ? $"That code is wrong. {ResetMaxAttempts - reset.Attempts} tries left."
                : "Too many wrong tries. Ask for a new code.");
        }

        reset.UsedAt = now;
        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);

        // Sign every device out: whoever had the old password is no longer let in.
        var sessions = await _db.RefreshTokens
            .Where(t => t.UserId == user.Id && t.RevokedAt == null)
            .ToListAsync(ct);
        foreach (var t in sessions) t.RevokedAt = now;

        await _books.AuditAsync(user.BusinessId, user.Id, "ResetPassword", "AppUser", user.Id, null, ClientIp, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(true, "Password changed. Log in with your new password.");
    }

    // ------------------------------------------------------------------

    private async Task<AuthResponse> IssueTokensAsync(AppUser user, CancellationToken ct)
    {
        var (access, expiresAt) = _tokens.CreateAccessToken(user);
        var refresh = new RefreshToken
        {
            UserId    = user.Id,
            Token     = _tokens.CreateRefreshToken(),
            ExpiresAt = DateTime.UtcNow.AddDays(_jwt.RefreshTokenDays)
        };
        _db.RefreshTokens.Add(refresh);
        await _db.SaveChangesAsync(ct);

        return new AuthResponse
        {
            AccessToken  = access,
            RefreshToken = refresh.Token,
            ExpiresAt    = expiresAt,
            User         = await ProfileAsync(user, ct)
        };
    }

    /// <summary>Appearance settings live on the account so they follow the user across devices.</summary>
    [Authorize]
    [HttpPut("preferences")]
    public async Task<IActionResult> UpdatePreferences(PreferencesRequest req, CancellationToken ct)
    {
        var allowedModes = new[] { "System", "Light", "Dark" };
        if (!allowedModes.Contains(req.ThemeMode))
            return Fail("Theme mode must be System, Light or Dark.");

        var user = await _db.Users.Include(u => u.Business)
                                  .FirstOrDefaultAsync(u => u.Id == _me.UserId, ct);
        if (user is null) return NotFoundMsg("Account not found.");

        user.ThemeMode = req.ThemeMode;
        user.ThemeName = req.ThemeName;
        await _db.SaveChangesAsync(ct);
        return Ok(await ProfileAsync(user, ct), "Appearance saved.");
    }

    private async Task<UserProfileDto> ProfileAsync(AppUser u, CancellationToken ct)
    {
        var dto = Profile(u);
        if (u.Role == Roles.Worker)
        {
            var w = await _db.Workers.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == u.Id, ct);
            if (w is not null)
            {
                dto.WorkerId      = w.Id;
                dto.Designation   = w.Designation;
                dto.CanGiveUdhaar = w.CanGiveUdhaar;
            }
        }
        return dto;
    }

    internal static UserProfileDto Profile(AppUser u) => new()
    {
        Id = u.Id, Mobile = u.Mobile, FullName = u.FullName, Email = u.Email,
        Role = u.Role, BusinessId = u.BusinessId, BusinessName = u.Business?.Name,
        ThemeMode = u.ThemeMode, ThemeName = u.ThemeName
    };

    internal static string Normalize(string mobile)
    {
        var digits = new string((mobile ?? "").Where(char.IsDigit).ToArray());
        // Accept 0XXXXXXXXXX / 91XXXXXXXXXX and store the bare 10 digits.
        if (digits.Length > 10) digits = digits[^10..];
        return digits;
    }
}


