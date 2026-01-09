-- Sample Data for Q2 Tables
-- Insert test data for performance testing

-- Admin Property Data Elements (lookup table)
INSERT INTO Q2_AdminUserPropertyDataElements (PropertyID, PropertyName, PropertyLongName, PropertyDataType, IsGroupProperty, IsUserProperty, VersionAdded) VALUES
(1, 'AllowTransfers', 'Allow Transfers', 'BIT', true, true, 4400),
(2, 'AllowBillPay', 'Allow Bill Pay', 'BIT', true, true, 4400),
(3, 'AllowExternalTransfers', 'Allow External Transfers', 'BIT', true, true, 4400),
(4, 'DailyTransferLimit', 'Daily Transfer Limit', 'INT', true, true, 4400),
(5, 'AllowMobileDeposit', 'Allow Mobile Deposit', 'BIT', true, true, 4500),
(84, 'AccessCommercialSalesEnablement', 'Commercial Sales Enablement', 'BIT', true, false, 4600),
(85, 'UserManagementUserVerification', 'User Verification', 'BIT', false, true, 4600),
(10, 'AllowWireTransfers', 'Allow Wire Transfers', 'BIT', true, true, 4400),
(11, 'AllowACH', 'Allow ACH', 'BIT', true, true, 4400),
(12, 'SessionTimeout', 'Session Timeout Minutes', 'INT', true, false, 4400);

-- System Property Data Elements
INSERT INTO Q2_SystemPropertyDataElements (PropertyID, PropertyName, PropertyLongName, PropertyDataType) VALUES
(1, 'EnableCommercialSalesEnablement', 'Enable Commercial Sales', 'BIT'),
(2, 'EndUserVerificationAllowEmailTargets', 'Allow Email Verification', 'BIT'),
(3, 'EndUserVerificationAllowSmsTargets', 'Allow SMS Verification', 'BIT'),
(4, 'MaintenanceMode', 'Maintenance Mode', 'BIT'),
(5, 'MaxLoginAttempts', 'Max Login Attempts', 'INT');

-- System Property Data
INSERT INTO Q2_SystemPropertyData (SystemPropertyDataID, UISourceID, ProductTypeID, ProductID, GroupID, HADE_ID, PropertyID, PropertyValue) VALUES
(1, 8, NULL, NULL, NULL, NULL, 1, 'True'),
(2, 8, NULL, NULL, NULL, NULL, 2, 'True'),
(3, 8, NULL, NULL, NULL, NULL, 3, 'False'),
(4, 8, NULL, NULL, NULL, NULL, 4, 'False'),
(5, 8, NULL, NULL, NULL, NULL, 5, '5');

-- Admin User Property Data (sample users with properties)
-- Generate data for multiple groups, FIs, and users
INSERT INTO Q2_AdminUserPropertyData (UserPropertyDataID, GroupID, FIID, UISourceID, UserID, PropertyID, PropertyValue, Weight) VALUES
-- Group-level properties (UserID = NULL)
(1, 1, NULL, 8, NULL, 1, 'True', 100),
(2, 1, NULL, 8, NULL, 2, 'True', 100),
(3, 1, NULL, 8, NULL, 3, 'False', 100),
(4, 1, NULL, 8, NULL, 4, '5000', 100),
-- FI-level overrides
(5, 1, 1, 8, NULL, 3, 'True', 200),
(6, 1, 1, 8, NULL, 4, '10000', 200),
-- User-level overrides
(7, 1, 1, 8, 440, 4, '25000', 300),
(8, 1, 1, 8, 440, 5, 'True', 300),
-- Another group
(9, 7, NULL, 8, NULL, 1, 'True', 100),
(10, 7, NULL, 8, NULL, 2, 'True', 100),
(11, 7, 1, 8, NULL, 10, 'True', 200),
(12, 7, 1, 8, 3, 11, 'True', 300),
-- More users
(13, 6, 1, 8, 3, 1, 'True', 300),
(14, 6, 1, 8, 3, 2, 'True', 300),
(15, 6, 1, 8, 3, 12, '30', 300);
