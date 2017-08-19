# Inspired by Unix's `od` utility.
function Convert-Bytes
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [byte[]] $Input,

        [ValidateSet('ASCII', 'Binary', 'Hex', 'Octal')]
        [string] $To = 'Hex'
    )

    process
    {
        switch ($To)
        {
            'ASCII' { ($Input | ForEach-Object { [Convert]::ToChar($_) }) }
            'Binary' { ($Input | ForEach-Object { ([Convert]::ToString($_, 2)).PadLeft(8, '0') }) }
            'Hex' { ($Input | ForEach-Object { ([Convert]::ToString($_, 16)).PadLeft(2, '0') }) } 
            'Octal' { ($Input | ForEach-Object { [Convert]::ToString($_, 3) }) }
        }
    }
}
