/*
================================================================================
Script Name : report_usage_analysis.sql
Author      : Paulo Gonçalves
Created On  : 2026-01-14
Purpose     : Analyse SSRS / Power BI Report Server report usage.

Description :
    Returns an inventory of report server objects with execution statistics,
    including last execution, number of executions, creation date, modification
    date, last modifier, and last executing user.

Target DB   : ReportServer database
Platforms   : SQL Server Reporting Services (SSRS)
              Power BI Report Server (PBIRS)

Notes       :
    - Run this script in the ReportServer database context.
    - Uses dbo.ExecutionLog3, dbo.Catalog, and dbo.Users.
    - Platform detection is heuristic-based.
    - WITH (NOLOCK) is used to avoid blocking operational workloads; review this
      according to your organisation's data consistency standards.
    - Set @StartDate and/or @EndDate to limit execution history analysis.

Safe to run multiple times: YES
================================================================================
*/

SET NOCOUNT ON;

DECLARE @StartDate DATETIME = NULL; -- Example: '2025-01-01'
DECLARE @EndDate   DATETIME = NULL; -- Example: '2025-12-31'

BEGIN TRY;

    ;WITH PlatformDetection AS
    (
        SELECT
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM sys.tables AS t
                    WHERE t.name LIKE '%PowerBI%'
                       OR t.name LIKE '%DataModel%'
                       OR t.name LIKE '%Semantic%'
                )
                OR EXISTS
                (
                    SELECT 1
                    FROM dbo.Catalog AS c WITH (NOLOCK)
                    WHERE c.Name LIKE '%.pbix%'
                )
                THEN 'PBIRS'
                ELSE 'SSRS'
            END AS PlatformName
    ),
    ExecutionLogFiltered AS
    (
        SELECT
            el.ItemPath,
            el.UserName,
            el.TimeStart
        FROM dbo.ExecutionLog3 AS el WITH (NOLOCK)
        WHERE (@StartDate IS NULL OR el.TimeStart >= @StartDate)
          AND (@EndDate   IS NULL OR el.TimeStart < DATEADD(DAY, 1, @EndDate))
    )
    SELECT
        @@SERVERNAME AS [Server_Name],
        'Y' AS [Old_Server],
        DB_NAME() AS [DB_Name],
        pd.PlatformName AS [Platform],

        CASE c.[Type]
            WHEN 1 THEN 'Folder'
            WHEN 2 THEN 'Report (.rdl)'
            WHEN 3 THEN 'Resource / XML'
            WHEN 4 THEN 'Linked Report'
            WHEN 5 THEN 'Data Source (.rds)'
            WHEN 6 THEN 'Model'
            WHEN 8 THEN 'Shared Dataset'
            WHEN 9 THEN 'Report Part'
            WHEN 13 THEN 'Power BI Report (.pbix)'
            ELSE CONCAT('Unknown (Type ', c.[Type], ')')
        END AS [ObjectType],

        c.Name AS [Report_Name],
        c.[Path] AS [Report_Path],
        LEFT(c.[Path], LEN(c.[Path]) - CHARINDEX('/', REVERSE(c.[Path]))) AS [Report_Folder],

        MAX(u.UserName) AS [Last_Modified_By],
        MAX(elf.UserName) AS [Last_Executed_By],

        COUNT(elf.TimeStart) AS [Times_Run],
        MIN(c.CreationDate) AS [CreationDate],
        MAX(c.ModifiedDate) AS [ModifiedDate],
        MAX(elf.TimeStart) AS [Last_Run],

        CASE
            WHEN MAX(elf.TimeStart) IS NULL THEN 'Never Executed'
            ELSE 'Executed'
        END AS [Execution_Status]

    FROM dbo.Catalog AS c WITH (NOLOCK)
    CROSS JOIN PlatformDetection AS pd
    LEFT JOIN ExecutionLogFiltered AS elf
        ON elf.ItemPath = c.[Path]
    LEFT JOIN dbo.Users AS u WITH (NOLOCK)
        ON c.ModifiedByID = u.UserID

    GROUP BY
        pd.PlatformName,
        c.Name,
        c.[Type],
        c.[Path]

    ORDER BY
        [Times_Run] DESC,
        [Last_Run] DESC,
        [Report_Path] ASC;

END TRY
BEGIN CATCH;

    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();

    RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);

END CATCH;
