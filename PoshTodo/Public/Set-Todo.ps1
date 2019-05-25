<#
    .SYNOPSIS
        Updates a todo item

    .DESCRIPTION
        Updates the properties of a todo item in a given list.

    .PARAMETER ListName
        Name of the list to update. Must be used with -Number.

    .PARAMETER List
        List object to update. Must be used with -Number.

    .PARAMETER Number
        Number of the todo item to update. Must be used with -ListName or -List.

    .PARAMETER Item
        Todo item to update. If updating by object, the relevant item is identified by Number; 

    .PARAMETER Tag
        List of tags to set on the todo item.

    .PARAMETER Description
        Description to set on the todo item.

    .INPUTS
        Todo list object (if using -List) or todo item (if using -Item).

    .EXAMPLE
        $item = Get-Todo | Select-Object -First 1
        $item.Description = 'Now something else'
        $item | Set-Todo

        Gets the first todo in the Default list, updates its description, and then persists that change.
#>
function Set-Todo
{
    [CmdletBinding(DefaultParameterSetName='byListName')]
    param (
        [Parameter(ParameterSetName='byListName')]
        [string] $ListName = 'Default',

        [Parameter(ValueFromPipeline)]
        [Parameter(ParameterSetName='byList')]
        [TodoList] $List,

        [Parameter(ParameterSetName='byListName')]
        [Parameter(ParameterSetName='byList')]
        [int] $Number,

        [Parameter(ValueFromPipeline)]
        [Parameter(ParameterSetName='byItem')]
        [Todo] $Item,

        [string[]] $Tag,

        [string] $Description
    )

    process
    {
        [Todo] $matchingItem = $null
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
                else
                {
                    $matchingItem.UpdateWith($Item)
                }
            }
            else
            {
                Write-Warning "Could not find list matching todo item's list name '$($List.Name)'; changes will not be persisted"
                $matchingItem = $Item
            }
        }

        if ($null -ne $matchingItem -and $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Tag'))
        {
            $matchingItem.Tags = $Tag
            if ($Item)
            {
                $Item.Tags = $Tag.Clone()
            }
        }
        if ($null -ne $matchingItem -and $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Description'))
        {
            $matchingItem.Description = $Description
            if ($Item)
            {
                $Item.Description = $Description
            }
        }

        if ($List -and $null -ne $matchingItem)
        {
            $List.SetItem($matchingItem)
            UpdateList($List)
        }
    }
}