<#
    .SYNOPSIS
        Retrieves todo items from a list

    .DESCRIPTION
        Retries and filters todo items from a list.
    
    .PARAMETER ListName
        Name of the list whose todo items should be retrieved. Error occurs
        if list does not exist.

    .PARAMETER List
        List object whose todo items should be retrieved.

    .PARAMETER Description
        Filter on description of the todo items to return. Uses the same
        syntax as the -Like operator on strings.

    .PARAMETER Number
        One-based index of the todo item to be retrieved. No error will
        occur if no such index exists.

    .PARAMETER Tag
        Tag(s) by which results should be filtered.

    .INPUTS
        (optional) List whose items should be retrieved

    .OUTPUTS
        List of todo items, appropriately filtered.
#>
function Get-Todo
{
    [CmdletBinding(DefaultParameterSetName='byListName')]
    param (
        [Parameter(ParameterSetName='byListName')]
        [string] $ListName,

        [Parameter(ParameterSetName='byList', ValueFromPipeline)]
        [TodoList] $List,

        [Parameter(Position=0)]
        [string] $Description,

        [Parameter(Position=1)]
        [Nullable[int]] $Number,

        [Parameter(Position=2)]
        [string[]] $Tag
    )

    process
    {
        if (-not $List)
        {
            if ($PSCmdlet.ParameterSetName -eq 'byListName')
            {
                $List = (GetWorkingList)
            }
            else
            {
                $nameArr = @($ListName)
                $List = GetListsByName($nameArr)
            }
        }

        [List[Todo]] $items = $List.Items
        if ($null -ne $Number)
        {
            # Kind of hacky, but as a result we always return a [List[Todo]].
            $item = $List.GetItem($Number)
            if ($null -ne $item)
            {
                $items = [List[Todo]]::new([Todo[]](@($item)))
            }
            else
            {
                $items = [List[Todo]]::new()
            }
        }
        else
        {
            $items = [List[Todo]]::new($items)
        }

        [Todo[]] $clonedItems = @($items | % { [Todo]::new($_) })

        if ($Tag)
        {
            $tagHash = [HashSet[string]]::new($Tag)
            $clonedItems = $clonedItems | Where-Object { $tagHash.Overlaps($_.Tags) }
        }

        if ($Description)
        {
            $clonedItems | Where-Object Description -like $Description
        }
        else
        {
            $clonedItems
        }
    }
}