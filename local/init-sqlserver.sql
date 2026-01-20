-- Create Q2Test database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'Q2Test')
BEGIN
    CREATE DATABASE Q2Test;
END
GO

USE Q2Test;
GO

-- Enable change tracking on database
IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
BEGIN
    ALTER DATABASE Q2Test SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);
END
GO

-- Create schema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'admin')
BEGIN
    EXEC('CREATE SCHEMA admin');
END
GO

-- Q2_AdminUserPropertyDataElements
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Q2_AdminUserPropertyDataElements')
BEGIN
    CREATE TABLE admin.Q2_AdminUserPropertyDataElements (
        PropertyID INT PRIMARY KEY,
        PropertyName VARCHAR(80) NOT NULL,
        PropertyLongName VARCHAR(80) NOT NULL,
        PropertyDataType VARCHAR(3) NOT NULL,
        IsGroupProperty BIT NOT NULL,
        IsUserProperty BIT NOT NULL,
        VersionAdded INT
    );
    ALTER TABLE admin.Q2_AdminUserPropertyDataElements ENABLE CHANGE_TRACKING;
END
GO

-- Q2_AdminUserPropertyData
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Q2_AdminUserPropertyData')
BEGIN
    CREATE TABLE admin.Q2_AdminUserPropertyData (
        UserPropertyDataID INT PRIMARY KEY,
        GroupID INT,
        FIID INT,
        UISourceID INT,
        UserID INT,
        PropertyID INT NOT NULL,
        PropertyValue VARCHAR(50),
        Weight INT
    );
    ALTER TABLE admin.Q2_AdminUserPropertyData ENABLE CHANGE_TRACKING;
END
GO

-- Q2_SystemPropertyDataElements
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Q2_SystemPropertyDataElements')
BEGIN
    CREATE TABLE dbo.Q2_SystemPropertyDataElements (
        PropertyID INT PRIMARY KEY,
        PropertyName VARCHAR(80) NOT NULL,
        PropertyLongName VARCHAR(80) NOT NULL,
        PropertyDataType VARCHAR(3) NOT NULL
    );
    ALTER TABLE dbo.Q2_SystemPropertyDataElements ENABLE CHANGE_TRACKING;
END
GO

-- Q2_SystemPropertyData
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Q2_SystemPropertyData')
BEGIN
    CREATE TABLE dbo.Q2_SystemPropertyData (
        SystemPropertyDataID INT PRIMARY KEY,
        UISourceID INT,
        ProductTypeID SMALLINT,
        ProductID SMALLINT,
        GroupID INT,
        HADE_ID INT,
        PropertyID INT NOT NULL,
        PropertyValue VARCHAR(1024) NOT NULL
    );
    ALTER TABLE dbo.Q2_SystemPropertyData ENABLE CHANGE_TRACKING;
END
GO

-- Insert sample data: Admin Property Data Elements
INSERT INTO admin.Q2_AdminUserPropertyDataElements (PropertyID, PropertyName, PropertyLongName, PropertyDataType, IsGroupProperty, IsUserProperty, VersionAdded) VALUES
(1, 'AllowTransfers', 'Allow Transfers', 'BIT', 1, 1, 4400),
(2, 'AllowBillPay', 'Allow Bill Pay', 'BIT', 1, 1, 4400),
(3, 'AllowExternalTransfers', 'Allow External Transfers', 'BIT', 1, 1, 4400),
(4, 'DailyTransferLimit', 'Daily Transfer Limit', 'INT', 1, 1, 4400),
(5, 'AllowMobileDeposit', 'Allow Mobile Deposit', 'BIT', 1, 1, 4500),
(84, 'AccessCommercialSalesEnablement', 'Commercial Sales Enablement', 'BIT', 1, 0, 4600),
(85, 'UserManagementUserVerification', 'User Verification', 'BIT', 0, 1, 4600),
(10, 'AllowWireTransfers', 'Allow Wire Transfers', 'BIT', 1, 1, 4400),
(11, 'AllowACH', 'Allow ACH', 'BIT', 1, 1, 4400),
(12, 'SessionTimeout', 'Session Timeout Minutes', 'INT', 1, 0, 4400);
GO

-- Insert sample data: System Property Data Elements
INSERT INTO dbo.Q2_SystemPropertyDataElements (PropertyID, PropertyName, PropertyLongName, PropertyDataType) VALUES
(1, 'EnableCommercialSalesEnablement', 'Enable Commercial Sales', 'BIT'),
(2, 'EndUserVerificationAllowEmailTargets', 'Allow Email Verification', 'BIT'),
(3, 'EndUserVerificationAllowSmsTargets', 'Allow SMS Verification', 'BIT'),
(4, 'MaintenanceMode', 'Maintenance Mode', 'BIT'),
(5, 'MaxLoginAttempts', 'Max Login Attempts', 'INT');
GO

-- Insert sample data: System Property Data
INSERT INTO dbo.Q2_SystemPropertyData (SystemPropertyDataID, UISourceID, ProductTypeID, ProductID, GroupID, HADE_ID, PropertyID, PropertyValue) VALUES
(1, 8, NULL, NULL, NULL, NULL, 1, 'True'),
(2, 8, NULL, NULL, NULL, NULL, 2, 'True'),
(3, 8, NULL, NULL, NULL, NULL, 3, 'False'),
(4, 8, NULL, NULL, NULL, NULL, 4, 'False'),
(5, 8, NULL, NULL, NULL, NULL, 5, '5');
GO

-- Insert sample data: Admin User Property Data
INSERT INTO admin.Q2_AdminUserPropertyData (UserPropertyDataID, GroupID, FIID, UISourceID, UserID, PropertyID, PropertyValue, Weight) VALUES
(1, 1, NULL, 8, NULL, 1, 'True', 100),
(2, 1, NULL, 8, NULL, 2, 'True', 100),
(3, 1, NULL, 8, NULL, 3, 'False', 100),
(4, 1, NULL, 8, NULL, 4, '5000', 100),
(5, 1, 1, 8, NULL, 3, 'True', 200),
(6, 1, 1, 8, NULL, 4, '10000', 200),
(7, 1, 1, 8, 440, 4, '25000', 300),
(8, 1, 1, 8, 440, 5, 'True', 300),
(9, 7, NULL, 8, NULL, 1, 'True', 100),
(10, 7, NULL, 8, NULL, 2, 'True', 100),
(11, 7, 1, 8, NULL, 10, 'True', 200),
(12, 7, 1, 8, 3, 11, 'True', 300),
(13, 6, 1, 8, 3, 1, 'True', 300),
(14, 6, 1, 8, 3, 2, 'True', 300),
(15, 6, 1, 8, 3, 12, '30', 300);
GO

-- Verify row counts
SELECT 'Q2_AdminUserPropertyDataElements' as tbl, COUNT(*) as cnt FROM admin.Q2_AdminUserPropertyDataElements
UNION ALL SELECT 'Q2_AdminUserPropertyData', COUNT(*) FROM admin.Q2_AdminUserPropertyData
UNION ALL SELECT 'Q2_SystemPropertyDataElements', COUNT(*) FROM dbo.Q2_SystemPropertyDataElements
UNION ALL SELECT 'Q2_SystemPropertyData', COUNT(*) FROM dbo.Q2_SystemPropertyData;
GO

PRINT 'SQL Server initialization complete!';
GO
