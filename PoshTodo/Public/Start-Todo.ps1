<#
    .SYNOPSIS
        Marks the given todo item as started.

    .DESCRIPTION
        Updates the given todo item so that its status is 'IN PROGRESS'. Item can be updated
        directly or indirectly by referencing its parent list.

    .PARAMETER ListName
        Name of the list containing the todo item. Must be used with -Number.

    .PARAMETER List
        List object containing the todo item. Must be used with -Number.

    .PARAMETER Number
        Number of the todo item in its list. Must be used with -ListName or -List.

    .PARAMETER Item
        Todo item to update.

    .INPUTS
        Todo item or list object.
#>
function Start-Todo
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
        [Todo] $Item
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'byListName')
        {
            $nameArr = @($ListName)
            $List = GetListsByName($nameArr)
            $matchingItem = $List.GetItem($Number)
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'byList')
        {
            $matchingItem = $List.GetItem($Number)
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'byItem')
        {
            $List = GetLists | Where-Object Name -eq $Item.ParentListName | Select-Object -First 1
            if ($List)
            {
                $matchingItem = $List.GetItem($Item.Number)
                if ($null -eq $matchingItem)
                {
                    Write-Warning "Could not find todo number $($Item.Number) in list '$($List.Name)'; changes will not be persisted"
                }
            }
            else
            {
                Write-Warning "Could not find list matching todo item's list name '$($List.Name)'; changes will not be persisted"
                $matchingItem = $Item
            }
        }

        $matchingItem.Status = 'IN PROGRESS'
        if ($Item)
        {
            $Item.Status = 'IN PROGRESS'
        }
        if ($List -and $null -ne $matchingItem)
        {
            $List.SetItem($matchingItem)
            UpdateList($List)
        }
    }
}