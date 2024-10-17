# SQL Server 2019 Windows container dockerfile
## Warning: Restarting windows container causes the machine key to change and hence if you have any encryption configured then restarting SQL On Windows containers
## breaks the encryption key chain in SQL Server. 

# Download the SQL Developer from the following location  https://go.microsoft.com/fwlink/?linkid=866662 and extract the .box and .exe files using the option: "Download Media"

FROM mcr.microsoft.com/windows/servercore:ltsc2019

ENV sa_password="_" \
    attach_dbs="[]" \
    ACCEPT_EULA="_" \
    sa_password_path="C:\ProgramData\Docker\secrets\sa-password" \
    PAT="_" \
    ORGANIZATIONURL="_" \
    AGENT_DIR="C:\azagent"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# make install files accessible
COPY start.ps1 /
COPY SQLServer2019-DEV-x64-ENU.box /
COPY SQLServer2019-DEV-x64-ENU.exe /
COPY SQLServer2019-DEV-x64-ENU /

WORKDIR /

RUN Start-Process -Wait -FilePath .\SQLServer2019-DEV-x64-ENU.exe -ArgumentList /qs, /x:setup ; \
        .\setup\setup.exe /q /ACTION=Install /INSTANCENAME=MSSQLSERVER /FEATURES=SQLEngine /UPDATEENABLED=0 /SQLSVCACCOUNT='NT AUTHORITY\NETWORK SERVICE' /SQLSYSADMINACCOUNTS='BUILTIN\ADMINISTRATORS' /TCPENABLED=1 /NPENABLED=0 /IACCEPTSQLSERVERLICENSETERMS ; \
        Remove-Item -Recurse -Force SQLServer2019-DEV-x64-ENU.exe, SQLServer2019-DEV-x64-ENU.box, setup

RUN stop-service MSSQLSERVER ; \
        set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql15.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -name tcpdynamicports -value '' ; \
        set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql15.MSSQLSERVER\mssqlserver\supersocketnetlib\tcp\ipall' -name tcpport -value 1433 ; \
        set-itemproperty -path 'HKLM:\software\microsoft\microsoft sql server\mssql15.MSSQLSERVER\mssqlserver\' -name LoginMode -value 2 ;

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
CMD .\start -sa_password $env:sa_password -ACCEPT_EULA $env:ACCEPT_EULA -attach_dbs \"$env:attach_dbs\" -Verbose; \
    .\configure-agent.ps1 -PAT $env:PAT -ORGANIZATIONURL $env:ORGANIZATIONURL -POOL $env:POOL -Verbose