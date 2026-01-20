-- Q2 Denormalized User Properties for GridGain 9
-- Optimized for login-time reads: single table lookup by UserID
--
-- DESIGN NOTES:
-- 1. PropertyID in Q2_AdminUserPropertyDataElements is NOT the same as 
--    PropertyID in Q2_SystemPropertyDataElements (separate domains)
-- 2. This table pre-materializes the view result, updated via CDC/triggers
-- 3. Feature flags (AccessCommercialSalesEnablement, UserManagementUserVerification)
--    are evaluated at write-time, not read-time

CREATE ZONE IF NOT EXISTS q2_denorm_zone WITH REPLICAS=3, PARTITIONS=25, STORAGE_PROFILES='aipersist';

-- Denormalized user properties table
-- Key insight: partition by UserID for login-time lookups
CREATE TABLE IF NOT EXISTS Q2_UserPropertiesDenorm (
    -- Composite key: UserID + PropertyID for uniqueness
    UserID INT,
    AdminPropertyID INT,  -- from Q2_AdminUserPropertyDataElements.PropertyID
    
    -- Flattened from Q2_AdminUserPropertyData
    UserPropertyDataID INT NOT NULL,
    GroupID INT,
    FIID INT,
    UISourceID INT,
    PropertyValue VARCHAR(50),
    Weight INT,
    
    -- Flattened from Q2_AdminUserPropertyDataElements
    PropertyName VARCHAR(80) NOT NULL,
    PropertyLongName VARCHAR(80) NOT NULL,
    PropertyDataType VARCHAR(3) NOT NULL,
    IsGroupProperty BOOLEAN NOT NULL,
    IsUserProperty BOOLEAN NOT NULL,
    
    -- Denormalization metadata
    LastUpdated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (UserID, AdminPropertyID)
) WITH PRIMARY_ZONE='q2_denorm_zone';

-- Secondary index for group-based lookups if needed
CREATE INDEX IF NOT EXISTS idx_denorm_groupid ON Q2_UserPropertiesDenorm (GroupID);
CREATE INDEX IF NOT EXISTS idx_denorm_fiid ON Q2_UserPropertiesDenorm (FIID);

-- ============================================================================
-- SYNC STRATEGY (choose one):
-- ============================================================================
-- Option A: Application-level sync
--   - When user properties change, app writes to both normalized + denorm tables
--   - When system flags change, batch job re-evaluates affected users
--
-- Option B: CDC from SQL Server
--   - Use Debezium/Kafka to capture changes from source
--   - Stream processor evaluates feature flags and writes to denorm table
--
-- Option C: Periodic materialization
--   - Scheduled job runs the full view query and upserts results
--   - Good for eventually-consistent scenarios
-- ============================================================================

-- LOGIN QUERY (now just a partition scan):
-- SELECT * FROM Q2_UserPropertiesDenorm WHERE UserID = ?
-- Expected latency: <1ms at any scale
