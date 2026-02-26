<#
.SYNOPSIS
    Configuration and Session Management for Sentinel Manager
.DESCRIPTION
    Provides configuration settings, session state management, and schema templates
    for Microsoft Sentinel operations.
.VERSION
    3.0
#>

#region Configuration

# Global configuration settings
$script:Config = @{
    ApiVersion = "2023-01-01-preview"
    ApiVersionRetention = "2025-02-01"
    ApiVersionWorkbooks = "2023-06-01"  # Using latest stable API
    ApiVersionAnalyticsRules = "2025-09-01"  # For alert rule templates (latest)
    ApiVersionContentTemplates = "2024-09-01"  # For Content Hub filtering
    ManagementApiUrl = "https://management.azure.com"
    DebugMode = $false
}

# Session state (subscription, workspace, token, etc.)
$script:Session = @{
    SubscriptionId = $null
    SubscriptionName = $null
    ResourceGroup = $null
    WorkspaceName = $null
    WorkspaceId = $null  # CustomerId (GUID) of the workspace, used for KQL queries
    AuthToken = $null
    UseAzModule = $false
    DiscoveredSettingsApiVersion = $null  # Cache for Settings API version (performance optimization)
}

#endregion

#region Schema Templates

$script:SchemaTemplates = @{
    "Syslog" = @{
        Description = "Syslog Daten (CEF/Syslog Format)"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="Computer"; type="string"},
            @{name="EventTime"; type="datetime"},
            @{name="Facility"; type="string"},
            @{name="HostName"; type="string"},
            @{name="SeverityLevel"; type="string"},
            @{name="SyslogMessage"; type="string"},
            @{name="ProcessID"; type="int"},
            @{name="HostIP"; type="string"},
            @{name="ProcessName"; type="string"},
            @{name="MG"; type="guid"},
            @{name="CollectorHostName"; type="string"}
        )
    }
    "CommonSecurityLog" = @{
        Description = "CEF Common Security Log"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="Computer"; type="string"},
            @{name="DeviceVendor"; type="string"},
            @{name="DeviceProduct"; type="string"},
            @{name="DeviceVersion"; type="string"},
            @{name="DeviceEventClassID"; type="string"},
            @{name="DeviceName"; type="string"},
            @{name="DeviceAction"; type="string"},
            @{name="SourceIP"; type="string"},
            @{name="DestinationIP"; type="string"},
            @{name="RequestURL"; type="string"},
            @{name="Protocol"; type="string"}
        )
    }
    "SecurityEvent" = @{
        Description = "Windows Security Events (Event ID Format)"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="Computer"; type="string"},
            @{name="EventID"; type="int"},
            @{name="EventLog"; type="string"},
            @{name="ProviderName"; type="string"},
            @{name="Level"; type="string"},
            @{name="Channel"; type="string"},
            @{name="Message"; type="string"}
        )
    }
    "DNSActivityLogs" = @{
        Description = "DNS Activity Logs (ASIM DNS Schema)"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="DnsQuery"; type="string"},
            @{name="QueryType"; type="string"},
            @{name="ResponseCode"; type="string"},
            @{name="SrcIpAddr"; type="string"},
            @{name="DstIpAddr"; type="string"},
            @{name="DstHostname"; type="string"}
        )
    }
    "WebActivityLogs" = @{
        Description = "Web/HTTP Activity Logs"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="Computer"; type="string"},
            @{name="SrcIpAddr"; type="string"},
            @{name="DstIpAddr"; type="string"},
            @{name="RequestUrl"; type="string"},
            @{name="HttpMethod"; type="string"},
            @{name="HttpStatusCode"; type="int"},
            @{name="UserAgent"; type="string"}
        )
    }
    "AuthenticationLogs" = @{
        Description = "Authentication Events"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="UserId"; type="string"},
            @{name="UserName"; type="string"},
            @{name="AuthenticationMethod"; type="string"},
            @{name="AuthenticationSuccessful"; type="boolean"},
            @{name="SourceIP"; type="string"},
            @{name="ResultDescription"; type="string"}
        )
    }
    "ProcessEvents" = @{
        Description = "Process Creation Events"
        Columns = @(
            @{name="SourceSystem"; type="string"},
            @{name="TimeGenerated"; type="datetime"},
            @{name="Computer"; type="string"},
            @{name="ProcessName"; type="string"},
            @{name="ProcessID"; type="int"},
            @{name="ParentProcessID"; type="int"},
            @{name="ParentProcessName"; type="string"},
            @{name="CommandLine"; type="string"},
            @{name="UserName"; type="string"}
        )
    }
}

#endregion

#region Accessor Functions

function Get-SentinelConfig {
    <#
    .SYNOPSIS
        Gets the current configuration
    .RETURN
        Configuration hashtable
    #>
    return $script:Config
}

function Get-SentinelSession {
    <#
    .SYNOPSIS
        Gets the current session state
    .RETURN
        Session hashtable
    #>
    return $script:Session
}

function Get-SchemaTemplates {
    <#
    .SYNOPSIS
        Gets available schema templates
    .RETURN
        Schema templates hashtable
    #>
    return $script:SchemaTemplates
}

function Set-DebugMode {
    <#
    .SYNOPSIS
        Enables or disables debug mode
    .PARAMETER Enabled
        True to enable, False to disable
    #>
    param([bool]$Enabled)
    $script:Config.DebugMode = $Enabled
}

#endregion

#region Export Module Members

