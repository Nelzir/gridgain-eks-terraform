-- Q2_AdminUserPropertyView Definition
-- NOTE: GridGain 9 does not support CREATE VIEW, so this is the equivalent query
-- Run this query directly in k6 tests instead of referencing a view

-- Original SQL Server View: [admin].[Q2_AdminUserPropertyView]
-- Created: January 5, 2023
-- References: HQ 4.4.0.5400 ZAR-74, HQ 4.4.1.5683 HQ-6195, HQ 4.5.0.6094 HQ-8896

-- Full GridGain equivalent (all 4 tables):
-- Part 1: Base properties excluding feature-flagged ones
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
    AND aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')

UNION ALL

-- Part 2: AccessCommercialSalesEnablement (only if system flag enabled)
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
INNER JOIN Q2_SystemPropertyDataElements spde 
    ON spde.PropertyName = 'EnableCommercialSalesEnablement'
INNER JOIN Q2_SystemPropertyData spd 
    ON spd.PropertyID = spde.PropertyID
WHERE spd.PropertyValue = 'True'
    AND aupde.PropertyName = 'AccessCommercialSalesEnablement'

UNION ALL

-- Part 3: UserManagementUserVerification (only if email/SMS verification enabled)
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
WHERE EXISTS (
    SELECT 1 
    FROM Q2_SystemPropertyDataElements spde
    INNER JOIN Q2_SystemPropertyData spd 
        ON spd.PropertyID = spde.PropertyID
    WHERE spde.PropertyName IN ('EndUserVerificationAllowEmailTargets', 'EndUserVerificationAllowSmsTargets') 
        AND spd.PropertyValue = 'True'
)
AND aupde.PropertyName = 'UserManagementUserVerification';
