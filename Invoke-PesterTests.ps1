param (
    [Parameter(Mandatory)]
    [string] $TestPath,

    [string] $TestName
)

if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('TestName'))
{
    & powershell.exe -NoProfile -NoLogo -Command "Invoke-Pester -Script '$TestPath' -TestName '$TestName'"
}
else
{
    & powershell.exe -NoProfile -NoLogo -Command "Invoke-Pester -Script '$TestPath'"
}
