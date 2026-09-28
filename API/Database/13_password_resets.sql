/* =====================================================================
   BizFlow - 13_password_resets.sql
   "Forgot password" codes for shop owners and customers. Only a hash of each
   6-digit code is stored; a code lasts 10 minutes and dies after 5 wrong tries.
   The API also creates this table by itself on start, so running this by hand
   is optional.
   Run : sqlcmd -S 192.168.29.53,50491 -U sa -C -I -d BizflowDb -i 13_password_resets.sql   (asks for the sa password)
   ===================================================================== */

USE BizflowDb;
GO

IF OBJECT_ID('dbo.PasswordResets','U') IS NULL
BEGIN
    CREATE TABLE dbo.PasswordResets
    (
        Id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PasswordResets PRIMARY KEY,
        UserId     INT          NOT NULL CONSTRAINT FK_PasswordResets_AppUsers REFERENCES dbo.AppUsers(Id),
        CodeHash   VARCHAR(100) NOT NULL,
        ExpiresAt  DATETIME2    NOT NULL,
        Attempts   INT          NOT NULL CONSTRAINT DF_PasswordResets_Attempts DEFAULT(0),
        UsedAt     DATETIME2    NULL,
        RequestIp  VARCHAR(64)  NULL,
        CreatedAt  DATETIME2    NOT NULL CONSTRAINT DF_PasswordResets_Created DEFAULT(SYSUTCDATETIME())
    );
    PRINT 'Created dbo.PasswordResets.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PasswordResets_UserId')
    CREATE INDEX IX_PasswordResets_UserId ON dbo.PasswordResets(UserId);
GO

PRINT '13_password_resets.sql completed.';
GO
