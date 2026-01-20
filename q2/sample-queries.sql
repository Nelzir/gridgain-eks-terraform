-- Sample Queries for Q2_AdminUserPropertyView Access Pattern
-- These match the common access patterns from SQL Server
-- Since GridGain 9 doesn't support views, we use the full query as a subquery

-- =============================================================================
-- Query 1: Filter by GroupID=7, FIID=1, UISourceID=8, UserID=440, exclude PropertyID=84
-- =============================================================================
SELECT * FROM (
    -- Part 1: Base properties excluding feature-flagged ones
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde 
        ON aupd.PropertyID = aupde.PropertyID
        AND aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')
    UNION ALL
    -- Part 2: AccessCommercialSalesEnablement (only if system flag enabled)
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
    INNER JOIN Q2_SystemPropertyDataElements spde ON spde.PropertyName = 'EnableCommercialSalesEnablement'
    INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
    WHERE spd.PropertyValue = 'True' AND aupde.PropertyName = 'AccessCommercialSalesEnablement'
    UNION ALL
    -- Part 3: UserManagementUserVerification (only if email/SMS verification enabled)
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
    WHERE EXISTS (
        SELECT 1 FROM Q2_SystemPropertyDataElements spde
        INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
        WHERE spde.PropertyName IN ('EndUserVerificationAllowEmailTargets', 'EndUserVerificationAllowSmsTargets') 
            AND spd.PropertyValue = 'True'
    ) AND aupde.PropertyName = 'UserManagementUserVerification'
) AS v
WHERE (v.GroupID = 7 OR v.GroupID IS NULL)
  AND (v.FIID = 1 OR v.FIID IS NULL)
  AND (v.UISourceID = 8 OR v.UISourceID IS NULL)
  AND (v.UserID = 440 OR v.UserID IS NULL)
  AND v.PropertyID NOT IN (84)
ORDER BY v.PropertyID ASC, v.Weight DESC;


-- =============================================================================
-- Query 2: Filter by GroupID=6, FIID=1, UISourceID=8, UserID=3 (no PropertyID exclusion)
-- =============================================================================
SELECT * FROM (
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde 
        ON aupd.PropertyID = aupde.PropertyID
        AND aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')
    UNION ALL
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
    INNER JOIN Q2_SystemPropertyDataElements spde ON spde.PropertyName = 'EnableCommercialSalesEnablement'
    INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
    WHERE spd.PropertyValue = 'True' AND aupde.PropertyName = 'AccessCommercialSalesEnablement'
    UNION ALL
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
    WHERE EXISTS (
        SELECT 1 FROM Q2_SystemPropertyDataElements spde
        INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
        WHERE spde.PropertyName IN ('EndUserVerificationAllowEmailTargets', 'EndUserVerificationAllowSmsTargets') 
            AND spd.PropertyValue = 'True'
    ) AND aupde.PropertyName = 'UserManagementUserVerification'
) AS v
WHERE (v.GroupID = 6 OR v.GroupID IS NULL)
  AND (v.FIID = 1 OR v.FIID IS NULL)
  AND (v.UISourceID = 8 OR v.UISourceID IS NULL)
  AND (v.UserID = 3 OR v.UserID IS NULL)
ORDER BY v.PropertyID ASC, v.Weight DESC;


-- =============================================================================
-- Query 3: Filter by GroupID=1 (used for both GroupID and FIID), UISourceID=8, UserID=2, exclude PropertyID=84
-- =============================================================================
SELECT * FROM (
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde 
        ON aupd.PropertyID = aupde.PropertyID
        AND aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')
    UNION ALL
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
    INNER JOIN Q2_SystemPropertyDataElements spde ON spde.PropertyName = 'EnableCommercialSalesEnablement'
    INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
    WHERE spd.PropertyValue = 'True' AND aupde.PropertyName = 'AccessCommercialSalesEnablement'
    UNION ALL
    SELECT  
        aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
        aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
        aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
        aupde.IsGroupProperty, aupde.IsUserProperty
    FROM Q2_AdminUserPropertyData aupd
    INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
    WHERE EXISTS (
        SELECT 1 FROM Q2_SystemPropertyDataElements spde
        INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
        WHERE spde.PropertyName IN ('EndUserVerificationAllowEmailTargets', 'EndUserVerificationAllowSmsTargets') 
            AND spd.PropertyValue = 'True'
    ) AND aupde.PropertyName = 'UserManagementUserVerification'
) AS v
WHERE (v.GroupID = 1 OR v.GroupID IS NULL)
  AND (v.FIID = 1 OR v.FIID IS NULL)
  AND (v.UISourceID = 8 OR v.UISourceID IS NULL)
  AND (v.UserID = 2 OR v.UserID IS NULL)
  AND v.PropertyID NOT IN (84)
ORDER BY v.PropertyID ASC, v.Weight DESC;


-- =============================================================================
-- Utility Queries
-- =============================================================================

-- Row counts for all tables
SELECT 'Q2_AdminUserPropertyDataElements' as tbl, COUNT(*) as cnt FROM Q2_AdminUserPropertyDataElements
UNION ALL SELECT 'Q2_AdminUserPropertyData', COUNT(*) FROM Q2_AdminUserPropertyData
UNION ALL SELECT 'Q2_SystemPropertyDataElements', COUNT(*) FROM Q2_SystemPropertyDataElements
UNION ALL SELECT 'Q2_SystemPropertyData', COUNT(*) FROM Q2_SystemPropertyData;

-- Check system flags status
SELECT spde.PropertyName, spd.PropertyValue
FROM Q2_SystemPropertyDataElements spde
INNER JOIN Q2_SystemPropertyData spd ON spd.PropertyID = spde.PropertyID
WHERE spde.PropertyName IN (
    'EnableCommercialSalesEnablement',
    'EndUserVerificationAllowEmailTargets', 
    'EndUserVerificationAllowSmsTargets'
);
