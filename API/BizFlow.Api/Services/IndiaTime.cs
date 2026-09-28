namespace BizFlow.Api.Services;

/// <summary>
/// Shops are in India. Storage is UTC; anything a person reads (message text,
/// "today", chart buckets) is in IST whatever zone the server runs in.
/// </summary>
public static class IndiaTime
{
    public static readonly TimeZoneInfo Zone = Find();

    private static TimeZoneInfo Find()
    {
        foreach (var id in new[] { "India Standard Time", "Asia/Kolkata" })
            try { return TimeZoneInfo.FindSystemTimeZoneById(id); } catch (TimeZoneNotFoundException) { }
        return TimeZoneInfo.Local;
    }

    public static DateTime FromUtc(DateTime utc) =>
        TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utc, DateTimeKind.Utc), Zone);

    public static DateTime ToUtc(DateTime ist) =>
        TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(ist, DateTimeKind.Unspecified), Zone);

    public static DateTime Today => FromUtc(DateTime.UtcNow).Date;
}
