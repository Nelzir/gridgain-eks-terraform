#!/bin/bash
set -e

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
SERVER="sqlserver"
USER="sa"
PASSWORD="YourStrong@Passw0rd"

echo "Waiting for SQL Server to be ready..."
sleep 10

echo "Creating database and tables..."
$SQLCMD -S $SERVER -U $USER -P $PASSWORD -C -i /init-sqlserver.sql

echo "==================================="
echo "SQL Server setup complete!"
echo "Database: Q2Test"
echo "Connection: sqlserver://sa:YourStrong@Passw0rd@localhost:1433?database=Q2Test"
echo "==================================="
