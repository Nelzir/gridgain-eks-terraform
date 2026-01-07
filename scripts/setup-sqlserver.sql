-- =========================
-- SQL Server Setup for GridGain Sync
-- Run this via SSMS, DataGrip, or sqlcmd
-- =========================

-- Create database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'testdb')
BEGIN
    CREATE DATABASE testdb;
    PRINT 'Created database: testdb';
END
GO

USE testdb;
GO

-- Enable Change Tracking on database
IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
BEGIN
    ALTER DATABASE testdb SET CHANGE_TRACKING = ON 
        (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON);
    PRINT 'Enabled Change Tracking on testdb';
END
GO

-- Customers table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Customers')
BEGIN
    CREATE TABLE Customers (
        ID INT PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Email NVARCHAR(100)
    );
    ALTER TABLE Customers ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
    PRINT 'Created table: Customers';
END
GO

-- Products table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Products')
BEGIN
    CREATE TABLE Products (
        ID INT PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Price DECIMAL(10, 2)
    );
    ALTER TABLE Products ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
    PRINT 'Created table: Products';
END
GO

-- Orders table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Orders')
BEGIN
    CREATE TABLE Orders (
        ID INT PRIMARY KEY,
        CustomerID INT,
        ProductID INT,
        Quantity INT,
        OrderDate NVARCHAR(50)
    );
    ALTER TABLE Orders ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
    PRINT 'Created table: Orders';
END
GO

-- Insert sample data
IF NOT EXISTS (SELECT 1 FROM Customers)
BEGIN
    INSERT INTO Customers (ID, Name, Email) VALUES
        (1, 'John Doe', 'john@example.com');
    PRINT 'Inserted sample customer';
END
GO

IF NOT EXISTS (SELECT 1 FROM Products)
BEGIN
    INSERT INTO Products (ID, Name, Price) VALUES
        (1, 'Widget', 29.99);
    PRINT 'Inserted sample product';
END
GO

IF NOT EXISTS (SELECT 1 FROM Orders)
BEGIN
    INSERT INTO Orders (ID, CustomerID, ProductID, Quantity, OrderDate) VALUES
        (1, 1, 1, 10, '2026-01-07');
    PRINT 'Inserted sample order';
END
GO

PRINT 'SQL Server setup complete!';
GO
