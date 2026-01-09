-- Q2_AdminUserPropertyView Definition
-- NOTE: GridGain 9 does not support CREATE VIEW, so this is the equivalent query
-- Run this query directly in k6 tests instead of referencing a view

-- Original SQL Server View (for reference):
-- CREATE VIEW [admin].[Q2_AdminUserPropertyView] AS
--   SELECT ... FROM admin.Q2_AdminUserPropertyData aupd
--   INNER JOIN admin.Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
--   WHERE aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')
--   UNION ALL ... (conditional sections based on system property flags)

-- Simplified GridGain equivalent (main query path):
SELECT 
    aupd.UserPropertyDataID,
    aupd.GroupID,
    aupd.FIID,
    aupd.UISourceID,
    aupd.UserID,
    aupd.PropertyID,
    aupde.PropertyName,
    aupde.PropertyLongName,
    aupde.PropertyDataType,
    aupd.PropertyValue,
    aupd.Weight,
    aupde.IsGroupProperty,
    aupde.IsUserProperty
FROM Q2_AdminUserPropertyData aupd
INNER JOIN Q2_AdminUserPropertyDataElements aupde 
    ON aupd.PropertyID = aupde.PropertyID
WHERE aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification');
