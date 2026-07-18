################################################################################
# VROPS CONSOLIDATED UPTIME REPORT SCRIPT
# PowerShell 5.1 Compatible
# vROps / Aria Operations 8.18.6
################################################################################

# --------------------------- CONFIG ------------------------------------------

$vropsTargets = @(
    @{
        Name               = "DC1"
        Url                = "https://10.1.60.131"
        ReportDefinitionId = "1ad1a67a-ad27-46ae-8a45-7d2f1fce3209"
        CredentialFile     = "D:\Sundaram\VROPS\Secure\vrops_dc1dc2_cred.xml"
        AuthSource         = "Local"
        ResourceName       = "vSphere World"
        ResourceId         = "838a77f0-0fba-4d36-8291-d5b818f379a4"
    },
    @{
        Name               = "DC2"
        Url                = "https://10.2.33.231"
        ReportDefinitionId = "f6a71372-d88b-4849-9cbd-b682db3a3df7"
        CredentialFile     = "D:\Sundaram\VROPS\Secure\vrops_dc1dc2_cred.xml"
        AuthSource         = "Local"
        ResourceName       = "vSphere World"
        ResourceId         = "7e0a5795-2122-43fe-b8b7-2bd65aaf9493"
    },
    @{
        Name               = "S02"
        Url                = "https://s02-adm-vrps-01.servereps.local"
        ReportDefinitionId = "9007e4f6-37c7-4b86-8464-e61a85fbce58"
        CredentialFile     = "D:\Sundaram\VROPS\Secure\vrops_s02_cred.xml"
        AuthSource         = "Local"
        ResourceName       = "vSphere World"
        ResourceId         = ""
    }
)

$extractFolder      = "D:\Sundaram\VROPS\VROPS extracted reports"
$consolidatedFolder = "D:\Sundaram\VROPS\Daily Consolidated Reports"
$logFolder          = "D:\Sundaram\VROPS\Logs"

$emailTo    = "Sundaram.Gaur@ncrvoyix.com"
$emailFrom  = "Sundaram.Gaur@ncrvoyix.com"
$smtpServer = "DC1SMTP01.servereps.local"
$smtpPort   = 25

$reportTimeoutMinutes = 15
$pollIntervalSeconds  = 30
$retentionDays        = 30

################################################################################
# SETUP
################################################################################

foreach ($folder in @($extractFolder, $consolidatedFolder, $logFolder)) {
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

$runDateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logFolder "VROPS_Consolidated_Uptime_$runDateTime.log"

Start-Transcript -Path $logFile -Append | Out-Null

################################################################################
# TLS / CERTIFICATE BYPASS FOR POWERSHELL 5.1
################################################################################

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not ([System.Management.Automation.PSTypeName]'CertBypassVropsClean').Type) {
    $certCode = 'using System.Net; using System.Security.Cryptography.X509Certificates; using System.Net.Security; public class CertBypassVropsClean { public static bool IgnoreCert(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) { return true; } }'
    Add-Type -TypeDefinition $certCode
}

$certCallback = [System.Delegate]::CreateDelegate(
    [System.Net.Security.RemoteCertificateValidationCallback],
    [CertBypassVropsClean].GetMethod("IgnoreCert")
)

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $certCallback

################################################################################
# FUNCTIONS
################################################################################

function Write-Step {
    param(
        [string]$Message,
        [string]$Color = "Cyan"
    )

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Test-IsBlank {
    param([object]$Value)

    if ($null -eq $Value) {
        return $true
    }

    if (([string]$Value).Trim().Length -eq 0) {
        return $true
    }

    return $false
}

function Invoke-VROpsRetentionCleanup {
    param(
        [string[]]$Folders,
        [int]$DaysToKeep
    )

    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)

    foreach ($folder in $Folders) {
        if (-not (Test-Path $folder)) {
            continue
        }

        Write-Step "Cleaning files older than $DaysToKeep days from: $folder" "Yellow"

        $oldFiles = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }

        foreach ($file in $oldFiles) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Step "Deleted old file: $($file.FullName)" "DarkYellow"
            }
            catch {
                Write-Step "Unable to delete old file: $($file.FullName). Error: $($_.Exception.Message)" "Yellow"
            }
        }
    }
}

