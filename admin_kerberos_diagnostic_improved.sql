/*
Script: admin_kerberos_diagnostic.sql
Author: Paulo Gonçalves
Date: 2025-11-17
Description:
	Kerberos / NTLM Session Diagnostics
    Diagnostic script to identify Kerberos vs NTLM authentication usage
    and related connection/session details.
	This script helps diagnose why Kerberos authentication might not be working

Notes:
    - Review results to validate Kerberos configuration
    - Useful for troubleshooting double-hop / delegation issues
    - Adapt filters if running in high-volume environments
	- Run this script with appropriate permissions (sysadmin recommended)
	- Compatible with SQL Server 2005+ (adjusts for missing DMVs in older versions)

Safe to run multiple times: YES
*/

SET NOCOUNT ON;

BEGIN TRY

-- Section 0: Check SQL Server Version and Compatibility
-- ============================================
PRINT '=== SQL Server Version Information ==='
SELECT 
    @@VERSION AS [SQL_Server_Version],
    SERVERPROPERTY('ProductVersion') AS [Product_Version],
    SERVERPROPERTY('ProductLevel') AS [Service_Pack_Level],
    SERVERPROPERTY('Edition') AS [Edition]

-- Section 1: Check SQL Server Service Account and SPN Configuration
-- ============================================
PRINT '=== SQL Server Service Account Information ==='
-- This DMV is available in SQL Server 2008+
IF OBJECT_ID('sys.dm_server_services') IS NOT NULL
BEGIN
    SELECT 
        servicename,
        service_account,
        startup_type_desc,
        status_desc,
        process_id,
        last_startup_time
    FROM sys.dm_server_services
    WHERE servicename LIKE '%SQL Server%'
    ORDER BY servicename;
END
ELSE
BEGIN
    PRINT 'WARNING: sys.dm_server_services not available in this SQL Server version.'
    PRINT 'Please check SQL Server Configuration Manager for service account information.'
END

-- Section 2: Check Authentication Mode
-- ============================================
PRINT '=== Authentication Mode Check ==='
SELECT 
    CASE SERVERPROPERTY('IsIntegratedSecurityOnly')
        WHEN 1 THEN 'Windows Authentication Only'
        WHEN 0 THEN 'Mixed Mode (SQL Server and Windows Authentication)'
        ELSE 'Unknown'
    END AS [Authentication_Mode];

-- Section 3: Check Network Protocol Configuration (SQL Server 2008+)
-- ============================================
PRINT '=== Network Protocol Status ==='
IF OBJECT_ID('sys.dm_server_network_protocols') IS NOT NULL
BEGIN
    SELECT 
        protocol_name,
        is_enabled,
        certificate_name,
        encryption_required,
        authentication_method
    FROM sys.dm_server_network_protocols
    ORDER BY protocol_name;
END
ELSE
BEGIN
    PRINT 'WARNING: sys.dm_server_network_protocols not available in this SQL Server version.'
    PRINT 'Please check SQL Server Configuration Manager for network protocol settings.'
    PRINT 'Ensure TCP/IP protocol is enabled for Kerberos authentication.'
END

-- Section 4: Check Current Connection Authentication
-- ============================================
PRINT '=== Current Session Authentication Details ==='
SELECT 
    s.session_id,
    s.login_name,
    s.nt_domain,
    s.nt_user_name,
    s.original_login_name,
    s.security_id,
    s.authenticating_database_id,
    c.auth_scheme,
    CASE 
        WHEN c.auth_scheme = 'KERBEROS' THEN 'SUCCESS: Using Kerberos'
        WHEN c.auth_scheme = 'NTLM' THEN 'WARNING: Using NTLM (Kerberos failed)'
        WHEN c.auth_scheme = 'SQL' THEN 'INFO: Using SQL Authentication'
        ELSE 'UNKNOWN: ' + ISNULL(c.auth_scheme, 'NULL')
    END AS [Authentication_Status]
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
WHERE s.session_id = @@SPID;

