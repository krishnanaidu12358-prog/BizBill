using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using BizFlow.Api.Entities;
using Microsoft.IdentityModel.Tokens;

namespace BizFlow.Api.Services;

public class JwtOptions
{
    public string Issuer { get; set; } = "BizFlow";
    public string Audience { get; set; } = "BizFlowApp";
    public string Key { get; set; } = "";
    public int AccessTokenMinutes { get; set; } = 480;
    public int RefreshTokenDays { get; set; } = 30;
}

public interface ITokenService
{
    (string token, DateTime expiresAt) CreateAccessToken(AppUser user);
    string CreateRefreshToken();
}

public class TokenService : ITokenService
{
    private readonly JwtOptions _opt;

    public TokenService(JwtOptions opt) => _opt = opt;

    public (string token, DateTime expiresAt) CreateAccessToken(AppUser user)
    {
        var expires = DateTime.UtcNow.AddMinutes(_opt.AccessTokenMinutes);
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.FullName),
            new(ClaimTypes.Role, user.Role),
            new("mobile", user.Mobile),
            new("businessId", (user.BusinessId ?? 0).ToString())
        };

        var creds = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_opt.Key)),
            SecurityAlgorithms.HmacSha256);

        var jwt = new JwtSecurityToken(
            issuer: _opt.Issuer,
            audience: _opt.Audience,
            claims: claims,
            expires: expires,
            signingCredentials: creds);

        return (new JwtSecurityTokenHandler().WriteToken(jwt), expires);
    }

    public string CreateRefreshToken()
    {
        var bytes = RandomNumberGenerator.GetBytes(48);
        return Convert.ToBase64String(bytes).Replace("+", "-").Replace("/", "_").TrimEnd('=');
    }
}
