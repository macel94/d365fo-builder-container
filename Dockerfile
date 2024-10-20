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
COPY SQL2022-SSEI-Dev.exe /

WORKDIR /

RUN Start-Process -Wait -FilePath .\SQL2022-SSEI-Dev.exe -ArgumentList /qs, /x:setup ; \
        .\setup\setup.exe /q /ACTION=Install /INSTANCENAME=MSSQLSERVER /FEATURES=SQLEngine /UPDATEENABLED=0 /SQLSVCACCOUNT='NT AUTHORITY\NETWORK SERVICE' /SQLSYSADMINACCOUNTS='BUILTIN\ADMINISTRATORS' /TCPENABLED=1 /NPENABLED=0 /IACCEPTSQLSERVERLICENSETERMS ; \
        Remove-Item -Recurse -Force SQL2022-SSEI-Dev.exe, setup

RUN stop-service MSSQLSERVER ; \
        set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql16.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -name tcpdynamicports -value '' ; \
        set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql16.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -name tcpport -value 1433 ; \
        set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql16.MSSQLSERVER\mssqlserver\' -name LoginMode -value 2 ;

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
CMD .\start-sql.ps1 -sa_password $env:sa_password -ACCEPT_EULA $env:ACCEPT_EULA -attach_dbs \"$env:attach_dbs\" -Verbose; \
    .\configure-agent.ps1 -PAT $env:PAT -ORGANIZATIONURL $env:ORGANIZATIONURL -POOL $env:POOL -Verbose
