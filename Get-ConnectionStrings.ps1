<#

IIS Connection String Auditor (Get-ConnectionStrings.ps1)
This PowerShell script scans all Internet Information Services (IIS) sites on a local Windows machine, extracts all connection strings defined in their web.config files, 
and outputs the results to a structured CSV file for easy auditing and reporting.

Key Features:
Audit-Ready Output: Automatically generates a clean, structured CSV file.
Multi-Server Friendly: Includes the System Name ($env:COMPUTERNAME) in every row, allowing reports from multiple servers to be easily merged and tracked.
Dynamic Filenames: The output file is automatically named using the current system name and date to prevent overwriting and facilitate archiving (e.g., ConnectionStrings_MYSERVERNAME_20241008.csv).
Robust Error Handling: Logs sites that have no connection strings or for which the script could not retrieve configuration details due to access errors.

Prerequisites:
To run this script successfully, you must have:
Windows Server/Client with IIS installed.
The IISAdministration PowerShell Module. This module is typically installed automatically when the IIS Management Tools feature is enabled.
Permissions to read the IIS configuration (Administrative privileges are usually required).

Execute the Script
Download the Get-ConnectionStrings.ps1 file and run it from an elevated PowerShell session:
.\Get-ConnectionStrings.ps1

Check the Output
The script will display progress in the console and, upon completion, will generate a CSV file in the same directory.

Default Output Filename:
If you don't specify an output path, the file name will be automatically generated as:

ConnectionStrings_<SystemName>_<YYYYMMDD>.csv

Example: ConnectionStrings_WEB-SERVER01_20250615.csv

Specifying a Custom Path:
You can optionally specify a custom path and filename using the -OutputPath parameter:

.\Get-IISConnectionStrings -OutputPath "C:\Reports\Production_Strings.csv"
#>




# Requires the IISAdministration module, which is available on modern Windows Server/Client OS with IIS installed.
Import-Module IISAdministration -ErrorAction Stop

# Define a function that retrieves connection strings and outputs them as objects.
function Get-IISConnectionStrings {
    param(
        # Parameter to define the output file path. If not provided, a dynamic filename is generated.
        [Parameter(Mandatory=$false)]
        [string]$OutputPath
    )

    # Get the local machine name once for the report column
    $SystemName = $env:COMPUTERNAME 

    # Generate dynamic output filename if the parameter was not provided
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $DateString = (Get-Date -Format yyyyMMdd)
        # Dynamic format: ConnectionStrings_Systemname_yyyymmdd.csv
        $OutputPath = "C:\ConnectionStrings_$($SystemName)_$($DateString).csv"
    }
    
    # Get all IIS sites defined on the local server
    $sites = Get-IISSite

    Write-Host "--- Scanning $($sites.Count) IIS Sites on system '$SystemName' for Connection Strings ---" -ForegroundColor Yellow
    
    # Initialize an array to hold the results (PSCustomObject instances)
    $AllResults = @()
    $i = 0

    # Iterate through each site object
    foreach ($site in $sites) {
        $i++
        

        Write-Progress -Activity "Extracting Connection Strings from IIS Sites" -Status "Processing site: $($site.Name) ($i of $($sites.Count))" -PercentComplete (($i / $sites.Count) * 100)
        

        $SiteDetails = @{
            SystemName        = $SystemName 
            SiteName          = $site.Name
            SiteId            = $site.Id
            PhysicalPath      = $site.PhysicalPath
        }


        try {
            $connStringsPath = "IIS:\Sites\$($site.Name)"
            $connectionStrings = Get-WebConfiguration -PSPath $connStringsPath -Filter "connectionStrings/add" -ErrorAction Stop

            if ($connectionStrings -is [System.Collections.ICollection] -and $connectionStrings.Count -gt 0) {
                Write-Host "  Found $($connectionStrings.Count) connection string(s) for $($site.Name)." -ForegroundColor Green
                
                foreach ($connString in $connectionStrings) {

                    $ResultObject = [PSCustomObject]@{
                        SystemName            = $SiteDetails.SystemName # Included in output
                        SiteName              = $SiteDetails.SiteName
                        SiteId                = $SiteDetails.SiteId
                        ConnectionStringName  = $connString.Name
                        ConnectionStringValue = $connString.ConnectionString
                        PhysicalPath          = $SiteDetails.PhysicalPath
                        Source                = "web.config"
                        Status                = "Success"
                    }
                    $AllResults += $ResultObject
                }
            } else {

                Write-Host "  No connection strings found for $($site.Name)." -ForegroundColor Cyan
                $EmptyResult = [PSCustomObject]@{
                    SystemName            = $SiteDetails.SystemName # Included in output
                    SiteName              = $SiteDetails.SiteName
                    SiteId                = $SiteDetails.SiteId
                    ConnectionStringName  = ""
                    ConnectionStringValue = ""
                    PhysicalPath          = $SiteDetails.PhysicalPath
                    Source                = ""
                    Status                = "No Strings Found"
                }
                $AllResults += $EmptyResult
            }
        } catch {

            $ErrorMessage = "Error: $($_.Exception.Message)"
            Write-Host "  [ERROR] $($ErrorMessage) on site $($site.Name)." -ForegroundColor Red
            $ErrorResult = [PSCustomObject]@{
                SystemName            = $SiteDetails.SystemName 
                SiteName              = $SiteDetails.SiteName
                SiteId                = $SiteDetails.SiteId
                ConnectionStringName  = ""
                ConnectionStringValue = ""
                PhysicalPath          = $SiteDetails.PhysicalPath
                Source                = ""
                Status                = $ErrorMessage
            }
            $AllResults += $ErrorResult
        }
    }
    

    Write-Progress -Activity "Extracting Connection Strings from IIS Sites" -Status "Done." -Completed


    if ($AllResults.Count -gt 0) {

        $AllResults | Export-Csv -Path $OutputPath -NoTypeInformation -Force
        Write-Host ""
        Write-Host "--- Successfully exported $($AllResults.Count) result row(s) to $OutputPath ---" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "--- No IIS sites or data found. CSV export skipped. ---" -ForegroundColor Red
    }
}

# Execute the function, which now exports the data directly to a CSV file.
Get-IISConnectionStrings
