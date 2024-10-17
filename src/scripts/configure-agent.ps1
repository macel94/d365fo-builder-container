param (
    [string]$PAT,
    [string]$ORGANIZATIONURL,
    [string]$POOL
)

$agentDir = $env:AGENT_DIR
cd $agentDir

# Configuring the agent with the passed PAT and ORGANIZATION URL
& .\config.cmd --unattended --url $ORGANIZATIONURL --auth pat --token $PAT --pool $POOL --agent $(hostname)

# Run the agent
& .\run.cmd
