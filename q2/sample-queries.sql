-- Sample Queries for Q2_AdminUserPropertyView Access Pattern
-- These match the common access patterns from SQL Server

-- Query 1: Filter by GroupID, FIID, UISourceID, UserID (with NULL handling)
SELECT 
    aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
    aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
    aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
    aupde.IsGroupProperty, aupde.IsUserProperty
FROM Q2_AdminUserPropertyData aupd
INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
WHERE aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')
  AND (aupd.GroupID = ? OR aupd.GroupID IS NULL)
  AND (aupd.FIID = ? OR aupd.FIID IS NULL)
  AND (aupd.UISourceID = ? OR aupd.UISourceID IS NULL)
  AND (aupd.UserID = ? OR aupd.UserID IS NULL)
ORDER BY aupd.PropertyID ASC, aupd.Weight DESC;
-- Example: args: [7, 1, 8, 440]

-- Query 2: Same as Query 1 but with PropertyID exclusion
SELECT 
    aupd.UserPropertyDataID, aupd.GroupID, aupd.FIID, aupd.UISourceID, aupd.UserID,
    aupd.PropertyID, aupde.PropertyName, aupde.PropertyLongName,
    aupde.PropertyDataType, aupd.PropertyValue, aupd.Weight,
    aupde.IsGroupProperty, aupde.IsUserProperty
FROM Q2_AdminUserPropertyData aupd
INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
WHERE aupde.PropertyName NOT IN ('AccessCommercialSalesEnablement', 'UserManagementUserVerification')
  AND (aupd.GroupID = ? OR aupd.GroupID IS NULL)
  AND (aupd.FIID = ? OR aupd.FIID IS NULL)
  AND (aupd.UISourceID = ? OR aupd.UISourceID IS NULL)
  AND (aupd.UserID = ? OR aupd.UserID IS NULL)
  AND aupd.PropertyID NOT IN (?)
ORDER BY aupd.PropertyID ASC, aupd.Weight DESC;
-- Example: args: [7, 1, 8, 440, 84]

-- Query 3: Simple count for monitoring
SELECT COUNT(*) FROM Q2_AdminUserPropertyData;

-- Query 4: Point lookup by UserPropertyDataID
SELECT * FROM Q2_AdminUserPropertyData WHERE UserPropertyDataID = ?;
-- Example: args: [12345]

-- Query 5: Get all properties for a specific user
SELECT 
    aupd.PropertyID, aupde.PropertyName, aupd.PropertyValue, aupd.Weight
FROM Q2_AdminUserPropertyData aupd
INNER JOIN Q2_AdminUserPropertyDataElements aupde ON aupd.PropertyID = aupde.PropertyID
WHERE aupd.UserID = ?
ORDER BY aupd.Weight DESC;
-- Example: args: [440]
