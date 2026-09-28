/* =====================================================================
   BizFlow - 02_schema.sql
   All tables, keys and indexes. Safe to re-run (IF NOT EXISTS guards).
   Run : sqlcmd -S 192.168.29.53,50491 -U sa -C -I -d BizflowDb -i 02_schema.sql   (asks for the sa password)
   ===================================================================== */

USE BizflowDb;
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* 1. Businesses  (a tenant / shop owned by one BusinessUser)          */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Businesses') IS NULL
CREATE TABLE dbo.Businesses
(
    Id             INT IDENTITY(1,1) CONSTRAINT PK_Businesses PRIMARY KEY,
    Name           NVARCHAR(150)  NOT NULL,
    OwnerName      NVARCHAR(120)  NULL,
    Mobile         VARCHAR(15)    NOT NULL,
    Email          NVARCHAR(150)  NULL,
    AddressLine    NVARCHAR(250)  NULL,
    City           NVARCHAR(80)   NULL,
    [State]        NVARCHAR(80)   NULL,
    Pincode        VARCHAR(10)    NULL,
    GstNumber      VARCHAR(20)    NULL,
    InvoicePrefix  VARCHAR(10)    NOT NULL CONSTRAINT DF_Businesses_Prefix  DEFAULT ('INV'),
    Currency       VARCHAR(5)     NOT NULL CONSTRAINT DF_Businesses_Curr    DEFAULT ('INR'),
    IsActive       BIT            NOT NULL CONSTRAINT DF_Businesses_Active  DEFAULT (1),
    CreatedAt      DATETIME2(0)   NOT NULL CONSTRAINT DF_Businesses_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_Businesses_Mobile UNIQUE (Mobile)
);
GO

/* ------------------------------------------------------------------ */
/* 2. AppUsers  (login identity = Mobile, for all three roles)         */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.AppUsers') IS NULL
CREATE TABLE dbo.AppUsers
(
    Id           INT IDENTITY(1,1) CONSTRAINT PK_AppUsers PRIMARY KEY,
    BusinessId   INT            NULL,          -- NULL for SuperAdmin and Customer
    Mobile       VARCHAR(15)    NOT NULL,
    FullName     NVARCHAR(120)  NOT NULL,
    Email        NVARCHAR(150)  NULL,
    PasswordHash NVARCHAR(200)  NOT NULL,
    Role         VARCHAR(20)    NOT NULL,
    IsActive     BIT            NOT NULL CONSTRAINT DF_AppUsers_Active  DEFAULT (1),
    LastLoginAt  DATETIME2(0)   NULL,
    CreatedAt    DATETIME2(0)   NOT NULL CONSTRAINT DF_AppUsers_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_AppUsers_Mobile UNIQUE (Mobile),
    CONSTRAINT CK_AppUsers_Role CHECK (Role IN ('SuperAdmin','BusinessUser','Customer')),
    CONSTRAINT FK_AppUsers_Business FOREIGN KEY (BusinessId) REFERENCES dbo.Businesses(Id)
);
GO

/* ------------------------------------------------------------------ */
/* 3. RefreshTokens                                                    */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.RefreshTokens') IS NULL
CREATE TABLE dbo.RefreshTokens
(
    Id        INT IDENTITY(1,1) CONSTRAINT PK_RefreshTokens PRIMARY KEY,
    UserId    INT           NOT NULL,
    Token     VARCHAR(100)  NOT NULL,
    ExpiresAt DATETIME2(0)  NOT NULL,
    RevokedAt DATETIME2(0)  NULL,
    CreatedAt DATETIME2(0)  NOT NULL CONSTRAINT DF_RefreshTokens_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_RefreshTokens_Token UNIQUE (Token),
    CONSTRAINT FK_RefreshTokens_User FOREIGN KEY (UserId) REFERENCES dbo.AppUsers(Id)
);
GO