-- Section 5: Check All Active Sessions Authentication
-- ============================================
PRINT '=== All Active Sessions Authentication Summary ==='
SELECT 
    c.auth_scheme,
    COUNT(*) as [Session_Count],
    CASE 
        WHEN c.auth_scheme = 'KERBEROS' THEN 'Kerberos (Preferred)'
        WHEN c.auth_scheme = 'NTLM' THEN 'NTLM (Fallback)'
        WHEN c.auth_scheme = 'SQL' THEN 'SQL Authentication'
        ELSE 'Other/Unknown'
    END AS [Auth_Type_Description]
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
WHERE s.is_user_process = 1
    AND c.auth_scheme IS NOT NULL
GROUP BY c.auth_scheme
ORDER BY Session_Count DESC;

-- Section 6: Check SQL Server Configuration for Kerberos
-- ============================================
PRINT '=== SQL Server Configuration Settings ==='
SELECT 
    name,
    value,
    value_in_use,
    description
FROM sys.configurations
WHERE name IN (
    'network packet size',
    'remote access',
    'show advanced options',
    'xp_cmdshell'
)
ORDER BY name;

-- Section 7: Check Windows Authentication Details
-- ============================================
PRINT '=== Windows Authentication Login Details ==='
SELECT 
    p.name AS [Principal_Name],
    p.type_desc AS [Principal_Type],
    p.is_disabled,
    p.create_date,
    p.modify_date,
    CASE 
        WHEN p.name LIKE '%$' THEN 'Computer Account'
        WHEN p.name LIKE '%\%' THEN 'Domain Account'
        ELSE 'Other'
    END AS [Account_Type]
FROM sys.server_principals p
WHERE p.type IN ('U', 'G', 'S') -- Windows user, group, or service account
    AND p.name NOT LIKE '##%' -- Exclude system accounts
ORDER BY p.name;

-- Section 8: Check for Common Kerberos Issues
-- ============================================
PRINT '=== Potential Kerberos Configuration Issues ==='

-- Check if SQL Server is running under LocalSystem (not recommended for Kerberos)
IF OBJECT_ID('sys.dm_server_services') IS NOT NULL
BEGIN
    IF EXISTS (
        SELECT 1 FROM sys.dm_server_services 
        WHERE servicename LIKE '%SQL Server%' 
        AND service_account IN ('LocalSystem', 'NT AUTHORITY\SYSTEM')
    )
    BEGIN
        PRINT 'WARNING: SQL Server is running under LocalSystem account. This prevents Kerberos authentication.'
        PRINT 'RECOMMENDATION: Change to a domain service account and register SPNs.'
    END
    
    -- Check if TCP/IP is enabled (if DMV is available)
    IF OBJECT_ID('sys.dm_server_network_protocols') IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.dm_server_network_protocols 
            WHERE protocol_name = 'TCP' AND is_enabled = 1
        )
        BEGIN
            PRINT 'WARNING: TCP/IP protocol is not enabled. This may affect Kerberos authentication.'
            PRINT 'RECOMMENDATION: Enable TCP/IP protocol in SQL Server Configuration Manager.'
        END
    END
END
ELSE
BEGIN
    PRINT 'INFO: Unable to check service account automatically in this SQL Server version.'
    PRINT 'Please manually verify that SQL Server is NOT running under LocalSystem.'
END

-- Section 9: Registry-based Service Account Check (Alternative for older versions)
-- ============================================
PRINT '=== Alternative Service Account Check ==='
PRINT 'For older SQL Server versions, check these registry locations:'
PRINT 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MSSQLSERVER'
PRINT 'Look for the ObjectName value to see the service account.'

