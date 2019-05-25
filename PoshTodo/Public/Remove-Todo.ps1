<#
    .SYNOPSIS
        Removes the given todo item.

    .DESCRIPTION
        Removes the given todo item from the given list. Throws if list name
        is provided but doesn't exist, but will not throw if index is invalid
        or if the list object is provided and it isn't persisted. In either
        case a warning will be written.

    .PARAMETER Item
        Todo item to be removed. No other arguments need to be provided.

    .PARAMETER Number
        Number of the todo item to be removed. Must be provided with -ListName
        or -List.

    .PARAMETER ListName
        Name of the list whose todo item should be removed. Must be provided
        with -Number.

    .PARAMETER List
        List object whose todo item should be removed. Must be provided with -Number.

    .INPUTS

#>
function Remove-Todo
{
    [CmdletBinding(DefaultParameterSetName='byListName')]
    param (
        [Parameter(ParameterSetName='byItem', ValueFromPipeline)]
        [Todo] $Item,

        [Parameter(ParameterSetName='byListName')]
        [Parameter(ParameterSetName='byList')]
        [int] $Number,

        [Parameter(ParameterSetName='byListName')]
        [string] $ListName = 'Default',

        [Parameter(ParameterSetName='byList', ValueFromPipeline)]
        [TodoList] $List
    )

    process
    {
        $updatedList = $false
        if ($PSCmdlet.ParameterSetName -eq 'byItem')
        {
            $List = GetLists | Where-Object Name -eq $Item.ParentListName | Select-Object -First 1
            if ($List)
            {
                $updatedList = $List.RemoveItem($Item)
            }
        }
        else
        {
            if ($PSCmdlet.ParameterSetName -eq 'byListName')
            {
                $nameArr = @($ListName)
                $List = GetListsByName($nameArr)
            }

            $updatedList = $List.RemoveItemAt($Number)
        }

        if (-not (ListExists($List.Name)) -and $updatedList)
        {
            Write-Warning "List with name '$($List.Name)' not found in todo list repository; changes will not be persisted"
        }
        elseif ($updatedList)
        {
            UpdateList($List)
        }
    }
}