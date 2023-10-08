$global:TIMEMANAGEMENT_BLOCK_FOLDER = Join-Path $env:USERPROFILE '.time-management'
if (-not (Test-Path $TIMEMANAGEMENT_BLOCK_FOLDER))
{
    Write-Warning "TimeManagement folder not found at ${TIMEMANAGEMENT_BLOCK_FOLDER}; creating"
    $null = New-Item -ItemType Directory -Path $TIMEMANAGEMENT_BLOCK_FOLDER
}