using System.ComponentModel.DataAnnotations;

namespace BizFlow.Api.Dtos;

// ------------------------------------------------------------- workers

public class WorkerRequest
{
    [Required] public string Name { get; set; } = "";
    [Required, RegularExpression(@"^\d{10}$", ErrorMessage = "Mobile must be 10 digits.")]
    public string Mobile { get; set; } = "";
    public string? Designation { get; set; }
    /// <summary>Monthly or Daily</summary>
    public string SalaryType { get; set; } = "Monthly";
    [Range(0, 99999999)] public decimal SalaryAmount { get; set; }
    public DateOnly? JoinDate { get; set; }
    public string? Address { get; set; }
    public bool CanGiveUdhaar { get; set; }
    /// <summary>On create: also make a counter login with this password (min 6).</summary>
    public string? LoginPassword { get; set; }
}

public class WorkerLoginRequest
{
    [Required, MinLength(6)] public string Password { get; set; } = "";
}

public class WorkerDto
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Mobile { get; set; } = "";
    public string? Designation { get; set; }
    public string SalaryType { get; set; } = "Monthly";
    public decimal SalaryAmount { get; set; }
    public DateOnly JoinDate { get; set; }
    public string? Address { get; set; }
    public bool CanGiveUdhaar { get; set; }
    public bool IsActive { get; set; }
    public bool HasLogin { get; set; }
    public bool LoginActive { get; set; }
    /// <summary>Today's attendance, if marked.</summary>
    public string? TodayStatus { get; set; }
    public DateTime? TodayCheckIn { get; set; }
    public DateTime? TodayCheckOut { get; set; }
    /// <summary>Advances not yet recovered from salary.</summary>
    public decimal OutstandingAdvance { get; set; }
}

// ---------------------------------------------------------- attendance

public class AttendanceRowDto
{
    public int WorkerId { get; set; }
    public string WorkerName { get; set; } = "";
    public string? Designation { get; set; }
    public DateOnly WorkDate { get; set; }
    /// <summary>Null when not marked yet.</summary>
    public string? Status { get; set; }
    public DateTime? CheckIn { get; set; }
    public DateTime? CheckOut { get; set; }
    public string? Note { get; set; }
}

public class AttendanceMarkRequest
{
    [Required] public int WorkerId { get; set; }
    /// <summary>Present / HalfDay / Absent / Leave / WeekOff. Empty clears the day.</summary>
    public string? Status { get; set; }
    public string? Note { get; set; }
}

public class AttendanceBulkRequest
{
    [Required] public DateOnly Date { get; set; }
    public List<AttendanceMarkRequest> Rows { get; set; } = new();
}

public class AttendanceMonthDto
{
    public int WorkerId { get; set; }
    public string WorkerName { get; set; } = "";
    public int Year { get; set; }
    public int Month { get; set; }
    public int DaysInMonth { get; set; }
    public decimal Present { get; set; }
    public decimal HalfDay { get; set; }
    public decimal Absent { get; set; }
    public decimal Leave { get; set; }
    public decimal WeekOff { get; set; }
    public int NotMarked { get; set; }
    public List<AttendanceRowDto> Days { get; set; } = new();
}

/// <summary>What the worker sees on their own counter screen.</summary>
public class WorkerTodayDto
{
    public WorkerDto Worker { get; set; } = new();
    public string? Status { get; set; }
    public DateTime? CheckIn { get; set; }
    public DateTime? CheckOut { get; set; }
    public int BillsToday { get; set; }
    public decimal SalesToday { get; set; }
    public decimal CashToday { get; set; }
    public decimal UpiToday { get; set; }
    public decimal CardToday { get; set; }
}

// ------------------------------------------------------------ advances

public class AdvanceRequest
{
    [Range(1, 99999999)] public decimal Amount { get; set; }
    public string PaymentMode { get; set; } = "Cash";
    public string? Note { get; set; }
    public DateTime? Date { get; set; }
}

public class AdvanceDto
{
    public int Id { get; set; }
    public int WorkerId { get; set; }
    public string WorkerName { get; set; } = "";
    public DateTime AdvanceDate { get; set; }
    public decimal Amount { get; set; }
    public string PaymentMode { get; set; } = "";
    public string? Note { get; set; }
    public bool Recovered { get; set; }
    public bool IsCancelled { get; set; }
}

// ------------------------------------------------------------- payroll

/// <summary>A worker's salary for one month - worked out, or already paid.</summary>
public class PayrollDto
{
    public int? Id { get; set; }
    public int WorkerId { get; set; }
    public string WorkerName { get; set; } = "";
    public string? Designation { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public string SalaryType { get; set; } = "Monthly";
    public decimal SalaryAmount { get; set; }
    public int DaysInMonth { get; set; }
    public decimal PresentDays { get; set; }
    public decimal HalfDays { get; set; }
    public decimal LeaveDays { get; set; }
    public decimal AbsentDays { get; set; }
    public int NotMarkedDays { get; set; }
    public decimal PayableDays { get; set; }
    public decimal GrossPay { get; set; }
    public decimal Bonus { get; set; }
    public decimal OtherDeductions { get; set; }
    public decimal AdvanceDeducted { get; set; }
    /// <summary>Advances still open for this worker (the most that can be recovered).</summary>
    public decimal OutstandingAdvance { get; set; }
    public decimal NetPay { get; set; }
    public bool IsPaid { get; set; }
    public DateTime? PaidOn { get; set; }
    public string? PaymentMode { get; set; }
    public string? Note { get; set; }
}

public class PayrollPayRequest
{
    [Range(2020, 2100)] public int Year { get; set; }
    [Range(1, 12)] public int Month { get; set; }
    /// <summary>Override the days paid (e.g. attendance was not marked). Null = from attendance.</summary>
    [Range(0, 31)] public decimal? PayableDays { get; set; }
    [Range(0, 99999999)] public decimal Bonus { get; set; }
    [Range(0, 99999999)] public decimal OtherDeductions { get; set; }
    /// <summary>How much of the open advances to recover. Null = all of it (up to the pay).</summary>
    [Range(0, 99999999)] public decimal? AdvanceDeducted { get; set; }
    public string PaymentMode { get; set; } = "Cash";
    public string? Note { get; set; }
}

// ------------------------------------------------------- sales report

public class WorkerSalesRowDto
{
    /// <summary>Null for bills the owner made.</summary>
    public int? WorkerId { get; set; }
    public string Name { get; set; } = "";
    public string? Designation { get; set; }
    public int Bills { get; set; }
    public int CancelledBills { get; set; }
    public decimal Sales { get; set; }
    public decimal Collected { get; set; }
    public decimal Udhaar { get; set; }
    public decimal Cash { get; set; }
    public decimal Upi { get; set; }
    public decimal Card { get; set; }
    public decimal CardInternational { get; set; }
    public decimal Other { get; set; }
    public decimal AverageBill { get; set; }
}

public class WorkerSalesReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public List<WorkerSalesRowDto> Rows { get; set; } = new();
    public decimal TotalSales { get; set; }
    public int TotalBills { get; set; }
}