function Get-StoredCredential {
    param([string]$CredentialFile)

    if (-not (Test-Path $CredentialFile)) {
        throw "Credential file not found: $CredentialFile"
    }

    return Import-Clixml -Path $CredentialFile
}

function Get-VROpsToken {
    param(
        [string]$VropsUrl,
        [string]$Username,
        [string]$Password,
        [string]$AuthSource
    )

    try {
        $body = @{
            username   = $Username
            password   = $Password
            authSource = $AuthSource
        } | ConvertTo-Json

        $response = Invoke-RestMethod `
            -Method POST `
            -Uri "$VropsUrl/suite-api/api/auth/token/acquire" `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop

        $ns = New-Object System.Xml.XmlNamespaceManager($response.NameTable)
        $ns.AddNamespace("ops", "http://webservice.vmware.com/vRealizeOpsMgr/1.0/")

        $tokenNode = $response.SelectSingleNode("//ops:token", $ns)

        if ($null -eq $tokenNode) {
            throw "Token node not found in response."
        }

        if (Test-IsBlank $tokenNode.InnerText) {
            throw "Token value is blank."
        }

        return $tokenNode.InnerText
    }
    catch {
        Write-Step "ERROR authenticating to $VropsUrl" "Red"
        Write-Host $_.Exception.Message -ForegroundColor Red

        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                Write-Host "SERVER RESPONSE:" -ForegroundColor Yellow
                Write-Host $reader.ReadToEnd()
            }
            catch {}
        }

        return $null
    }
}

function New-VROpsHeaders {
    param([string]$Token)

    return @{
        "Authorization" = "OpsToken $Token"
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
    }
}

function Find-VROpsResourceIdRecursive {
    param(
        [object]$Object,
        [string]$ResourceName
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        foreach ($item in $Object) {
            $found = Find-VROpsResourceIdRecursive -Object $item -ResourceName $ResourceName
            if (-not (Test-IsBlank $found)) {
                return $found
            }
        }

        return $null
    }

    $props = $Object.PSObject.Properties.Name

    if ($props -contains "resourceKey" -and $props -contains "id") {
        $resourceKey = $Object.resourceKey

        if ($null -ne $resourceKey) {
            $resourceKeyProps = $resourceKey.PSObject.Properties.Name

            if ($resourceKeyProps -contains "name") {
                if ($resourceKey.name -eq $ResourceName) {
                    return $Object.id
                }
            }
        }
    }

    foreach ($property in $Object.PSObject.Properties) {
        $value = $property.Value

        if ($null -eq $value) {
            continue
        }

        if ($value -is [string] -or $value -is [int] -or $value -is [long] -or $value -is [bool]) {
            continue
        }

        $found = Find-VROpsResourceIdRecursive -Object $value -ResourceName $ResourceName

        if (-not (Test-IsBlank $found)) {
            return $found
        }
    }

    return $null
}

function Get-VROpsResourceId {
    param(
        [string]$VropsUrl,
        [string]$Token,
        [string]$ResourceName
    )

    try {
        $headers = New-VROpsHeaders -Token $Token

        Write-Step "Searching ResourceId for '$ResourceName' on $VropsUrl..." "Yellow"

        $response = Invoke-RestMethod `
            -Method GET `
            -Uri "$VropsUrl/suite-api/api/resources/groups" `
            -Headers $headers `
            -ErrorAction Stop

        $resourceId = Find-VROpsResourceIdRecursive -Object $response -ResourceName $ResourceName

        if (Test-IsBlank $resourceId) {
            throw "Could not find ResourceId for '$ResourceName'."
        }

        return $resourceId
    }
    catch {
        Write-Step "ERROR finding ResourceId for '$ResourceName' on $VropsUrl" "Red"
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $null
    }
}

function Get-ReportIdFromResponse {
    param([object]$Response)

    if ($null -eq $Response) {
        return $null
    }

    $props = $Response.PSObject.Properties.Name

    if ($props -contains "id") {
        return $Response.id
    }

    if ($props -contains "identifier") {
        return $Response.identifier
    }

    if ($props -contains "report") {
        if ($null -ne $Response.report) {
            $reportProps = $Response.report.PSObject.Properties.Name

            if ($reportProps -contains "id") {
                return $Response.report.id
            }

            if ($reportProps -contains "identifier") {
                return $Response.report.identifier
            }
        }
    }

    return $null
}

function Start-VROpsReportRun {
    param(
        [string]$VropsUrl,
        [string]$Token,
        [string]$ReportDefinitionId,
        [string]$ResourceId
    )

    try {
        $headers = New-VROpsHeaders -Token $Token

        $body = @{
            reportDefinitionId = $ReportDefinitionId
            resourceId         = $ResourceId
        } | ConvertTo-Json

        Write-Step "Starting report. Definition=$ReportDefinitionId Resource=$ResourceId" "Yellow"

        $response = Invoke-RestMethod `
            -Method POST `
            -Uri "$VropsUrl/suite-api/api/reports" `
            -Headers $headers `
            -Body $body `
            -ErrorAction Stop

        $reportId = Get-ReportIdFromResponse -Response $response

        if (Test-IsBlank $reportId) {
            Write-Host "Report start response:" -ForegroundColor Yellow
            $response | Format-List *
            throw "Could not find ReportId in response."
        }

        return $reportId
    }
    catch {
        Write-Step "ERROR starting report on $VropsUrl" "Red"
        Write-Host $_.Exception.Message -ForegroundColor Red

        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                Write-Host "SERVER RESPONSE:" -ForegroundColor Yellow
                Write-Host $reader.ReadToEnd()
            }
            catch {}
        }

        return $null
    }
}

