namespace BizFlow.Api.Entities;

/// <summary>
/// HRMS for a shop: the people who work the counter, their attendance,
/// salary advances and monthly payroll.
/// </summary>
public static class AttendanceStatus
{
    public const string Present = "Present";
    public const string HalfDay = "HalfDay";
    public const string Absent  = "Absent";
    /// <summary>Paid leave.</summary>
    public const string Leave   = "Leave";
    /// <summary>Weekly off / holiday - paid.</summary>
    public const string WeekOff = "WeekOff";

    public static readonly string[] All = { Present, HalfDay, Absent, Leave, WeekOff };

    /// <summary>How much of a day's pay this status earns.</summary>
    public static decimal PaidFraction(string status) => status switch
    {
        Present => 1m,
        HalfDay => 0.5m,
        Leave   => 1m,
        WeekOff => 1m,
        _       => 0m
    };
}

public static class SalaryTypes
{
    /// <summary>Fixed amount a month, pro-rated by paid days.</summary>
    public const string Monthly = "Monthly";
    /// <summary>Paid per day worked.</summary>
    public const string Daily   = "Daily";
}

public class Worker
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    /// <summary>Set when the worker has a login to bill at the counter.</summary>
    public int? UserId { get; set; }
    public string Name { get; set; } = "";
    public string Mobile { get; set; } = "";
    public string? Designation { get; set; }
    public string SalaryType { get; set; } = SalaryTypes.Monthly;
    /// <summary>Monthly salary, or the day rate when SalaryType is Daily.</summary>
    public decimal SalaryAmount { get; set; }
    public DateOnly JoinDate { get; set; } = DateOnly.FromDateTime(DateTime.UtcNow);
    public string? Address { get; set; }
    /// <summary>May this worker leave an unpaid balance (Udhaar) on a bill?</summary>
    public bool CanGiveUdhaar { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Business? Business { get; set; }
    public AppUser? User { get; set; }
}

public class WorkerAttendance
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int WorkerId { get; set; }
    /// <summary>Shop-local (India) calendar day.</summary>
    public DateOnly WorkDate { get; set; }
    public string Status { get; set; } = AttendanceStatus.Present;
    public DateTime? CheckIn { get; set; }
    public DateTime? CheckOut { get; set; }
    public string? Note { get; set; }
    public int? MarkedByUserId { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Worker? Worker { get; set; }
}

/// <summary>Money given to a worker ahead of salary. Deducted in the next payroll.</summary>
public class WorkerAdvance
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int WorkerId { get; set; }
    public DateTime AdvanceDate { get; set; } = DateTime.UtcNow;
    public decimal Amount { get; set; }
    public string PaymentMode { get; set; } = "Cash";
    public string? Note { get; set; }
    /// <summary>The payroll that recovered it; null while still outstanding.</summary>
    public int? PayrollId { get; set; }
    public int? ExpenseId { get; set; }
    public bool IsCancelled { get; set; }
    public int? CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Worker? Worker { get; set; }
}

/// <summary>One month's salary for one worker. Saved when the salary is paid.</summary>
public class WorkerPayroll
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public int WorkerId { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public string SalaryType { get; set; } = SalaryTypes.Monthly;
    public decimal SalaryAmount { get; set; }
    public int DaysInMonth { get; set; }
    public decimal PresentDays { get; set; }
    public decimal HalfDays { get; set; }
    public decimal LeaveDays { get; set; }
    public decimal AbsentDays { get; set; }
    /// <summary>Days the salary is paid for (after any owner override).</summary>
    public decimal PayableDays { get; set; }
    public decimal GrossPay { get; set; }
    public decimal Bonus { get; set; }
    public decimal OtherDeductions { get; set; }
    public decimal AdvanceDeducted { get; set; }
    public decimal NetPay { get; set; }
    public string PaymentMode { get; set; } = "Cash";
    public string? Note { get; set; }
    public DateTime PaidOn { get; set; } = DateTime.UtcNow;
    public int? ExpenseId { get; set; }
    public int? CreatedByUserId { get; set; }

    public Worker? Worker { get; set; }
}

/// <summary>Card types the counter card machine can take.</summary>
public static class CardInfo
{
    public static readonly string[] Scopes   = { "Domestic", "International" };
    public static readonly string[] Types    = { "Debit", "Credit", "Prepaid" };
    public static readonly string[] Networks =
        { "Visa", "Mastercard", "RuPay", "Amex", "Diners", "Discover", "JCB", "UnionPay", "Maestro", "Other" };
}
