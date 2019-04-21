[CmdletBinding()]
param (
    [ValidateScript({ $_ -and (Test-Path $_) })]
    [Parameter(Mandatory)]
    [string] $ModulePath
)

$moduleName = Split-Path -Path $ModulePath -Leaf
& powershell -NoProfile -NoLogo -NoExit -Command @"
&{
    Import-Module -Force '$ModulePath'
    if (-not `$?)
    {
        exit
    }
    `$global:old_prompt = (Get-Command prompt).ScriptBlock
    Set-Item Function:\prompt -Value {
        Write-Host -ForegroundColor Green -NoNewLine -Object `"[$moduleName] `"
        `$global:old_prompt.Invoke()
    }
}
"@
