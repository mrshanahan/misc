<#
    .SYNOPSIS
        Reorders a given todo item

    .DESCRIPTION
        Reorders todos within a list. Will work successfully given a valid list
        object and valid number, even if that list only exists in-memory. Attempts
        to reference non-existent lists by name or non-existent items by number will
        throw.

    .PARAMETER ListName
        Name of the list containing the todo item. Must be used with -Number.

    .PARAMETER List
        List object containing the todo item. Must be used with -Number.

    .PARAMETER Number
        Number of the todo item in its list. Must be used with -ListName or -List.

    .PARAMETER Item
        Todo item to move.

    .PARAMETER ToNumber
        Target position to which the item should be moved. If larger or smaller
        than the largest/smallest item in the list, will be appended/prepended.

    .INPUTS
        Todo item or list to update.
#>
function Move-Todo
{
    [CmdletBinding(DefaultParameterSetName='byListName')]
    param (
        [Parameter(ParameterSetName='byListName')]
        [string] $ListName = 'Default',

        [Parameter(ParameterSetName='byList', ValueFromPipeline)]
        [TodoList] $List,

        [Parameter(ParameterSetName='byListName')]
        [Parameter(ParameterSetName='byList')]
        [int] $Number,

        [Parameter(ParameterSetName='byItem', ValueFromPipeline)]
        [Todo] $Item,

        [Parameter(Mandatory)]
        [int] $ToNumber
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'byListName')
        {
            $nameArr = @($ListName)
            $List = GetListsByName($nameArr)
            $matchingItem = $List.GetItem($Number)
            if ($null -eq $matchingItem)
            {
                throw "Could not find todo number $Number in list '$($List.Name)'"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'byList')
        {
            $matchingItem = $List.GetItem($Number)
            if ($null -eq $matchingItem)
            {
                throw "Could not find todo number $($Number) in list '$($List.Name)'"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'byItem')
        {
            $List = GetLists | Where-Object Name -eq $Item.ParentListName | Select-Object -First 1
            if ($List)
            {
                $matchingItem = $List.GetItem($Item.Number)
                if ($null -eq $matchingItem)
                {
                    throw "Could not find todo number $($Item.Number) in list '$($List.Name)'"
                }
            }
            else
            {
                throw "Could not find list matching todo item's list name '$($List.Name)'"
            }
        }

        $null = $List.RemoveItem($matchingItem)
        $List.InsertItem($ToNumber, $matchingItem)
        if (ListExists($List.Name))
        {
            UpdateList($List)
        }
        else
        {
            Write-Warning "List with name '$($List.Name)' not found in todo list repository; changes will not be persisted"
        }
    }
}