-- Q2 Admin User Property Tables for GridGain 9
-- These tables support the Q2_AdminUserPropertyView access pattern

-- Create zone with replication factor 3 for high availability
CREATE ZONE IF NOT EXISTS q2_zone WITH REPLICAS=3, PARTITIONS=25, STORAGE_PROFILES='aipersist';

-- Admin User Property Data Elements (lookup table)
CREATE TABLE IF NOT EXISTS Q2_AdminUserPropertyDataElements (
    PropertyID INT PRIMARY KEY,
    PropertyName VARCHAR(80) NOT NULL,
    PropertyLongName VARCHAR(80) NOT NULL,
    PropertyDataType VARCHAR(3) NOT NULL,
    IsGroupProperty BOOLEAN NOT NULL,
    IsUserProperty BOOLEAN NOT NULL,
    VersionAdded INT
) WITH PRIMARY_ZONE='q2_zone';

-- Admin User Property Data (main data table)
CREATE TABLE IF NOT EXISTS Q2_AdminUserPropertyData (
    UserPropertyDataID INT PRIMARY KEY,
    GroupID INT,
    FIID INT,
    UISourceID INT,
    UserID INT,
    PropertyID INT NOT NULL,
    PropertyValue VARCHAR(50),
    Weight INT
) WITH PRIMARY_ZONE='q2_zone';

-- Indexes for common access patterns
CREATE INDEX IF NOT EXISTS idx_admin_propdata_propid ON Q2_AdminUserPropertyData (PropertyID);
CREATE INDEX IF NOT EXISTS idx_admin_propdata_groupid ON Q2_AdminUserPropertyData (GroupID);
CREATE INDEX IF NOT EXISTS idx_admin_propdata_fiid ON Q2_AdminUserPropertyData (FIID);
CREATE INDEX IF NOT EXISTS idx_admin_propdata_uisourceid ON Q2_AdminUserPropertyData (UISourceID);
CREATE INDEX IF NOT EXISTS idx_admin_propdata_userid ON Q2_AdminUserPropertyData (UserID);
CREATE INDEX IF NOT EXISTS idx_admin_propdata_weight ON Q2_AdminUserPropertyData (Weight);

-- System Property Data Elements (lookup table)
CREATE TABLE IF NOT EXISTS Q2_SystemPropertyDataElements (
    PropertyID INT PRIMARY KEY,
    PropertyName VARCHAR(80) NOT NULL,
    PropertyLongName VARCHAR(80) NOT NULL,
    PropertyDataType VARCHAR(3) NOT NULL
) WITH PRIMARY_ZONE='q2_zone';

-- System Property Data (main data table)
CREATE TABLE IF NOT EXISTS Q2_SystemPropertyData (
    SystemPropertyDataID INT PRIMARY KEY,
    UISourceID INT,
    ProductTypeID SMALLINT,
    ProductID SMALLINT,
    GroupID INT,
    HADE_ID INT,
    PropertyID INT NOT NULL,
    PropertyValue VARCHAR(1024) NOT NULL
) WITH PRIMARY_ZONE='q2_zone';

-- Indexes for system property lookups
CREATE INDEX IF NOT EXISTS idx_system_propdata_propid ON Q2_SystemPropertyData (PropertyID);
