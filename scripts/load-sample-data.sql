-- =========================
-- Load Sample Data for GridGain Sync Testing
-- 1000 Customers, 500 Products, 10,000 Orders
-- Run via SSM port forward + DataGrip/SSMS
-- =========================

USE testdb;
GO

-- Clear existing data
DELETE FROM Orders;
DELETE FROM Products;
DELETE FROM Customers;
GO

-- =========================
-- Insert 1000 Customers
-- =========================
DECLARE @i INT = 1;
WHILE @i <= 1000
BEGIN
    INSERT INTO Customers (ID, Name, Email)
    VALUES (@i, CONCAT('Customer ', @i), CONCAT('customer', @i, '@example.com'));
    SET @i = @i + 1;
END
GO

PRINT 'Inserted 1000 customers';
GO

-- =========================
-- Insert 500 Products
-- =========================
DECLARE @i INT = 1;
WHILE @i <= 500
BEGIN
    INSERT INTO Products (ID, Name, Price)
    VALUES (@i, CONCAT('Product ', @i), ROUND(RAND() * 100 + 10, 2));
    SET @i = @i + 1;
END
GO

PRINT 'Inserted 500 products';
GO

-- =========================
-- Insert 10,000 Orders
-- =========================
DECLARE @i INT = 1;
WHILE @i <= 10000
BEGIN
    INSERT INTO Orders (ID, CustomerID, ProductID, Quantity, OrderDate)
    VALUES (
        @i,
        ((@i - 1) % 1000) + 1,           -- CustomerID 1-1000
        ((@i - 1) % 500) + 1,            -- ProductID 1-500
        ((@i % 10) + 1),                  -- Quantity 1-10
        FORMAT(DATEADD(day, -(@i % 365), GETDATE()), 'yyyy-MM-dd')
    );
    SET @i = @i + 1;
END
GO

PRINT 'Inserted 10000 orders';
GO

-- =========================
-- Verify counts
-- =========================
SELECT 'Customers' AS TableName, COUNT(*) AS RowCount FROM Customers
UNION ALL
SELECT 'Products', COUNT(*) FROM Products
UNION ALL
SELECT 'Orders', COUNT(*) FROM Orders;
GO
