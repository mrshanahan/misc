<#
    .SYNOPSIS
        Sets the working todo list.

    .DESCRIPTION
        Sets the working todo list (i.e. the one that is used by default)
        to be the specified list. The working todo list will be used by
        default for any actions that refer to todo list items.

    .INPUTS
        The TodoList to set as the working list. You may pipe in multiple
        values to this function, but note that the last list processed
        will be set as the working list once the function completes.
#>
function Set-WorkingTodoList
{
    [CmdletBinding(DefaultParameterSetName='byListName')]
    param (
        [Parameter(ParameterSetName='byListName')]
        [string] $ListName,

        [Parameter(ParameterSetName='byList', ValueFromPipeline)]
        [TodoList] $List
    )

    process
    {
        if (-not $List)
        {
            $nameArr = @($ListName)
            $List = GetListsByName($nameArr)
        }

        SetWorkingList($List.Name)
    }
}