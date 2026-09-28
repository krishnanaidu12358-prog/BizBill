using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Services;

/// <summary>
/// A worker's login token lives for hours. When the owner switches a worker off,
/// this stops that token at the very next request instead of when it expires.
/// </summary>
public class ActiveWorkerFilter : IAsyncActionFilter
{
    private readonly ICurrentUser _me;
    private readonly AppDbContext _db;

    public ActiveWorkerFilter(ICurrentUser me, AppDbContext db)
    {
        _me = me; _db = db;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext ctx, ActionExecutionDelegate next)
    {
        if (_me.IsAuthenticated && _me.Role == Roles.Worker)
        {
            var ok = await _db.Workers.AsNoTracking().AnyAsync(w =>
                w.UserId == _me.UserId && w.IsActive &&
                w.User != null && w.User.IsActive &&
                w.Business != null && w.Business.IsActive);
            if (!ok)
            {
                ctx.Result = new ObjectResult(ApiResponse<object>.Fail(
                    "Your worker account is switched off. Ask the shop owner."))
                { StatusCode = StatusCodes.Status401Unauthorized };
                return;
            }
        }
        await next();
    }
}
