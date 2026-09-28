using Microsoft.EntityFrameworkCore;

namespace BizFlow.Api.Data;

/// <summary>
/// Tables and columns added after the first release. Every statement is safe to
/// run again, so the API applies them on each start and an older database keeps
/// working. The same SQL is in Database/11_workers_and_cards.sql.
/// </summary>
public static class SchemaUpgrade
{
    public static readonly string[] Statements =
    {
        // ---- columns from earlier releases (09 / 10)
        """
        IF COL_LENGTH('dbo.Businesses','UpiId') IS NULL ALTER TABLE dbo.Businesses ADD UpiId VARCHAR(100) NULL;
        IF COL_LENGTH('dbo.Businesses','UpiName') IS NULL ALTER TABLE dbo.Businesses ADD UpiName NVARCHAR(100) NULL;
        IF COL_LENGTH('dbo.Products','Barcode') IS NULL ALTER TABLE dbo.Products ADD Barcode VARCHAR(64) NULL;
        """,

        // ---- workers (HRMS)
        """
        IF OBJECT_ID('dbo.Workers','U') IS NULL
        CREATE TABLE dbo.Workers
        (
            Id            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Workers PRIMARY KEY,
            BusinessId    INT            NOT NULL CONSTRAINT FK_Workers_Businesses REFERENCES dbo.Businesses(Id),
            UserId        INT            NULL     CONSTRAINT FK_Workers_AppUsers   REFERENCES dbo.AppUsers(Id),
            Name          NVARCHAR(120)  NOT NULL,
            Mobile        VARCHAR(15)    NOT NULL,
            Designation   NVARCHAR(60)   NULL,
            SalaryType    VARCHAR(10)    NOT NULL CONSTRAINT DF_Workers_SalaryType DEFAULT('Monthly'),
            SalaryAmount  DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Workers_Salary DEFAULT(0),
            JoinDate      DATE           NOT NULL,
            Address       NVARCHAR(250)  NULL,
            CanGiveUdhaar BIT            NOT NULL CONSTRAINT DF_Workers_Udhaar DEFAULT(0),
            IsActive      BIT            NOT NULL CONSTRAINT DF_Workers_Active DEFAULT(1),
            CreatedAt     DATETIME2      NOT NULL CONSTRAINT DF_Workers_Created DEFAULT(SYSUTCDATETIME())
        );
        """,
        """
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Workers_Business_Mobile')
            CREATE UNIQUE INDEX IX_Workers_Business_Mobile ON dbo.Workers(BusinessId, Mobile);
        """,
        """
        IF OBJECT_ID('dbo.WorkerAttendance','U') IS NULL
        CREATE TABLE dbo.WorkerAttendance
        (
            Id             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WorkerAttendance PRIMARY KEY,
            BusinessId     INT           NOT NULL,
            WorkerId       INT           NOT NULL CONSTRAINT FK_WorkerAttendance_Workers REFERENCES dbo.Workers(Id),
            WorkDate       DATE          NOT NULL,
            Status         VARCHAR(10)   NOT NULL,
            CheckIn        DATETIME2     NULL,
            CheckOut       DATETIME2     NULL,
            Note           NVARCHAR(200) NULL,
            MarkedByUserId INT           NULL,
            UpdatedAt      DATETIME2     NOT NULL CONSTRAINT DF_WorkerAttendance_Updated DEFAULT(SYSUTCDATETIME())
        );
        """,
        """
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_WorkerAttendance_Worker_Date')
            CREATE UNIQUE INDEX IX_WorkerAttendance_Worker_Date ON dbo.WorkerAttendance(WorkerId, WorkDate);
        """,
        """
        IF OBJECT_ID('dbo.WorkerAdvances','U') IS NULL
        CREATE TABLE dbo.WorkerAdvances
        (
            Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WorkerAdvances PRIMARY KEY,
            BusinessId      INT           NOT NULL,
            WorkerId        INT           NOT NULL CONSTRAINT FK_WorkerAdvances_Workers REFERENCES dbo.Workers(Id),
            AdvanceDate     DATETIME2     NOT NULL,
            Amount          DECIMAL(18,2) NOT NULL,
            PaymentMode     VARCHAR(20)   NOT NULL CONSTRAINT DF_WorkerAdvances_Mode DEFAULT('Cash'),
            Note            NVARCHAR(200) NULL,
            PayrollId       INT           NULL,
            ExpenseId       INT           NULL,
            IsCancelled     BIT           NOT NULL CONSTRAINT DF_WorkerAdvances_Cancelled DEFAULT(0),
            CreatedByUserId INT           NULL,
            CreatedAt       DATETIME2     NOT NULL CONSTRAINT DF_WorkerAdvances_Created DEFAULT(SYSUTCDATETIME())
        );
        """,
        """
        IF OBJECT_ID('dbo.WorkerPayrolls','U') IS NULL
        CREATE TABLE dbo.WorkerPayrolls
        (
            Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WorkerPayrolls PRIMARY KEY,
            BusinessId      INT           NOT NULL,
            WorkerId        INT           NOT NULL CONSTRAINT FK_WorkerPayrolls_Workers REFERENCES dbo.Workers(Id),
            [Year]          INT           NOT NULL,
            [Month]         INT           NOT NULL,
            SalaryType      VARCHAR(10)   NOT NULL,
            SalaryAmount    DECIMAL(18,2) NOT NULL,
            DaysInMonth     INT           NOT NULL,
            PresentDays     DECIMAL(6,2)  NOT NULL,
            HalfDays        DECIMAL(6,2)  NOT NULL,
            LeaveDays       DECIMAL(6,2)  NOT NULL,
            AbsentDays      DECIMAL(6,2)  NOT NULL,
            PayableDays     DECIMAL(6,2)  NOT NULL,
            GrossPay        DECIMAL(18,2) NOT NULL,
            Bonus           DECIMAL(18,2) NOT NULL,
            OtherDeductions DECIMAL(18,2) NOT NULL,
            AdvanceDeducted DECIMAL(18,2) NOT NULL,
            NetPay          DECIMAL(18,2) NOT NULL,
            PaymentMode     VARCHAR(20)   NOT NULL,
            Note            NVARCHAR(200) NULL,
            PaidOn          DATETIME2     NOT NULL,
            ExpenseId       INT           NULL,
            CreatedByUserId INT           NULL
        );
        """,
        """
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_WorkerPayrolls_Worker_Month')
            CREATE UNIQUE INDEX IX_WorkerPayrolls_Worker_Month ON dbo.WorkerPayrolls(WorkerId, [Year], [Month]);
        """,

        // ---- who billed it, cash handed over
        """
        IF COL_LENGTH('dbo.Invoices','BilledByWorkerId') IS NULL ALTER TABLE dbo.Invoices ADD BilledByWorkerId INT NULL;
        IF COL_LENGTH('dbo.Invoices','CashTendered') IS NULL ALTER TABLE dbo.Invoices ADD CashTendered DECIMAL(18,2) NULL;
        """,
        """
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Invoices_BilledByWorker')
            CREATE INDEX IX_Invoices_BilledByWorker ON dbo.Invoices(BusinessId, BilledByWorkerId, InvoiceDate);
        """,

        // ---- card payments on the counter card machine
        """
        IF COL_LENGTH('dbo.Payments','CardScope') IS NULL ALTER TABLE dbo.Payments ADD CardScope VARCHAR(20) NULL;
        IF COL_LENGTH('dbo.Payments','CardNetwork') IS NULL ALTER TABLE dbo.Payments ADD CardNetwork VARCHAR(20) NULL;
        IF COL_LENGTH('dbo.Payments','CardType') IS NULL ALTER TABLE dbo.Payments ADD CardType VARCHAR(20) NULL;
        IF COL_LENGTH('dbo.Payments','CardLast4') IS NULL ALTER TABLE dbo.Payments ADD CardLast4 VARCHAR(4) NULL;
        IF COL_LENGTH('dbo.Payments','CardApprovalCode') IS NULL ALTER TABLE dbo.Payments ADD CardApprovalCode VARCHAR(20) NULL;
        """,

        // The original schema only allowed three roles; add Worker.
        """
        IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AppUsers_Role'
                   AND definition NOT LIKE '%Worker%')
            ALTER TABLE dbo.AppUsers DROP CONSTRAINT CK_AppUsers_Role;
        IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AppUsers_Role')
            ALTER TABLE dbo.AppUsers ADD CONSTRAINT CK_AppUsers_Role
                CHECK (Role IN ('SuperAdmin','BusinessUser','Customer','Worker'));
        """
    };

