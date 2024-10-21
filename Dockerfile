# SQL Server 2019 Windows container dockerfile
## Warning: Restarting windows container causes the machine key to change and hence if you have any encryption configured then restarting SQL On Windows containers
## breaks the encryption key chain in SQL Server. 

FROM mcr.microsoft.com/windows/servercore:ltsc2022

ENV sa_password="_" \
    attach_dbs="[]" \
    ACCEPT_EULA="_" \
    sa_password_path="C:\ProgramData\Docker\secrets\sa-password" \
    PAT="_" \
    ORGANIZATIONURL="_" \
    AGENT_DIR="C:\azagent" \
    POOL="windows-containers" \
    EXE="https://go.microsoft.com/fwlink/p/?linkid=2215158&clcid=0x409&culture=en-us&country=us"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# make install files accessible
COPY src/scripts/start-sql.ps1 /

WORKDIR /

# Download SQL Server 2022 using the EXE link
RUN Invoke-WebRequest -Uri $env:EXE -OutFile SQL2022-SSEI-Dev.exe

# Install SQL Server directly without extraction and log the process
RUN & { \
    .\SQL2022-SSEI-Dev.exe '/ACTION=Install', '/INSTANCENAME=MSSQLSERVER', '/FEATURES=SQLEngine', '/UPDATEENABLED=0', '/SQLSVCACCOUNT=NT AUTHORITY\NETWORK SERVICE', '/SQLSYSADMINACCOUNTS=BUILTIN\ADMINISTRATORS', '/TCPENABLED=1', '/NPENABLED=0', '/IACCEPTSQLSERVERLICENSETERMS', '/QS', '/INDICATEPROGRESS', '/ERRORREPORTING=1', '/SECURITYMODE=SQL' > ./install_log.txt 2> ./install_error_log.txt; \
    if (Test-Path ./install_log.txt) { \
        $logContent = Get-Content ./install_log.txt; \
        if ($logContent) { \
            Write-Host $logContent; \
        } else { \
            Write-Host 'Log file is empty.'; \
        } \
    } else { \
        Write-Host 'Log file not found.'; \
    }; \
    if (Test-Path ./install_error_log.txt) { \
        $errorContent = Get-Content ./install_error_log.txt; \
        if ($errorContent) { \
            Write-Host $errorContent; \
        } else { \
            Write-Host 'Error log file is empty.'; \
        } \
    } else { \
        Write-Host 'Error log file not found.'; \
    }; \
    Remove-Item -Recurse -Force SQL2022-SSEI-Dev.exe, ./install_log.txt, ./install_error_log.txt \
}

# Wait for SQL Server service to be created, then start it
RUN $serviceName = 'MSSQLSERVER'; \
    Write-Host 'Waiting for SQL Server service to be available...'; \
    $attempt = 0; \
    while (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) -and $attempt -lt 20) { \
        Start-Sleep -Seconds 10; \
        $attempt++; \
        Write-Host ('Attempt ' + $attempt + ' - Waiting for ' + $serviceName + ' service...'); \
    }; \
    if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) { \
        Write-Host ('SQL Server service ' + $serviceName + ' not found. Attempting to start manually...'); \
        Start-Service -Name $serviceName; \
        Start-Sleep -Seconds 10; \
        if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) { \
            Write-Host ('SQL Server service ' + $serviceName + ' still not available. Exiting...'); \
            exit 1; \
        } \
    }

# Stop SQL Server and configure ports
RUN Stop-Service MSSQLSERVER ; \
    Set-ItemProperty -Path 'HKLM:\software\microsoft\microsoft sql server\mssql16.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -Name tcpdynamicports -Value ''; \
    Set-ItemProperty -Path 'HKLM:\software\microsoft\microsoft sql server\mssql16.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -Name tcpport -Value 1433; \
    Set-ItemProperty -Path 'HKLM:\software\microsoft\microsoft sql server\mssql16.MSSQLSERVER\mssqlserver\' -Name LoginMode -Value 2;

# Install Visual Studio Community 2022
RUN Invoke-WebRequest -Uri https://aka.ms/vs/22/release/vs_community.exe -OutFile vs_installer.exe; \
    Start-Process -Wait -FilePath .\vs_installer.exe -ArgumentList '--quiet', '--wait', '--add', 'Microsoft.VisualStudio.Workload.ManagedDesktop', '--includeRecommended', '--includeOptional'; \
    Remove-Item -Force vs_installer.exe

# Set up entry point for configuring the DevOps agent at runtime
COPY configure-agent.ps1 /configure-agent.ps1

# Download and extract the Azure DevOps Agent
RUN Invoke-WebRequest -Uri https://vstsagentpackage.azureedge.net/agent/3.220.1/vsts-agent-win-x64-3.220.1.zip -OutFile agent.zip; \
    Expand-Archive -Path agent.zip -DestinationPath $env:AGENT_DIR; \
    Remove-Item -Force agent.zip

HEALTHCHECK CMD [ "sqlcmd", "-Q", "select 1" ]

# Set up container start script
CMD .\start-sql.ps1 -sa_password $env:sa_password -ACCEPT_EULA $env:ACCEPT_EULA -attach_dbs "$env:attach_dbs" -Verbose; \
    .\configure-agent.ps1 -PAT $env:PAT -ORGANIZATIONURL $env:ORGANIZATIONURL -POOL $env:POOL -Verbose
