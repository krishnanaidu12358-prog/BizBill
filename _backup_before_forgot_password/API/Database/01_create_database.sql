/* =====================================================================
   BizFlow - 01_create_database.sql
   Creates the local database and a dedicated SQL login for the API.
   Server : DESKTOP-BV2BD6K   (local SQL Server 2022 Express)
   Run    : sqlcmd -S DESKTOP-BV2BD6K -E -C -i 01_create_database.sql
   ===================================================================== */

IF DB_ID('BizFlowDb') IS NULL
BEGIN
    PRINT 'Creating database BizFlowDb ...';
    CREATE DATABASE BizFlowDb;
END
ELSE
    PRINT 'Database BizFlowDb already exists - skipping create.';
GO

ALTER DATABASE BizFlowDb SET RECOVERY SIMPLE;
GO

/* ---------------------------------------------------------------------
   Dedicated application login.
   The API uses this instead of 'sa' so the sa password never leaves SSMS.
   To use 'sa' instead, just change the connection string in
   API/BizFlow.Api/appsettings.json.
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = 'bizflow_app')
BEGIN
    PRINT 'Creating login bizflow_app ...';
    CREATE LOGIN bizflow_app
        WITH PASSWORD = 'BizFlow@2026#Sql',
             CHECK_POLICY = OFF,
             DEFAULT_DATABASE = BizFlowDb;
END
ELSE
    PRINT 'Login bizflow_app already exists - skipping create.';
GO

USE BizFlowDb;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'bizflow_app')
BEGIN
    CREATE USER bizflow_app FOR LOGIN bizflow_app;
    ALTER ROLE db_owner ADD MEMBER bizflow_app;
    PRINT 'Mapped bizflow_app to BizFlowDb as db_owner.';
END
GO

PRINT '01_create_database.sql completed.';
GO
