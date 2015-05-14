# Simple, dumb pseudo-implementation of *nix's `du` command.
param (
    [string]$BaseFile=".",
    [switch]$B,
    [switch]$KB,
    [switch]$MB,
    [switch]$GB
)
if (!(Test-Path $BaseFile)) {
    Write-Error "Could not find file $BaseFile"
    Exit -1
}
if (!($B -or $KB -or $MB -or $GB)) {
    $B = $true
}
$bytes = (ls -Recurse $BaseFile | Measure-Object -Property Length -Sum).Sum
$properties = @{'Base'=$BaseFile}

# Using Add-Member here instead of a property dictionary so that properties are kept in order
$retVal = New-Object -TypeName PSObject
$retVal | Add-Member -MemberType NoteProperty -Name Base -Value $BaseFile
if ($B) {
    $retVal | Add-Member -MemberType NoteProperty -Name B -Value $bytes
}
if ($KB) {
    $retVal | Add-Member -MemberType NoteProperty -Name KB -Value ($bytes / 1024)    
}
if ($MB) {
    $retVal | Add-Member -MemberType NoteProperty -Name MB -Value ($bytes / (1024*1024))
}
if ($GB) {
    $retVal | Add-Member -MemberType NoteProperty -Name GB -Value ($bytes / (1024*1024*1024))    
}
return $retVal