function Get-VROpsReportStatus {
    param([object]$Response)

    if ($null -eq $Response) {
        return $null
    }

    $props = $Response.PSObject.Properties.Name

    if ($props -contains "status") {
        return $Response.status
    }

    if ($props -contains "reportStatus") {
        return $Response.reportStatus
    }

    if ($props -contains "state") {
        return $Response.state
    }

    if ($props -contains "report") {
        if ($null -ne $Response.report) {
            $reportProps = $Response.report.PSObject.Properties.Name

            if ($reportProps -contains "status") {
                return $Response.report.status
            }

            if ($reportProps -contains "reportStatus") {
                return $Response.report.reportStatus
            }

            if ($reportProps -contains "state") {
                return $Response.report.state
            }
        }
    }

    return $null
}

function Wait-VROpsReportComplete {
    param(
        [string]$VropsUrl,
        [string]$Token,
        [string]$ReportId
    )

    $headers = New-VROpsHeaders -Token $Token
    $deadline = (Get-Date).AddMinutes($reportTimeoutMinutes)

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-RestMethod `
                -Method GET `
                -Uri "$VropsUrl/suite-api/api/reports/$ReportId" `
                -Headers $headers `
                -ErrorAction Stop

            $status = Get-VROpsReportStatus -Response $response

            if (Test-IsBlank $status) {
                $status = "UNKNOWN"
            }

            Write-Step "ReportId=$ReportId Status=$status" "Yellow"

            if ($status -match "COMPLETED|FINISHED|SUCCESS|DONE") {
                return $true
            }

            if ($status -match "FAILED|ERROR|CANCELLED|CANCELED") {
                throw "Report failed with status: $status"
            }
        }
        catch {
            Write-Step "Warning while checking report status: $($_.Exception.Message)" "Yellow"
        }

        Start-Sleep -Seconds $pollIntervalSeconds
    }

    Write-Step "Timed out waiting for ReportId=$ReportId" "Red"
    return $false
}

