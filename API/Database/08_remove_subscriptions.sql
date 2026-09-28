/* =====================================================================
   BizFlow - 08_remove_subscriptions.sql
   Subscription plans have been removed from the app. This drops the two
   subscription tables from an existing database. Safe to re-run: it does
   nothing once the tables are gone.
   Run : sqlcmd -S DESKTOP-BV2BD6K -E -C -I -d BizFlowDb -i 08_remove_subscriptions.sql
   ===================================================================== */

USE BizFlowDb;
GO
SET NOCOUNT ON;
GO

/* BusinessSubscriptions first - it holds the foreign key to SubscriptionPlans. */
IF OBJECT_ID('dbo.BusinessSubscriptions') IS NOT NULL
    DROP TABLE dbo.BusinessSubscriptions;
GO

IF OBJECT_ID('dbo.SubscriptionPlans') IS NOT NULL
    DROP TABLE dbo.SubscriptionPlans;
GO

PRINT '08_remove_subscriptions.sql completed.';
GO
