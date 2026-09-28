/* =====================================================================
   BizFlow - 11_workers_and_cards.sql
   Workers (HRMS): workers, attendance, salary advances, payroll.
   Counter billing: which worker billed, cash tendered, card payment details
   (domestic / international, network, last 4 digits, approval code).
   Additive and safe to re-run. The API also applies this on start-up.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 11_workers_and_cards.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

IF COL_LENGTH('dbo.Businesses','UpiId') IS NULL ALTER TABLE dbo.Businesses ADD UpiId VARCHAR(100) NULL;
IF COL_LENGTH('dbo.Businesses','UpiName') IS NULL ALTER TABLE dbo.Businesses ADD UpiName NVARCHAR(100) NULL;
IF COL_LENGTH('dbo.Products','Barcode') IS NULL ALTER TABLE dbo.Products ADD Barcode VARCHAR(64) NULL;
GO

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
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Workers_Business_Mobile')
    CREATE UNIQUE INDEX IX_Workers_Business_Mobile ON dbo.Workers(BusinessId, Mobile);
GO

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
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_WorkerAttendance_Worker_Date')
    CREATE UNIQUE INDEX IX_WorkerAttendance_Worker_Date ON dbo.WorkerAttendance(WorkerId, WorkDate);
GO

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
GO

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
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_WorkerPayrolls_Worker_Month')
    CREATE UNIQUE INDEX IX_WorkerPayrolls_Worker_Month ON dbo.WorkerPayrolls(WorkerId, [Year], [Month]);
GO

IF COL_LENGTH('dbo.Invoices','BilledByWorkerId') IS NULL ALTER TABLE dbo.Invoices ADD BilledByWorkerId INT NULL;
IF COL_LENGTH('dbo.Invoices','CashTendered') IS NULL ALTER TABLE dbo.Invoices ADD CashTendered DECIMAL(18,2) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Invoices_BilledByWorker')
    CREATE INDEX IX_Invoices_BilledByWorker ON dbo.Invoices(BusinessId, BilledByWorkerId, InvoiceDate);
GO

IF COL_LENGTH('dbo.Payments','CardScope') IS NULL ALTER TABLE dbo.Payments ADD CardScope VARCHAR(20) NULL;
IF COL_LENGTH('dbo.Payments','CardNetwork') IS NULL ALTER TABLE dbo.Payments ADD CardNetwork VARCHAR(20) NULL;
IF COL_LENGTH('dbo.Payments','CardType') IS NULL ALTER TABLE dbo.Payments ADD CardType VARCHAR(20) NULL;
IF COL_LENGTH('dbo.Payments','CardLast4') IS NULL ALTER TABLE dbo.Payments ADD CardLast4 VARCHAR(4) NULL;
IF COL_LENGTH('dbo.Payments','CardApprovalCode') IS NULL ALTER TABLE dbo.Payments ADD CardApprovalCode VARCHAR(20) NULL;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AppUsers_Role'
           AND definition NOT LIKE '%Worker%')
    ALTER TABLE dbo.AppUsers DROP CONSTRAINT CK_AppUsers_Role;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AppUsers_Role')
    ALTER TABLE dbo.AppUsers ADD CONSTRAINT CK_AppUsers_Role
        CHECK (Role IN ('SuperAdmin','BusinessUser','Customer','Worker'));
GO

PRINT '11_workers_and_cards.sql completed.';
GO
