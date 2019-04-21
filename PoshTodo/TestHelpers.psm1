function Assert-TodoInResults
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Todo[]] $Results,
        
        [Parameter(ValueFromPipeline)]
        [Todo] $Item
    )

    process
    {
        $actual = $results | Where-Object Description -eq $Item.Description
        $actual | Should -Not -BeNull
        $actual.Tags.Length | Should -BeExactly $Item.Tags.Length
        foreach ($tag in $Item.Tags)
        {
            $actualTag = $actual.Tags | Where-Object { $_ -eq $tag }
            $actualTag | Should -Not -BeNull
        }
    }
}

function Assert-TodoNotInResults
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Todo[]] $Results,
        
        [Parameter(ValueFromPipeline)]
        [Todo] $Item
    )

    process
    {
        $exists = $false
        $actual = $results | Where-Object Description -eq $Item.Description
        if ($null -ne $actual -and $Item.Tags.Length -eq $actual.Tags.Length)
        {
            foreach ($tag in $Item.Tags)
            {
                $actualTag = $actual.Tags | Where-Object { $_ -eq $tag }
                if ($null -eq $actualTag)
                {
                    $exists = $true
                }
            }
        }
        $exists | Should -BeFalse
    }
}

function Assert-TagsMatch
{
    param (
        [Parameter(Mandatory)]
        [string[]] $Expected,

        [Parameter(Mandatory)]
        [string[]] $Actual
    )

    $Actual.Length | Should -BeExactly $Expected.Length
    for ($i = 0; $i -lt $Actual.Length; $i += 1)
    {
        $Actual[$i] | Should -BeExactly $Expected[$i]
    }
}

function Assert-ItemMatches
{
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Todo] $Item,

        [int] $Number,

        [string] $Description,

        [string] $Status,

        [string[]] $Tags
    )

    process
    {
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Number'))
        {
            $Item.Number | Should -BeExactly $Number
        }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Description'))
        {
            $Item.Description | Should -BeExactly $Description
        }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Status'))
        {
            $Item.Status | Should -BeExactly $Status
        }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Tags'))
        {
            Assert-TagsMatch -Expected $Tags -Actual $Item.Tags
        }
    }
}