    /// <summary>Shop profile and bill design (12_shop_branding.sql).</summary>
    public static readonly string[] BrandingStatements =
    {
        """
        IF COL_LENGTH('dbo.Businesses','BusinessType') IS NULL
            ALTER TABLE dbo.Businesses ADD BusinessType NVARCHAR(30) NOT NULL CONSTRAINT DF_Businesses_Type DEFAULT('Retail');
        IF COL_LENGTH('dbo.Businesses','Tagline') IS NULL ALTER TABLE dbo.Businesses ADD Tagline NVARCHAR(150) NULL;
        IF COL_LENGTH('dbo.Businesses','LogoPath') IS NULL ALTER TABLE dbo.Businesses ADD LogoPath NVARCHAR(400) NULL;
        IF COL_LENGTH('dbo.Businesses','LogoContentType') IS NULL ALTER TABLE dbo.Businesses ADD LogoContentType VARCHAR(100) NULL;
        IF COL_LENGTH('dbo.Businesses','SignaturePath') IS NULL ALTER TABLE dbo.Businesses ADD SignaturePath NVARCHAR(400) NULL;
        IF COL_LENGTH('dbo.Businesses','SignatureContentType') IS NULL ALTER TABLE dbo.Businesses ADD SignatureContentType VARCHAR(100) NULL;
        IF COL_LENGTH('dbo.Businesses','SignatoryName') IS NULL ALTER TABLE dbo.Businesses ADD SignatoryName NVARCHAR(120) NULL;
        IF COL_LENGTH('dbo.Businesses','InvoiceTerms') IS NULL ALTER TABLE dbo.Businesses ADD InvoiceTerms NVARCHAR(1000) NULL;
        IF COL_LENGTH('dbo.Businesses','ReceiptFooter') IS NULL ALTER TABLE dbo.Businesses ADD ReceiptFooter NVARCHAR(200) NULL;
        IF COL_LENGTH('dbo.Businesses','ShowLogoOnReceipt') IS NULL
            ALTER TABLE dbo.Businesses ADD ShowLogoOnReceipt BIT NOT NULL CONSTRAINT DF_Businesses_LogoReceipt DEFAULT(1);
        IF COL_LENGTH('dbo.Businesses','ShowSignature') IS NULL
            ALTER TABLE dbo.Businesses ADD ShowSignature BIT NOT NULL CONSTRAINT DF_Businesses_ShowSig DEFAULT(1);
        IF COL_LENGTH('dbo.Businesses','BrandingUpdatedAt') IS NULL ALTER TABLE dbo.Businesses ADD BrandingUpdatedAt DATETIME2 NULL;
        """
    };

    public static async Task ApplyAsync(AppDbContext db, ILogger log)
    {
        foreach (var sql in Statements.Concat(BrandingStatements))
        {
            try
            {
                await db.Database.ExecuteSqlRawAsync(sql);
            }
            catch (Exception ex)
            {
                log.LogWarning(ex, "Schema upgrade step failed. Run API/Database/11_workers_and_cards.sql by hand.");
            }
        }
    }
}