-- Section 10: SPN Registration Check (PowerShell commands to run separately)
-- ============================================
PRINT '=== SPN Registration Commands (Run in PowerShell as Domain Admin) ==='
PRINT 'To check existing SPNs, run these PowerShell commands:'
PRINT ''
PRINT '# Check existing SPNs for SQL Server service account:'
PRINT 'setspn -L <ServiceAccountName>'
PRINT ''
PRINT '# Register SPNs for SQL Server (replace with actual values):'
PRINT 'setspn -A MSSQLSvc/<ServerFQDN>:1433 <ServiceAccountName>'
PRINT 'setspn -A MSSQLSvc/<ServerFQDN>:<InstanceName> <ServiceAccountName>'
PRINT ''
PRINT '# Check for duplicate SPNs:'
PRINT 'setspn -X'
PRINT ''
PRINT '# Example for default instance on server SQLSRV01 with service account DOMAIN\SQLService:'
PRINT 'setspn -A MSSQLSvc/SQLSRV01.domain.com:1433 DOMAIN\SQLService'
PRINT 'setspn -A MSSQLSvc/SQLSRV01:1433 DOMAIN\SQLService'

-- Section 11: Error Log Analysis (Version Compatible)
-- ============================================
PRINT '=== Recent Error Log Entries Related to Authentication ==='
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;

CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo VARCHAR(50),
    LogText NVARCHAR(4000)
);

-- Try to read error log (may fail if xp_readerrorlog is not available)
BEGIN TRY
    INSERT INTO #ErrorLog
    EXEC xp_readerrorlog 0, 1, N'authentication';
    
    INSERT INTO #ErrorLog
    EXEC xp_readerrorlog 0, 1, N'kerberos';
    
    INSERT INTO #ErrorLog
    EXEC xp_readerrorlog 0, 1, N'SSPI';
    
    INSERT INTO #ErrorLog
    EXEC xp_readerrorlog 0, 1, N'login failed';

    SELECT TOP 20
        LogDate,
        ProcessInfo,
        LogText
    FROM #ErrorLog
    WHERE LogDate >= DATEADD(day, -7, GETDATE()) -- Last 7 days
    ORDER BY LogDate DESC;
END TRY
BEGIN CATCH
    PRINT 'WARNING: Unable to read error log. Check permissions or use SQL Server Management Studio to view error log manually.'
    PRINT 'Look for entries containing: authentication, kerberos, SSPI, login failed'
END CATCH

DROP TABLE #ErrorLog;

-- Section 12: Manual Checks for Older SQL Server Versions
-- ============================================
PRINT '=== Manual Checks Required for Older SQL Server Versions ==='
PRINT '1. Open SQL Server Configuration Manager'
PRINT '2. Check SQL Server Services -> SQL Server -> Properties -> Log On tab'
PRINT '3. Verify service account is a domain account (not LocalSystem)'
PRINT '4. Check SQL Server Network Configuration -> Protocols'
PRINT '5. Ensure TCP/IP is enabled'
PRINT '6. Check Client Network Utility for protocol order'

-- Section 13: Recommendations Summary
-- ============================================
PRINT '=== KERBEROS TROUBLESHOOTING CHECKLIST ==='
PRINT '1. Ensure SQL Server runs under a domain service account (not LocalSystem)'
PRINT '2. Register proper SPNs for the service account using setspn commands'
PRINT '3. Ensure no duplicate SPNs exist (use setspn -X to check)'
PRINT '4. Verify TCP/IP protocol is enabled in SQL Server Configuration Manager'
PRINT '5. Check Windows firewall settings (port 1433 for default instance)'
PRINT '6. Verify time synchronization between client and server (within 5 minutes)'
PRINT '7. Ensure delegation is configured if needed (for multi-hop scenarios)'
PRINT '8. Check DNS resolution of SQL Server name from client'
PRINT '9. Verify client and server are in trusted domains'
PRINT '10. Check for recent Windows updates that might affect Kerberos'
PRINT '11. Test connectivity: telnet <servername> 1433'
PRINT '12. Use Kerberos troubleshooting tools: klist, kerbtray'

PRINT '=== Script Execution Completed ==='
PRINT 'If auth_scheme shows NTLM instead of KERBEROS, focus on SPN registration and service account configuration.'

END TRY
BEGIN CATCH

    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();

    RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

END CATCH;
