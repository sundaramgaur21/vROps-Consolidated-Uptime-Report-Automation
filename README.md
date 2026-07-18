vROps Consolidated Uptime Report Automation
---------------------------------------------
PowerShell automation tool for generating daily consolidated uptime reports from multiple VMware vRealize Operations (vROps) / Aria Operations environments, merging the data into a single report, converting it into an Excel-compatible format, and automatically distributing it via email.

Overview
---------
The vROps Consolidated Uptime Report Automation script is designed to collect uptime information from multiple vROps environments and produce a single consolidated uptime report for operational and management reporting.
The script connects to multiple vROps/Aria Operations environments using stored credentials, generates predefined reports, downloads the resulting CSV files, merges the data into a consolidated report, converts it into an Excel-compatible format, and automatically emails the final report to stakeholders.

This solution is particularly useful for:

-Daily uptime reporting
-Infrastructure operations reporting
-VMware environment monitoring
-Executive reporting
-Capacity and availability reviews
-Operational health dashboards
-Automated reporting requirements
-Multi-site environment monitoring

Features
--------
-Supports multiple vROps environments
-Secure credential storage using CLIXML
-Automated token-based authentication
-Automatic report execution
-Automatic report status monitoring
-Automated CSV report download
-Consolidated report generation
-Excel-compatible report creation
-Automatic email delivery
-Detailed logging
-File retention management
-PowerShell 5.1 compatible
-SSL certificate bypass support
-Automatic resource identification
-Automated failure notification emails

Supported Environments
-----------------------
The script currently supports multiple vROps environments including:
Environment 1
Environment 2
Environment 3

Each environment supports:

Unique vROps URL
Unique report definition
Individual credentials
Individual resource identifiers

How It Works
--------------
The script performs the following actions:

-Creates required folders if they do not exist
-Initializes logging
-Configures TLS 1.2
-Configures SSL certificate handling
-Removes old report files based on retention settings
-Authenticates to each vROps environment
-Retrieves authentication tokens
-Locates required resources
-Executes uptime reports ( or whatever report you want to consolidate with 3 environmets, just need the report ID)
-Monitors report generation status
-Downloads generated CSV reports
-Merges reports into a consolidated dataset
-Creates an Excel-compatible report
-Emails the final report
-Sends failure notifications if errors occur

Directory Structure
--------------------
The script uses the following folder structure:

Extract Folder
----------------
Stores individual downloaded reports.
Example:
D:\Sundaram\VROPS\VROPS extracted reports

Consolidated Report Folder
-------------------------
Stores merged reports.
Example:
D:\Sundaram\VROPS\Daily Consolidated Reports

Log Folder
----------
Stores script execution logs.
Example:
D:\Sundaram\VROPS\Logs

Authentication
------------------
The script uses stored PowerShell credentials.
Credentials are stored securely using:
Export-Clixml
Example:
vrops_environment1&2_cred.xml
vrops_environment3.xml
The script automatically loads credentials and authenticates against each vROps environment.

Report Generation Process
------------------------
Authentication
The script authenticates to each vROps instance using:

-Username
-Password
-Authentication Source

Token Acquisition
------------------
The script retrieves a valid OpsToken for API communication.

Resource Discovery
-------------------
If a Resource ID is not provided, the script automatically searches for the required resource.
Example Resource:
vSphere World

Report Execution
------------------
The script starts report execution using the configured Report Definition ID.
Example:

Env1 Report Definition
Env2 Report Definition
Env3 Report Definition

Report Monitoring
-----------------
The script continuously polls report status until one of the following occurs:

Completed
Finished
Success
Failed
Error
Timeout

CSV Download
--------------
Once completed, the report is downloaded in CSV format.
Example:
DC1-2026-07-18.csv
DC2-2026-07-18.csv
S02-2026-07-18.csv

Report Consolidation
--------------------
The script imports all downloaded CSV reports.
Each row receives an additional source identifier.
Example:
DC1
DC2
S02
The files are then merged into a single consolidated report.
Example Output:
Consolidated_Uptime_2026-07-18.csv

Excel Report Generation
-----------------------
The script automatically generates an Excel-compatible XML Spreadsheet document.
The report includes:

Column headers
Source environment identification
Freeze panes
Date formatting
Uptime calculation support

Generated File:
Consolidated_Uptime_2026-07-18.xls

Email Notification
------------------
Once the report is successfully generated, it is automatically emailed.
The email includes:

Daily uptime report attachment
Automated subject line
Notification message
Stakeholder contact information

Example Subject:
Connected Payments - Daily Consolidated vROps Uptime Report - 2026-07-18

Failure Handling
----------------
If any stage fails, the script:

Logs the error
Records details in the transcript
Sends a failure notification email
Returns a non-zero exit code

Common Failure Scenarios
------------------------
Authentication failure
Token generation failure
Missing credential files
Resource discovery failure
Report execution failure
Report timeout
CSV download failure
Email delivery failure
File creation failure

Logging
-------
The script creates a timestamped transcript log.
Example:
VROPS_Consolidated_Uptime_2026-07-18_10-00-00.log
Logged information includes:

Authentication status
Report execution status
Download status
Merge status
Excel generation status
Email delivery status
Error messages

Retention Management
--------------------
The script automatically removes files older than the configured retention period.
Default retention:
30 Days
Cleanup is applied to:

Extracted reports
Consolidated reports

Generated Reports
-------------------
Individual Reports
-------------------
Example:
DC1-2026-07-18.csv
DC2-2026-07-18.csv
S02-2026-07-18.csv

Consolidated Report
--------------------
Example:
Consolidated_Uptime_2026-07-18.csv

Excel Report
-------------
Example:
Consolidated_Uptime_2026-07-18.xls

Prerequisites
---------------
PowerShell 5.1
VMware vROps / Aria Operations 8.x
API access enabled
Stored CLIXML credentials
Network connectivity to all vROps instances
SMTP relay access
Appropriate report definitions configured
Required resource permissions

Usage
------
Run the script:
.\VROPS_Consolidated_Uptime_Report.ps1
The script runs automatically without user interaction.
Processing Steps:
-Authenticate
-Generate reports
-Download reports
-Merge CSV files
-Create Excel report
-Email results
-Clean up old files

Benefits
--------
Eliminates manual report generation
Consolidates multiple environments into one report
Reduces operational effort
Supports automated daily reporting
Provides centralized uptime visibility
Creates management-ready reports
Improves reporting consistency
Supports operational monitoring requirements

Use Cases
---------
Daily infrastructure reporting
VMware operations monitoring
Uptime reporting
Capacity reviews
Availability tracking
Executive dashboards
Operational health reviews
Multi-datacenter reporting

Limitations
------------
Requires valid vROps API access
Requires stored credentials
Requires SMTP connectivity
Depends on configured report definitions
Requires network access to vROps environments
Processes environments sequentially
Depends on API response availability

Future Enhancements
--------------------
Parallel report generation
HTML email reports
Dashboard integration
Teams notifications
SharePoint report publishing
Historical trend reporting
Automatic archive management
PDF report generation
Multi-recipient distribution lists
Report health validation

Author
-------
Sundaram Gaur
Senior Systems Engineer | VMware | PowerShell Automation | Infrastructure Operations

Disclaimer
-----------
This script is intended for authorized administrative use only. It accesses VMware vROps environments, generates operational reports, and distributes them through email. Ensure appropriate API permissions, credential security, SMTP access, and change management controls are in place before running in production environments.
