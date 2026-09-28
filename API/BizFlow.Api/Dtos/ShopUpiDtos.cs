using System.ComponentModel.DataAnnotations;

namespace BizFlow.Api.Dtos;

/// <summary>A shop's UPI details, as the owner sets them and the customer sees them.</summary>
public class ShopUpiDto
{
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    /// <summary>Null when the shop has not set up UPI yet.</summary>
    public string? UpiId { get; set; }
    public string UpiName { get; set; } = "";
    /// <summary>Filled in for the customer: what they owe this shop.</summary>
    public decimal? Outstanding { get; set; }
}

public class ShopUpiRequest
{
    /// <summary>Empty turns UPI payments off.</summary>
    [MaxLength(100)] public string? UpiId { get; set; }
    [MaxLength(100)] public string? UpiName { get; set; }
}
