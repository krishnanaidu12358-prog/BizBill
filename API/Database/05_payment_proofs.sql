/* =====================================================================
   BizFlow - 05_payment_proofs.sql

   PaymentProofs - a customer pays by UPI, uploads the screenshot, and
   the shop owner approves it. Approval records the payment and re-issues
   the bill showing the remaining amount.

   Additive and safe to re-run.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 05_payment_proofs.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* PaymentProofs                                                       */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.PaymentProofs') IS NULL
CREATE TABLE dbo.PaymentProofs
(
    Id                INT IDENTITY(1,1) CONSTRAINT PK_PaymentProofs PRIMARY KEY,
    BusinessId        INT            NOT NULL,
    CustomerId        INT            NOT NULL,
    InvoiceId         INT            NULL,          -- the bill it is against, if any
    Amount            DECIMAL(18,2)  NOT NULL,
    Method            VARCHAR(20)    NOT NULL CONSTRAINT DF_Proofs_Method DEFAULT ('UPI'),
    ReferenceNo       NVARCHAR(80)   NULL,          -- UPI reference / UTR
    Note              NVARCHAR(250)  NULL,

    -- the uploaded screenshot
    FileName          NVARCHAR(200)  NULL,
    ContentType       VARCHAR(100)   NULL,
    FileSize          INT            NULL,
    StoredPath        NVARCHAR(400)  NULL,

    Status            VARCHAR(20)    NOT NULL CONSTRAINT DF_Proofs_Status DEFAULT ('Pending'),
    Remarks           NVARCHAR(250)  NULL,
    SubmittedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Proofs_Sent  DEFAULT (SYSUTCDATETIME()),
    ProcessedAt       DATETIME2(0)   NULL,
    ProcessedByUserId INT            NULL,
    PaymentId         INT            NULL,          -- filled in once approved

    CONSTRAINT CK_Proofs_Status CHECK (Status IN ('Pending','Approved','Rejected','Cancelled')),
    CONSTRAINT FK_Proofs_Business FOREIGN KEY (BusinessId)        REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Proofs_Customer FOREIGN KEY (CustomerId)        REFERENCES dbo.Customers(Id),
    CONSTRAINT FK_Proofs_Invoice  FOREIGN KEY (InvoiceId)         REFERENCES dbo.Invoices(Id),
    CONSTRAINT FK_Proofs_User     FOREIGN KEY (ProcessedByUserId) REFERENCES dbo.AppUsers(Id),
    CONSTRAINT FK_Proofs_Payment  FOREIGN KEY (PaymentId)         REFERENCES dbo.Payments(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Proofs_Business_Status')
    CREATE INDEX IX_Proofs_Business_Status ON dbo.PaymentProofs(BusinessId, Status, Id DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Proofs_Customer')
    CREATE INDEX IX_Proofs_Customer ON dbo.PaymentProofs(CustomerId, Id DESC);
GO

PRINT '05_payment_proofs.sql completed.';
GO