/* ------------------------------------------------------------------ */
/* 4. Customers  (one row per business the person buys from)           */
/*    UserId links to the single AppUsers row for that mobile number.  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Customers') IS NULL
CREATE TABLE dbo.Customers
(
    Id                 INT IDENTITY(1,1) CONSTRAINT PK_Customers PRIMARY KEY,
    BusinessId         INT            NOT NULL,
    UserId             INT            NULL,
    Name               NVARCHAR(120)  NOT NULL,
    Mobile             VARCHAR(15)    NOT NULL,
    Email              NVARCHAR(150)  NULL,
    Address            NVARCHAR(250)  NULL,
    IsTrusted          BIT            NOT NULL CONSTRAINT DF_Customers_Trusted DEFAULT (0),
    CreditLimit        DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Customers_Limit   DEFAULT (0),
    OutstandingBalance DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Customers_Out     DEFAULT (0),
    CreditBalance      DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Customers_Credit  DEFAULT (0),
    IsActive           BIT            NOT NULL CONSTRAINT DF_Customers_Active  DEFAULT (1),
    CreatedAt          DATETIME2(0)   NOT NULL CONSTRAINT DF_Customers_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_Customers_Business_Mobile UNIQUE (BusinessId, Mobile),
    CONSTRAINT FK_Customers_Business FOREIGN KEY (BusinessId) REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Customers_User     FOREIGN KEY (UserId)     REFERENCES dbo.AppUsers(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Customers_UserId')
    CREATE INDEX IX_Customers_UserId ON dbo.Customers(UserId);
GO

/* ------------------------------------------------------------------ */
/* 5. Products                                                         */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Products') IS NULL
CREATE TABLE dbo.Products
(
    Id            INT IDENTITY(1,1) CONSTRAINT PK_Products PRIMARY KEY,
    BusinessId    INT            NOT NULL,
    Name          NVARCHAR(150)  NOT NULL,
    Sku           VARCHAR(50)    NULL,
    Unit          NVARCHAR(20)   NOT NULL CONSTRAINT DF_Products_Unit    DEFAULT ('PCS'),
    SellingPrice  DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Products_Sell    DEFAULT (0),
    PurchasePrice DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Products_Buy     DEFAULT (0),
    TaxPercent    DECIMAL(5,2)   NOT NULL CONSTRAINT DF_Products_Tax     DEFAULT (0),
    StockQty      DECIMAL(18,3)  NOT NULL CONSTRAINT DF_Products_Stock   DEFAULT (0),
    MinStockQty   DECIMAL(18,3)  NOT NULL CONSTRAINT DF_Products_Min     DEFAULT (0),
    IsActive      BIT            NOT NULL CONSTRAINT DF_Products_Active  DEFAULT (1),
    CreatedAt     DATETIME2(0)   NOT NULL CONSTRAINT DF_Products_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Products_Business FOREIGN KEY (BusinessId) REFERENCES dbo.Businesses(Id)
);
GO
SET QUOTED_IDENTIFIER ON;   -- required for filtered indexes
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Products_Business_Sku')
    CREATE UNIQUE INDEX UX_Products_Business_Sku
        ON dbo.Products(BusinessId, Sku) WHERE Sku IS NOT NULL;
GO

