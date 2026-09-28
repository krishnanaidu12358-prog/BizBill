/* =====================================================================
   BizFlow - 04_preferences.sql
   Adds per-user theme preferences (light/dark mode and colour palette).
   Additive and safe to re-run on an existing database.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 04_preferences.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* Per-user appearance preferences                                     */
/* ------------------------------------------------------------------ */
IF COL_LENGTH('dbo.AppUsers', 'ThemeMode') IS NULL
    ALTER TABLE dbo.AppUsers
        ADD ThemeMode VARCHAR(10) NOT NULL CONSTRAINT DF_AppUsers_ThemeMode DEFAULT ('System');
GO
IF COL_LENGTH('dbo.AppUsers', 'ThemeName') IS NULL
    ALTER TABLE dbo.AppUsers
        ADD ThemeName VARCHAR(30) NOT NULL CONSTRAINT DF_AppUsers_ThemeName DEFAULT ('Classic');
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AppUsers_ThemeMode')
    ALTER TABLE dbo.AppUsers
        ADD CONSTRAINT CK_AppUsers_ThemeMode CHECK (ThemeMode IN ('System','Light','Dark'));
GO

PRINT '04_preferences.sql completed.';
GO
