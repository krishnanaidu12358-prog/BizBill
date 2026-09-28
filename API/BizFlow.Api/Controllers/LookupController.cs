using BizFlow.Api.Dtos;
using BizFlow.Api.Entities;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace BizFlow.Api.Controllers;

/// <summary>
/// A shop owner types a mobile number and gets that customer's standing across
/// BizFlow: a computed rating, how many shops they buy from, and whether they
/// are running late anywhere. No other shop's rupee amounts or names are shown.
/// </summary>
[Authorize(Roles = Roles.BusinessUser + "," + Roles.SuperAdmin)]
[Route("api/lookup")]
public class LookupController : ApiControllerBase
{
    private readonly ICustomerInsightService _insight;
    private readonly ICurrentUser _me;

    public LookupController(ICustomerInsightService insight, ICurrentUser me)
    {
        _insight = insight; _me = me;
    }

    [HttpGet("customer/{mobile}")]
    public async Task<IActionResult> Customer(string mobile, [FromQuery] int? businessId,
                                              CancellationToken ct)
    {
        var normalized = AuthController.Normalize(mobile);
        if (normalized.Length != 10)
            return Fail("Enter a valid 10-digit mobile number.");

        var bizId = ResolveBusinessId(_me, businessId);
        var result = await _insight.LookupAsync(normalized, bizId, ct);

        return Ok(ToDto(result), result.Found
            ? "Customer found."
            : "No record for this number yet.");
    }

    internal static CustomerInsightDto ToDto(CustomerInsight i) => new()
    {
        Found = i.Found, Mobile = i.Mobile, Name = i.Name, HasAppAccount = i.HasAppAccount,
        MemberSince = i.MemberSince, Rating = i.Rating, RatingLabel = i.RatingLabel,
        ShopCount = i.ShopCount, TotalBills = i.TotalBills, PaymentSignal = i.PaymentSignal,
        HasOverdueElsewhere = i.HasOverdueElsewhere, Summary = i.Summary,
        ThisShop = i.ThisShop is null ? null : new CustomerInsightLocalDto
        {
            CustomerId = i.ThisShop.CustomerId, Name = i.ThisShop.Name,
            IsTrusted = i.ThisShop.IsTrusted, CreditLimit = i.ThisShop.CreditLimit,
            OutstandingBalance = i.ThisShop.OutstandingBalance,
            CreditBalance = i.ThisShop.CreditBalance,
            BillCount = i.ThisShop.BillCount, LastBillOn = i.ThisShop.LastBillOn
        }
    };
}