/* ------------------------------------------------------------------ */
/* 6. Invoices (bills) + items                                         */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Invoices') IS NULL
CREATE TABLE dbo.Invoices
(
    Id              INT IDENTITY(1,1) CONSTRAINT PK_Invoices PRIMARY KEY,
    BusinessId      INT            NOT NULL,
    CustomerId      INT            NOT NULL,
    InvoiceNumber   VARCHAR(30)    NOT NULL,
    InvoiceDate     DATETIME2(0)   NOT NULL CONSTRAINT DF_Invoices_Date    DEFAULT (SYSUTCDATETIME()),
    SubTotal        DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Invoices_Sub     DEFAULT (0),
    DiscountAmount  DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Invoices_Disc    DEFAULT (0),
    TaxAmount       DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Invoices_Tax     DEFAULT (0),
    GrandTotal      DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Invoices_Total   DEFAULT (0),
    PaidAmount      DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Invoices_Paid    DEFAULT (0),
    BalanceAmount   DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Invoices_Bal     DEFAULT (0),
    PaymentMode     VARCHAR(20)    NOT NULL CONSTRAINT DF_Invoices_Mode    DEFAULT ('Cash'),
    Status          VARCHAR(20)    NOT NULL CONSTRAINT DF_Invoices_Stat    DEFAULT ('Confirmed'),
    Notes           NVARCHAR(500)  NULL,
    CreatedByUserId INT            NULL,
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Invoices_Created DEFAULT (SYSUTCDATETIME()),
    CancelledAt     DATETIME2(0)   NULL,
    CONSTRAINT UQ_Invoices_Business_Number UNIQUE (BusinessId, InvoiceNumber),
    CONSTRAINT CK_Invoices_Status CHECK (Status IN ('Draft','Confirmed','PartiallyPaid','Paid','Credit','Cancelled')),
    CONSTRAINT CK_Invoices_Mode   CHECK (PaymentMode IN ('Cash','UPI','Card','BankTransfer','Credit','Split')),
    CONSTRAINT FK_Invoices_Business FOREIGN KEY (BusinessId)      REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Invoices_Customer FOREIGN KEY (CustomerId)      REFERENCES dbo.Customers(Id),
    CONSTRAINT FK_Invoices_User     FOREIGN KEY (CreatedByUserId) REFERENCES dbo.AppUsers(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Invoices_Customer')
    CREATE INDEX IX_Invoices_Customer ON dbo.Invoices(CustomerId, InvoiceDate DESC);
GO

IF OBJECT_ID('dbo.InvoiceItems') IS NULL
CREATE TABLE dbo.InvoiceItems
(
    Id             INT IDENTITY(1,1) CONSTRAINT PK_InvoiceItems PRIMARY KEY,
    InvoiceId      INT            NOT NULL,
    ProductId      INT            NULL,
    ProductName    NVARCHAR(150)  NOT NULL,
    Quantity       DECIMAL(18,3)  NOT NULL,
    UnitPrice      DECIMAL(18,2)  NOT NULL,
    DiscountAmount DECIMAL(18,2)  NOT NULL CONSTRAINT DF_InvoiceItems_Disc DEFAULT (0),
    TaxPercent     DECIMAL(5,2)   NOT NULL CONSTRAINT DF_InvoiceItems_Tax  DEFAULT (0),
    TaxAmount      DECIMAL(18,2)  NOT NULL CONSTRAINT DF_InvoiceItems_TaxA DEFAULT (0),
    LineTotal      DECIMAL(18,2)  NOT NULL,
    CONSTRAINT FK_InvoiceItems_Invoice FOREIGN KEY (InvoiceId) REFERENCES dbo.Invoices(Id) ON DELETE CASCADE,
    CONSTRAINT FK_InvoiceItems_Product FOREIGN KEY (ProductId) REFERENCES dbo.Products(Id)
);
GO

/* ------------------------------------------------------------------ */
/* 7. Payments (customer pays the business)                            */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Payments') IS NULL
CREATE TABLE dbo.Payments
(
    Id              INT IDENTITY(1,1) CONSTRAINT PK_Payments PRIMARY KEY,
    BusinessId      INT            NOT NULL,
    CustomerId      INT            NOT NULL,
    InvoiceId       INT            NULL,
    ReceiptNumber   VARCHAR(30)    NOT NULL,
    Amount          DECIMAL(18,2)  NOT NULL,
    Mode            VARCHAR(20)    NOT NULL CONSTRAINT DF_Payments_Mode    DEFAULT ('Cash'),
    ReferenceNo     NVARCHAR(80)   NULL,
    Note            NVARCHAR(250)  NULL,
    PaidOn          DATETIME2(0)   NOT NULL CONSTRAINT DF_Payments_On      DEFAULT (SYSUTCDATETIME()),
    CreatedByUserId INT            NULL,
    CreatedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_Payments_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_Payments_Business_Receipt UNIQUE (BusinessId, ReceiptNumber),
    CONSTRAINT FK_Payments_Business FOREIGN KEY (BusinessId) REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Payments_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id),
    CONSTRAINT FK_Payments_Invoice  FOREIGN KEY (InvoiceId)  REFERENCES dbo.Invoices(Id)
);
GO

/* --------------------------------------------------------------------- */
/* 8. CreditGrants - Udhaar / store credit issued to a trusted customer   */
/* --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.CreditGrants') IS NULL
CREATE TABLE dbo.CreditGrants
(
    Id             INT IDENTITY(1,1) CONSTRAINT PK_CreditGrants PRIMARY KEY,
    BusinessId     INT            NOT NULL,
    CustomerId     INT            NOT NULL,
    CreditCode     VARCHAR(20)    NOT NULL,
    Amount         DECIMAL(18,2)  NOT NULL,
    ClaimedAmount  DECIMAL(18,2)  NOT NULL CONSTRAINT DF_CreditGrants_Claimed DEFAULT (0),
    BalanceAmount  DECIMAL(18,2)  NOT NULL,
    Reason         NVARCHAR(250)  NULL,
    ExpiryDate     DATE           NULL,
    Status         VARCHAR(20)    NOT NULL CONSTRAINT DF_CreditGrants_Status  DEFAULT ('Active'),
    IssuedByUserId INT            NULL,
    CreatedAt      DATETIME2(0)   NOT NULL CONSTRAINT DF_CreditGrants_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_CreditGrants_Code UNIQUE (CreditCode),
    CONSTRAINT CK_CreditGrants_Status CHECK (Status IN ('Active','PartiallyClaimed','Claimed','Expired','Cancelled')),
    CONSTRAINT FK_CreditGrants_Business FOREIGN KEY (BusinessId)     REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_CreditGrants_Customer FOREIGN KEY (CustomerId)     REFERENCES dbo.Customers(Id),
    CONSTRAINT FK_CreditGrants_User     FOREIGN KEY (IssuedByUserId) REFERENCES dbo.AppUsers(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CreditGrants_Customer')
    CREATE INDEX IX_CreditGrants_Customer ON dbo.CreditGrants(CustomerId, Status);
GO

/* --------------------------------------------------------------------- */
/* 9. CreditClaims - customer asks to use credit, owner approves          */
/* --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.CreditClaims') IS NULL
CREATE TABLE dbo.CreditClaims
(
    Id                INT IDENTITY(1,1) CONSTRAINT PK_CreditClaims PRIMARY KEY,
    CreditGrantId     INT            NOT NULL,
    BusinessId        INT            NOT NULL,
    CustomerId        INT            NOT NULL,
    Amount            DECIMAL(18,2)  NOT NULL,
    Status            VARCHAR(20)    NOT NULL CONSTRAINT DF_CreditClaims_Status DEFAULT ('Pending'),
    Remarks           NVARCHAR(250)  NULL,
    RequestedAt       DATETIME2(0)   NOT NULL CONSTRAINT DF_CreditClaims_Req    DEFAULT (SYSUTCDATETIME()),
    ProcessedAt       DATETIME2(0)   NULL,
    ProcessedByUserId INT            NULL,
    InvoiceId         INT            NULL,
    CONSTRAINT CK_CreditClaims_Status CHECK (Status IN ('Pending','Approved','Rejected','Cancelled')),
    CONSTRAINT FK_CreditClaims_Grant    FOREIGN KEY (CreditGrantId) REFERENCES dbo.CreditGrants(Id),
    CONSTRAINT FK_CreditClaims_Business FOREIGN KEY (BusinessId)    REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_CreditClaims_Customer FOREIGN KEY (CustomerId)    REFERENCES dbo.Customers(Id),
    CONSTRAINT FK_CreditClaims_Invoice  FOREIGN KEY (InvoiceId)     REFERENCES dbo.Invoices(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CreditClaims_Business')
    CREATE INDEX IX_CreditClaims_Business ON dbo.CreditClaims(BusinessId, Status);
GO

/* ------------------------------------------------------------------ */
/* 10. LedgerEntries - running customer account statement              */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.LedgerEntries') IS NULL
CREATE TABLE dbo.LedgerEntries
(
    Id             INT IDENTITY(1,1) CONSTRAINT PK_LedgerEntries PRIMARY KEY,
    BusinessId     INT            NOT NULL,
    CustomerId     INT            NOT NULL,
    EntryDate      DATETIME2(0)   NOT NULL CONSTRAINT DF_Ledger_Date   DEFAULT (SYSUTCDATETIME()),
    RefType        VARCHAR(20)    NOT NULL,
    RefId          INT            NULL,
    Description    NVARCHAR(250)  NOT NULL,
    Debit          DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Ledger_Debit  DEFAULT (0),
    Credit         DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Ledger_Credit DEFAULT (0),
    RunningBalance DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Ledger_Run    DEFAULT (0),
    CONSTRAINT CK_Ledger_RefType CHECK (RefType IN ('Opening','Invoice','Payment','CreditGrant','CreditClaim','Adjustment')),
    CONSTRAINT FK_Ledger_Business FOREIGN KEY (BusinessId) REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Ledger_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Ledger_Customer')
    CREATE INDEX IX_Ledger_Customer ON dbo.LedgerEntries(CustomerId, Id);
GO

/* ------------------------------------------------------------------ */
/* 11. WhatsAppMessages - outbox for every bill / credit notification  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.WhatsAppMessages') IS NULL
CREATE TABLE dbo.WhatsAppMessages
(
    Id                INT IDENTITY(1,1) CONSTRAINT PK_WhatsAppMessages PRIMARY KEY,
    BusinessId        INT             NULL,
    CustomerId        INT             NULL,
    ToMobile          VARCHAR(15)     NOT NULL,
    Template          VARCHAR(40)     NOT NULL,
    Body              NVARCHAR(MAX)   NOT NULL,
    DeepLink          NVARCHAR(1000)  NULL,
    Status            VARCHAR(20)     NOT NULL CONSTRAINT DF_Wa_Status  DEFAULT ('Queued'),
    Provider          VARCHAR(30)     NULL,
    ProviderMessageId NVARCHAR(120)   NULL,
    ErrorMessage      NVARCHAR(500)   NULL,
    CreatedAt         DATETIME2(0)    NOT NULL CONSTRAINT DF_Wa_Created DEFAULT (SYSUTCDATETIME()),
    SentAt            DATETIME2(0)    NULL,
    CONSTRAINT CK_Wa_Status CHECK (Status IN ('Queued','Sent','Failed')),
    CONSTRAINT FK_Wa_Business FOREIGN KEY (BusinessId) REFERENCES dbo.Businesses(Id),
    CONSTRAINT FK_Wa_Customer FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Wa_Customer')
    CREATE INDEX IX_Wa_Customer ON dbo.WhatsAppMessages(CustomerId, Id DESC);
GO

/* ------------------------------------------------------------------ */
/* 12. AuditLogs                                                       */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.AuditLogs') IS NULL
CREATE TABLE dbo.AuditLogs
(
    Id         INT IDENTITY(1,1) CONSTRAINT PK_AuditLogs PRIMARY KEY,
    BusinessId INT            NULL,
    UserId     INT            NULL,
    [Action]   VARCHAR(60)    NOT NULL,
    EntityName VARCHAR(60)    NULL,
    EntityId   INT            NULL,
    Details    NVARCHAR(MAX)  NULL,
    IpAddress  VARCHAR(45)    NULL,
    CreatedAt  DATETIME2(0)   NOT NULL CONSTRAINT DF_Audit_Created DEFAULT (SYSUTCDATETIME())
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Audit_Created')
    CREATE INDEX IX_Audit_Created ON dbo.AuditLogs(CreatedAt DESC);
GO

PRINT '02_schema.sql completed - all tables ready.';
GO