function Download-VROpsReportCsv {
    param(
        [string]$VropsUrl,
        [string]$Token,
        [string]$ReportId,
        [string]$OutputFile
    )

    try {
        $headers = @{
            "Authorization" = "OpsToken $Token"
            "Accept"        = "text/csv"
        }

        Write-Step "Downloading CSV for ReportId=$ReportId" "Yellow"

        Invoke-WebRequest `
            -Method GET `
            -Uri "$VropsUrl/suite-api/api/reports/$ReportId/download?format=CSV" `
            -Headers $headers `
            -UseBasicParsing `
            -OutFile $OutputFile `
            -ErrorAction Stop

        if (-not (Test-Path $OutputFile)) {
            throw "CSV file was not created."
        }

        if ((Get-Item $OutputFile).Length -eq 0) {
            throw "CSV file is empty."
        }

        return $true
    }
    catch {
        Write-Step "ERROR downloading CSV from $VropsUrl" "Red"
        Write-Host $_.Exception.Message -ForegroundColor Red

        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                Write-Host "SERVER RESPONSE:" -ForegroundColor Yellow
                Write-Host $reader.ReadToEnd()
            }
            catch {}
        }

        return $false
    }
}

function Escape-XmlValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [System.Security.SecurityElement]::Escape([string]$Value)
}

function Convert-ConsolidatedCsvToFormattedExcel {
    param(
        [string]$CsvFile,
        [string]$ExcelFile
    )

    try {
        if (-not (Test-Path $CsvFile)) {
            throw "CSV file not found for Excel conversion: $CsvFile"
        }

        Write-Step "Creating Excel-compatible report without Excel COM: $ExcelFile" "Cyan"

        $rows = @(Import-Csv -Path $CsvFile)

        if ($null -eq $rows -or $rows.Count -eq 0) {
            throw "CSV does not contain data rows."
        }

        $headers = @($rows[0].PSObject.Properties.Name)

        $uptimeIndex = -1

        for ($i = 0; $i -lt $headers.Count; $i++) {
            if ($headers[$i].Trim() -eq "Uptime") {
                $uptimeIndex = $i
                break
            }
        }

        if ($uptimeIndex -eq -1) {
            for ($i = 0; $i -lt $headers.Count; $i++) {
                if ($headers[$i].Trim() -match "Uptime") {
                    $uptimeIndex = $i
                    break
                }
            }
        }

        if ($uptimeIndex -eq -1) {
            throw "Could not find Uptime column in consolidated report."
        }

        $finalHeaders = New-Object System.Collections.ArrayList

        for ($i = 0; $i -lt $headers.Count; $i++) {
            [void]$finalHeaders.Add($headers[$i])

            if ($i -eq $uptimeIndex) {
                [void]$finalHeaders.Add("Uptime Time")
            }
        }

        $xmlBuilder = New-Object System.Text.StringBuilder

        [void]$xmlBuilder.AppendLine('<?xml version="1.0"?>')
        [void]$xmlBuilder.AppendLine('<?mso-application progid="Excel.Sheet"?>')
        [void]$xmlBuilder.AppendLine('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"')
        [void]$xmlBuilder.AppendLine(' xmlns:o="urn:schemas-microsoft-com:office:office"')
        [void]$xmlBuilder.AppendLine(' xmlns:x="urn:schemas-microsoft-com:office:excel"')
        [void]$xmlBuilder.AppendLine(' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"')
        [void]$xmlBuilder.AppendLine(' xmlns:html="http://www.w3.org/TR/REC-html40">')

        [void]$xmlBuilder.AppendLine(' <Styles>')
        [void]$xmlBuilder.AppendLine('  <Style ss:ID="HeaderStyle">')
        [void]$xmlBuilder.AppendLine('   <Font ss:Bold="1"/>')
        [void]$xmlBuilder.AppendLine('  </Style>')
        [void]$xmlBuilder.AppendLine('  <Style ss:ID="DateTimeStyle">')
        [void]$xmlBuilder.AppendLine('   <NumberFormat ss:Format="mm/dd/yyyy hh:mm"/>')
        [void]$xmlBuilder.AppendLine('  </Style>')
        [void]$xmlBuilder.AppendLine(' </Styles>')

        [void]$xmlBuilder.AppendLine(' <Worksheet ss:Name="Consolidated Uptime">')
        [void]$xmlBuilder.AppendLine('  <Table>')

        # Header row
        [void]$xmlBuilder.AppendLine('   <Row>')

        foreach ($header in $finalHeaders) {
            $escapedHeader = Escape-XmlValue $header
            [void]$xmlBuilder.AppendLine("    <Cell ss:StyleID=""HeaderStyle""><Data ss:Type=""String"">$escapedHeader</Data></Cell>")
        }

        [void]$xmlBuilder.AppendLine('   </Row>')

        # Data rows
        foreach ($row in $rows) {
            [void]$xmlBuilder.AppendLine('   <Row>')

            for ($i = 0; $i -lt $headers.Count; $i++) {
                $headerName = $headers[$i]
                $cellValue = Escape-XmlValue $row.$headerName

                [void]$xmlBuilder.AppendLine("    <Cell><Data ss:Type=""String"">$cellValue</Data></Cell>")

                if ($i -eq $uptimeIndex) {
                    [void]$xmlBuilder.AppendLine('    <Cell ss:StyleID="DateTimeStyle" ss:Formula="=TODAY()-RC[-1]"><Data ss:Type="Number">0</Data></Cell>')
                }
            }

            [void]$xmlBuilder.AppendLine('   </Row>')
        }

        [void]$xmlBuilder.AppendLine('  </Table>')
        [void]$xmlBuilder.AppendLine('  <WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">')
        [void]$xmlBuilder.AppendLine('   <FreezePanes/>')
        [void]$xmlBuilder.AppendLine('   <FrozenNoSplit/>')
        [void]$xmlBuilder.AppendLine('   <SplitHorizontal>1</SplitHorizontal>')
        [void]$xmlBuilder.AppendLine('   <TopRowBottomPane>1</TopRowBottomPane>')
        [void]$xmlBuilder.AppendLine('  </WorksheetOptions>')
        [void]$xmlBuilder.AppendLine(' </Worksheet>')
        [void]$xmlBuilder.AppendLine('</Workbook>')

        if (Test-Path $ExcelFile) {
            Remove-Item -Path $ExcelFile -Force
        }

        [System.IO.File]::WriteAllText($ExcelFile, $xmlBuilder.ToString(), [System.Text.Encoding]::UTF8)

        if (-not (Test-Path $ExcelFile)) {
            throw "Excel-compatible file was not created."
        }

        if ((Get-Item $ExcelFile).Length -eq 0) {
            throw "Excel-compatible file is empty."
        }

        Write-Step "Excel-compatible report created successfully: $ExcelFile" "Green"

        return $true
    }
    catch {
        Write-Step "ERROR creating formatted Excel-compatible report" "Red"
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }
}

