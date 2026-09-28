using System.ComponentModel.DataAnnotations;

namespace BizFlow.Api.Dtos;

// --------------------------- payment proofs ----------------------------

public class PaymentProofDto
{
    public int Id { get; set; }
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    public int CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public string CustomerMobile { get; set; } = "";
    public int? InvoiceId { get; set; }
    public string? InvoiceNumber { get; set; }
    public decimal Amount { get; set; }
    public string Method { get; set; } = "";
    public string? ReferenceNo { get; set; }
    public string? Note { get; set; }
    public bool HasScreenshot { get; set; }
    public string Status { get; set; } = "";
    public string? Remarks { get; set; }
    public DateTime SubmittedAt { get; set; }
    public DateTime? ProcessedAt { get; set; }

    /// <summary>Balance still owed on the linked bill, for context in the list.</summary>
    public decimal InvoiceBalance { get; set; }
    public decimal CustomerOutstanding { get; set; }
}

public class ProcessProofRequest
{
    public bool Approve { get; set; } = true;
    public string? Remarks { get; set; }
    /// <summary>Send the customer the updated bill on WhatsApp after approving.</summary>
    public bool SendWhatsApp { get; set; } = true;
}

/// <summary>Result of approving a proof: the payment plus the re-issued bill.</summary>
public class ProofApprovalResultDto
{
    public PaymentProofDto Proof { get; set; } = new();
    public PaymentDto? Payment { get; set; }
    public InvoiceDto? ReIssuedInvoice { get; set; }
    public decimal RemainingOnInvoice { get; set; }
    public decimal CustomerOutstanding { get; set; }
    public string? WhatsAppLink { get; set; }
}

// ----------------------------- statement -------------------------------

public class StatementLineDto
{
    public int InvoiceId { get; set; }
    public string InvoiceNumber { get; set; } = "";
    public DateTime InvoiceDate { get; set; }
    public decimal GrandTotal { get; set; }
    public decimal PaidAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public string Status { get; set; } = "";
    public int DaysOld { get; set; }
}

/// <summary>A customer's running account with one shop: every unpaid bill, oldest first.</summary>
public class StatementDto
{
    public int CustomerId { get; set; }
    public string CustomerName { get; set; } = "";
    public string CustomerMobile { get; set; } = "";
    public int BusinessId { get; set; }
    public string BusinessName { get; set; } = "";
    public List<StatementLineDto> UnpaidBills { get; set; } = new();
    public decimal TotalBilled { get; set; }
    public decimal TotalPaid { get; set; }
    public decimal TotalDue { get; set; }
    public decimal CreditAvailable { get; set; }
    public int OldestBillDays { get; set; }
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public string? WhatsAppLink { get; set; }
}
