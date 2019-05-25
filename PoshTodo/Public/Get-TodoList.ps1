<#
    .SYNOPSIS
        Returns existing todo lists

    .DESCRIPTION
        Returns existing todo lists.

    .PARAMETER Name
        Name(s) of the list(s) to return. If no such list exists with any of the values,
        then an exception is thrown.

    .OUTPUTS
        Lists matching the given name(s), or all lists.

    .EXAMPLE
        Get-TodoList

        Return all todo lists.

    .EXAMPLE
        Get-TodoList -Name 'Foo','Bar'

        Return the todo lists with names 'Foo' and 'Bar'. Throw if they do not exist.
#>
function Get-TodoList
{
    [CmdletBinding()]
    param (
        [string[]] $Name
    )

    process
    {
        if ($Name)
        {
            $nameArr = @($Name)
            GetListsByName($nameArr)
        }
        else
        {
            GetLists
        }
    }
}