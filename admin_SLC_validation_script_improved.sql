/*
Script: admin_SLC_validation_script.sql
Author: Paulo Gonçalves
Date: 2025-11-17
Description:
    Ligth validation script for DBA after patching (performing Software Life Cycle(SLC)) checks.
   Post-patch validation script
   - Engine version + instance info
   - Databases not ONLINE and with an odd status
   - Authentication errors since last restart

Notes:
    - Review and adjust environment-specific values before execution
    - Intended for validation and diagnostic purposes
    - Test in non-production before running in production

Safe to run multiple times: YES
*/

SET NOCOUNT ON;

BEGIN TRY

SET NOCOUNT ON;

-- ***************
-- Variables:
--	1) Get SQL Server startup time (used as "since last reboot")
-- ***************
DECLARE @sqlserver_start_time datetime;

SELECT @sqlserver_start_time = sqlserver_start_time
FROM sys.dm_os_sys_info;   -- requires VIEW SERVER STATE

-- ***************
-- 1st result set: Engine / instance info
-- ***************
SELECT  
    @@SERVERNAME                               AS ServerName,
    SERVERPROPERTY('MachineName')              AS MachineName,
	ISNULL(SERVERPROPERTY('InstanceName'),'default') AS InstanceName,
    SERVERPROPERTY('ProductVersion')           AS ProductVersion,
    SERVERPROPERTY('ProductBuild')             AS ProductBuild,
    @sqlserver_start_time                      AS SqlServerStartTime;


-- ***************
-- 2nd result set: Databases not ONLINE (with fallback output)
-- ***************
IF OBJECT_ID('tempdb..#DBStatus') IS NOT NULL DROP TABLE #DBStatus;

CREATE TABLE #DBStatus
(
    ServerName        sysname,
    DatabaseName      sysname,
    StateDescription  nvarchar(60),
    UserAccess        nvarchar(60),
    ReadOnlyStatus    nvarchar(3),
    RecoveryModel     nvarchar(60)
);

INSERT INTO #DBStatus
SELECT  
    @@SERVERNAME                             AS ServerName,
    name                                     AS DatabaseName,
    state_desc                               AS StateDescription,
    user_access_desc                         AS UserAccess,
    CASE WHEN is_read_only = 1 THEN 'Yes' ELSE 'No' END AS ReadOnlyStatus,
    recovery_model_desc                      AS RecoveryModel
FROM sys.databases
--WHERE state_desc <> 'ONLINE'
WHERE state_desc in ('EMERGENCY', 'SUSPECT', 'RECOVERY PENDING', 'RECOVERING', 'RESTORING', '')
ORDER BY name;

IF NOT EXISTS (SELECT 1 FROM #DBStatus)
BEGIN
    INSERT INTO #DBStatus
    VALUES
    (
        @@SERVERNAME,
        'ALL GOOD',
        'N/A',
        'N/A',
        'N/A',
        'N/A'
    );
END

SELECT *
FROM #DBStatus
ORDER BY DatabaseName;

DROP TABLE IF EXISTS #DBStatus;


-- ***************
-- 3rd result set: Authentication errors since last restart
--   * Checks only the current SQL Server error log (archive 0)
--	 * If no relevant entries are found, returns a single "ALL GOOD" row
--	 * Only check active ERRORLOG file
-- ***************
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;

CREATE TABLE #ErrorLog
(
    LogDate     datetime,
    ProcessInfo nvarchar(50),
    [Text]      nvarchar(max)
);

BEGIN TRY
    DECLARE @CurrentErrorLogFile nvarchar(260);

    /* Get current error log file name */
    SELECT @CurrentErrorLogFile = CAST(SERVERPROPERTY('ErrorLogFileName') AS nvarchar(260));

    /* Read current error log (archive 0, SQL log type 1) looking for "Login failed" */
    INSERT INTO #ErrorLog (LogDate, ProcessInfo, [Text])
    EXEC xp_readerrorlog 0, 1, N'Login failed';

    /* If no events found since SQL Server startup, return a single ALL GOOD row */
    IF NOT EXISTS (SELECT 1 FROM #ErrorLog WHERE LogDate >= @sqlserver_start_time)
    BEGIN
        TRUNCATE TABLE #ErrorLog;

        INSERT INTO #ErrorLog (LogDate, ProcessInfo, [Text])
        VALUES (NULL, 'N/A', 'ALL GOOD');
    END;

    /* Final output */
    SELECT
        @@SERVERNAME                                             AS ServerName,
        [Text]                                                   AS LogMessage,
        @CurrentErrorLogFile                                     AS ErrorLogFile,
        CASE WHEN LogDate IS NULL THEN 'N/A' ELSE '0' END        AS ErrorLogArchiveNumber,
        ISNULL(CONVERT(varchar(19), LogDate, 120), 'N/A')        AS EventDate,
        ISNULL(ProcessInfo, 'N/A')                               AS ProcessInfo
    FROM #ErrorLog
    WHERE LogDate >= @sqlserver_start_time OR LogDate IS NULL
    ORDER BY EventDate DESC;
END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()  AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage,
        'Failed to read current SQL Server Error Log. Check sysadmin permissions or extended procedures status.' AS Notes;
END CATCH;

DROP TABLE IF EXISTS #ErrorLog;

END TRY
BEGIN CATCH

    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();

    RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

END CATCH;
