function Get-DayDescriptor([DateTime] $Day = (Get-Date))
{
    return $Day.ToString('yyyy-MM-dd')
}

function Get-TimeManagementFilePath([string] $DayDescriptor)
{
    $dayFile = "${DayDescriptor}.txt"
    $dayFilePath = Join-Path $TIMEMANAGEMENT_BLOCK_FOLDER $dayFile
    return $dayFilePath
}

function Get-TimeManagementData([string] $DayDescriptor = (Get-DayDescriptor))
{
    $path = Get-TimeManagementFilePath $DayDescriptor
    if (Test-Path $path)
    {
        return New-Object System.Collections.ArrayList -ArgumentList @(,@(Get-Content -Path $path -Encoding UTF8 | ConvertFrom-Json))
    }
    else
    {
        return $null
    }
}

function Save-TimeManagementData([object] $Data, [string] $DayDescriptor = (Get-DayDescriptor))
{
    $path = Get-TimeManagementFilePath $DayDescriptor

    # Using -InputObject directly prevents enumeration - even if 1 element we want to store as array
    $dataJson = ConvertTo-Json -Depth 99 -InputObject $Data
    $dataJson | Set-Content -Path $path -Encoding UTF8 -Force
}

function Format-Time([int] $Hour, [int] $Minute)
{
    "$($Hour.ToString('00')):$($Minute.ToString('00'))"
}

function Validate-TimeRange([int] $StartHour, [int] $StartMinute, [int] $EndHour, [int] $EndMinute)
{
    if ($StartHour -gt 23 -or $StartHour -lt 0)
    {
        return @{ Success = $false; Message = "invalid start hour (${StartHour})" }
    }
    elseif ($StartMinute -gt 59 -or $StartMinute -lt 0)
    {
        return @{ Success = $false; Message = "invalid start minute (${StartMinute})" }
    }
    elseif ($EndHour -gt 23 -or $EndHour -lt 0)
    {
        return @{ Success = $false; Message = "invalid end hour (${EndHour})" }
    }
    elseif ($EndMinute -gt 59 -or $EndMinute -lt 0)
    {
        return @{ Success = $false; Message = "invalid end minute (${EndMinute})" }
    }

    $timeModeResult = Validate-TimeMode $StartHour $StartMinute $EndHour $EndMinute
    return $timeModeResult
}

function New-Time([int] $Hour, [int] $Minute)
{
    @{ Hour = $Hour; Minute = $Minute }
}

function Validate-TimeMode([int] $StartHour, [int] $StartMinute, [int] $EndHour, [int] $EndMinute)
{
    $24HourMode = $StartHour -gt 12 -or $EndHour -gt 12 -or $StartHour -eq 0 -or $EndHour -eq 0
    if ($24HourMode -and ($StartHour -gt $EndHour -or ($StartHour -eq $EndHour -and $StartMinute -gt $EndMinute)))
    {
        return @{ Success = $false; Message = "start time is after end time ($(Format-Time $StartHour $StartMinute) >= $(Format-Time $EndHour $EndMinute))" }
    }
    elseif ($24HourMode)
    {
        return @{ Success = $true; Start = @{ Hour = $StartHour; Minute = $StartMinute }; End = @{ Hour = $EndHour; Minute = $EndMinute } }
    }
    else
    {
        $stdMinStartHour,$stdMaxEndHour = 7, 6 # i.e. it would be unexpected to have a blocker before 7 AM or after 6 PM
        if ($StartHour -gt $EndHour) # e.g. 11-1 -> 11AM - 1PM (we don't expect blockers to go overnight)
        {
            return @{ Success = $true; Start = New-Time $StartHour $StartMinute; End = New-Time (($EndHour + 12) % 24) $EndMinute }
        }
        elseif ($StartHour -ge $stdMinStartHour) # e.g. 8-11 -> 8AM - 11AM
        {
            return @{ Success = $true; Start = New-Time $StartHour $StartMinute; End = New-Time $EndHour $EndMinute }
        }
        elseif ($EndHour -le $stdMaxEndHour) # e.g. 3-4 -> 3PM - 4PM
        {
            return @{ Success = $true; Start = New-Time (($StartHour + 12) % 24) $StartMinute; End = New-Time (($EndHour + 12) % 24) $EndMinute }
        }
        else # e.g. 3-9 -> no obvious tell if that's 3PM - 9PM or 3AM - 9AM
        {
            return @{ Success = $false; Message = "could not determine AM/PM for time period ($(Format-Time $StartHour $StartMinute)-$(Format-Time $EndHour $EndMinute))" }
        }
    }
}

function Parse-TimeDescriptor([string] $Descriptor)
{
    # 09:00-10:00
    # 9-10
    # 12-4
    # 13-16

    $m = [Regex]::Match($Descriptor, '^(\d{1,2})(:\d{2})?\s*-\s*(\d{1,2})(:\d{1,2})?$')
    if (-not $m.Success)
    {
        return $null
    }

    $startHour = [int]::Parse($m.Groups[1].Value)
    if ($m.Groups[2].Success)
    {
        $startMinute = [int]::Parse($m.Groups[2].Value.TrimStart(':'))
    }
    else
    {
        $startMinute = 0
    }

    $endHour = [int]::Parse($m.Groups[3].Value)
    if ($m.Groups[4].Success)
    {
        $endMinute = [int]::Parse($m.Groups[4].Value.TrimStart(':'))
    }
    else
    {
        $endMinute = 0
    }

    $result = Validate-TimeRange $startHour $startMinute $endHour $endMinute
    if (-not $result.Success)
    {
        throw "Failed to parse time descriptor: $($result.Message)"
    }

    return @{ Start = $result.Start; End = $result.End }
}

function New-TimeBlockData()
{
    New-Object System.Collections.ArrayList
}

function Add-TimeBlock([object] $CurrentData, [object] $Block)
{
    $null = $CurrentData.Add($Block)
}

###################
# Public functions
###################

function Get-TimeBlock
{
    [CmdletBinding(DefaultParameterSetName='dayString')]
    param (
        [Parameter(ParameterSetName='dayString')]
        [string] $DayString,

        [Parameter(ParameterSetName='dayDateTime')]
        [DateTime] $DayDateTime
    )

    if ($PSCmdlet.ParameterSetName -eq 'dayString')
    {
        $DayString = $DayString.Trim()
        if ([string]::IsNullOrWhiteSpace($DayString))
        {
            $DayString = Get-DayDescriptor
        }
        elseif ($DayString -notmatch '^\d\d\d\d-(0[1-9]|1[0-2])-(0[1-9]|1\d|2\d|3[01])$')
        {
            throw "Invalid day descriptor given: ${DateString}"
        }
    }
    else
    {
        $DayString = Get-DayDescriptor $DayDate
    }

    Get-TimeManagementData $DayString
}

function New-TimeBlock
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=1)]
        [string] $Descriptor,

        [Parameter(Mandatory, Position=2)]
        [string] $Principal,

        [Parameter(Position=3)]
        [string] $BlockDescription
    )

    $blocks = Get-TimeManagementData
    if ($null -eq $blocks)
    {
        $blocks = New-TimeBlockData
    }

    $newBlock = Parse-TimeDescriptor $Descriptor
    $newBlock.Principal = $Principal
    if ($BlockDescription)
    {
        $newBlock.Description = $BlockDescription
    }
    Add-TimeBlock $blocks $newBlock
    Save-TimeManagementData $blocks
}

New-Alias -Name ntb -Value New-TimeBlock
New-Alias -Name gtb -Value Get-TimeBlock