################################################################################
# MAIN
################################################################################

$scriptFailed = $false
$downloadedFiles = @()
$consolidatedCsvFile = $null
$consolidatedExcelFile = $null

try {
    Write-Step "Starting vROps uptime extraction..." "Cyan"

    Invoke-VROpsRetentionCleanup `
        -Folders @($extractFolder, $consolidatedFolder) `
        -DaysToKeep $retentionDays

    foreach ($target in $vropsTargets) {
        Write-Step "Processing $($target.Name) - $($target.Url)" "Cyan"

        $storedCred = Get-StoredCredential -CredentialFile $target.CredentialFile
        $username = $storedCred.UserName
        $password = $storedCred.GetNetworkCredential().Password

        $token = Get-VROpsToken `
            -VropsUrl $target.Url `
            -Username $username `
            -Password $password `
            -AuthSource $target.AuthSource

        if (Test-IsBlank $token) {
            throw "Token generation failed for $($target.Name)"
        }

        Write-Step "Token acquired successfully for $($target.Name)" "Green"

        $resourceId = $target.ResourceId

        if (Test-IsBlank $resourceId) {
            $resourceId = Get-VROpsResourceId `
                -VropsUrl $target.Url `
                -Token $token `
                -ResourceName $target.ResourceName
        }

        if (Test-IsBlank $resourceId) {
            throw "ResourceId not found for $($target.Name)."
        }

        Write-Step "Using ResourceId=$resourceId for $($target.Name)" "Green"

        $reportId = Start-VROpsReportRun `
            -VropsUrl $target.Url `
            -Token $token `
            -ReportDefinitionId $target.ReportDefinitionId `
            -ResourceId $resourceId

        if (Test-IsBlank $reportId) {
            throw "Report execution failed for $($target.Name)"
        }

        Write-Step "Report started for $($target.Name). ReportId=$reportId" "Green"

        $completed = Wait-VROpsReportComplete `
            -VropsUrl $target.Url `
            -Token $token `
            -ReportId $reportId

        if (-not $completed) {
            throw "Report did not complete for $($target.Name)"
        }

        $csvFile = Join-Path $extractFolder "$($target.Name)-$(Get-Date -Format yyyy-MM-dd).csv"

        $downloaded = Download-VROpsReportCsv `
            -VropsUrl $target.Url `
            -Token $token `
            -ReportId $reportId `
            -OutputFile $csvFile

        if (-not $downloaded) {
            throw "CSV download failed for $($target.Name)"
        }

        Write-Step "CSV downloaded for $($target.Name): $csvFile" "Green"
        $downloadedFiles += $csvFile
    }

    Write-Step "Merging CSV files..." "Cyan"

    $merged = @()

    foreach ($file in $downloadedFiles) {
        $sourceName = ([System.IO.Path]::GetFileNameWithoutExtension($file) -split "-")[0]

        $rows = @(Import-Csv -Path $file)

        foreach ($row in $rows) {
            $row | Add-Member -MemberType NoteProperty -Name "vROpsSource" -Value $sourceName -Force
            $merged += $row
        }
    }

    $dateStamp = Get-Date -Format yyyy-MM-dd

    $consolidatedCsvFile = Join-Path $consolidatedFolder "Consolidated_Uptime_$dateStamp.csv"
    $consolidatedExcelFile = Join-Path $consolidatedFolder "Consolidated_Uptime_$dateStamp.xls"

    $merged | Export-Csv -Path $consolidatedCsvFile -NoTypeInformation -Encoding UTF8

    if (-not (Test-Path $consolidatedCsvFile)) {
        throw "Consolidated CSV file was not created."
    }

    Write-Step "Consolidated CSV report saved: $consolidatedCsvFile" "Green"

    $excelCreated = Convert-ConsolidatedCsvToFormattedExcel `
        -CsvFile $consolidatedCsvFile `
        -ExcelFile $consolidatedExcelFile

    if (-not $excelCreated) {
        throw "Formatted Excel-compatible report was not created."
    }

    if (-not (Test-Path $consolidatedExcelFile)) {
        throw "Formatted Excel-compatible report file not found after creation."
    }

    Write-Step "Sending email..." "Cyan"

    Send-MailMessage `
        -To $emailTo `
        -From $emailFrom `
        -Subject "Connected Payments - Daily Consolidated vROps Uptime Report - $(Get-Date -Format 'yyyy-MM-dd')" `
        -Body "Attached is the daily consolidated vROps uptime report for Connected Payments.`nPlease reach out to Sundaram Gaur (SG185523) (Sundaram.Gaur@ncrvoyix.com) for any issues related to the report.`n`n~Automated Email" `
        -Attachments $consolidatedExcelFile `
        -SmtpServer $smtpServer `
        -Port $smtpPort `
        -ErrorAction Stop

    Write-Step "Email sent successfully." "Green"
    Write-Step "ALL TASKS COMPLETED SUCCESSFULLY." "Green"
}
catch {
    $scriptFailed = $true

    Write-Step "SCRIPT FAILED" "Red"
    Write-Host $_.Exception.Message -ForegroundColor Red

    try {
        Send-MailMessage `
            -To $emailTo `
            -From $emailFrom `
            -Subject "FAILED - Connected Payments - Daily Consolidated vROps Uptime Report - $(Get-Date -Format 'yyyy-MM-dd')" `
            -Body "The vROps consolidated uptime report script failed.`n`nError:`n$($_.Exception.Message)`n`nLog file:`n$logFile" `
            -SmtpServer $smtpServer `
            -Port $smtpPort `
            -ErrorAction SilentlyContinue
    }
    catch {}
}
finally {
    Stop-Transcript | Out-Null

    if ($scriptFailed) {
        exit 1
    }
    else {
        exit 0
    }
}