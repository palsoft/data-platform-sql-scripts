/*
Script: <name>
Author: <you>
Date: <date>
Description: <what this does>

Notes:
- Tested on: SQL Server XXXX
- Safe to run multiple times: YES/NO
*/

SET NOCOUNT ON;

BEGIN TRY

    BEGIN TRAN;

    -- Your code here

    COMMIT TRAN;

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    THROW;

END CATCH;
