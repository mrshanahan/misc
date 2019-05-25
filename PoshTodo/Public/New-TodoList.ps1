<#
    .SYNOPSIS
        Creates a new todo list

    .DESCRIPTION
        Creates a new todo list with the given name and description. Raises an error
        if a list with the same name already exists.

    .PARAMETER Name
        Name(s) of the list(s) to create. If multiple values are provided a new list
        will be created for each value.

    .PARAMETER Description
        Description of the list(s) to create. If multiple values are provided for Name,
        then each list will have the same description.

    .PARAMETER PassThru
        If provided, returns the list(s).

    .OUTPUTS
        The created list object(s) if -PassThru is provided.

    .EXAMPLE
        New-TodoList -Name 'Groceries'

        Creates a new list called 'Groceries'.

    .EXAMPLE
        New-TodoList -Name 'Foo','Bar' -Description 'Some cool new lists'

        Creates two new lists, 'Foo' and 'Bar', both with the given description.
#>
function New-TodoList
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]] $Name,

        [string] $Description,

        [switch] $PassThru
    )

    process
    {
        foreach ($n in $Name)
        {
            if (ListExists($n))
            {
                Write-Error "List with name $n already exists"
            }
            else
            {
                $list = New-Object TodoList($n, $Description)
                AddList($list)
        
                if ($PassThru)
                {
                    $list
                }
            }
        }
    }
}