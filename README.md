# data-platform-sql-scripts

Central repository for SQL Server scripts used for administration, deployments, troubleshooting, and performance tuning.

## Structure
- admin/ → Maintenance and monitoring
- performance/ → Tuning and analysis
- troubleshooting/ → Diagnostics
- deployments/ → Schema changes

## Usage Guidelines
- Scripts must be idempotent where possible
- Avoid hardcoding database names
- Always test in non-production first

## Naming Convention
[category]_[purpose]_[object].sql"
ex.:
- admin_check_database_health.sql
- perf_missing_indexes_analysis.sql
- troubleshoot_blocking_sessions.sql
- deploy_create_customer_table.sql
