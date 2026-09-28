using System.Security.Claims;

namespace BizFlow.Api.Services;

/// <summary>
/// Tenant context is always derived from the JWT, never from the request body
/// (FRD FR-040 / security requirement 12.1).
/// </summary>
public interface ICurrentUser
{
    int UserId { get; }
    string Mobile { get; }
    string Role { get; }
    int? BusinessId { get; }
    bool IsSuperAdmin { get; }
    bool IsAuthenticated { get; }
}

public class CurrentUser : ICurrentUser
{
    private readonly ClaimsPrincipal? _principal;

    public CurrentUser(IHttpContextAccessor accessor) => _principal = accessor.HttpContext?.User;

    public bool IsAuthenticated => _principal?.Identity?.IsAuthenticated == true;
    public int UserId => int.TryParse(_principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : 0;
    public string Mobile => _principal?.FindFirstValue("mobile") ?? "";
    public string Role => _principal?.FindFirstValue(ClaimTypes.Role) ?? "";
    public int? BusinessId =>
        int.TryParse(_principal?.FindFirstValue("businessId"), out var b) && b > 0 ? b : null;
    public bool IsSuperAdmin => Role == Entities.Roles.SuperAdmin;
}
