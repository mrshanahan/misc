<#
    .SYNOPSIS
        Creates a new todo list item

    .DESCRIPTION
        Creates a new todo list item in the given todo list. Adds item to the Default
        list if no other list is provided.

    .PARAMETER ListName
        Name of the list to which this item should be added. Defaults to 'Default'.

    .PARAMETER List
        Reference to the list object to which this item should be added.

    .PARAMETER Description
        Text of the item

    .PARAMETER Tag
        (optional) Array of tags that can be used to categorize the todo item.

    .PARAMETER Number
        (optional) Order in the todo list at which the item should be placed. One-indexed.

    .PARAMETER PassThru
        If provided, will return the todo list with the new item added.

    .INPUTS
        (optional) List to which the new item should be added

    .OUTPUTS
        If -PassThru was provided, the list with the new item added.
#>
function New-Todo
{
    [CmdletBinding(DefaultParameterSetName='byName')]
    param (
        [Parameter(ParameterSetName='byName')]
        [string] $ListName = 'Default',

        [Parameter(ParameterSetName='byObject', ValueFromPipeline)]
        [TodoList] $List,

        [Parameter(Mandatory, Position=1)]
        [string] $Description,

        [Parameter(Position=2)]
        [string[]] $Tag,

        [Nullable[int]] $Number = $null,

        [switch] $PassThru
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'byName')
        {
            $List = GetListsByName(@($ListName))
        }

        $newItem = [Todo]::new($Description, $Tag)
        if ($null -eq $Number)
        {
            $List.AppendItem($newItem)
        }
        else
        {
            $List.InsertItem($Number, $newItem)
        }

        if (-not (ListExists($List.Name)))
        {
            Write-Warning "List with name '$($List.Name)' not found in todo list repository; changes will not be persisted"
        }
        else
        {
            UpdateList($List)
        }

        if ($PassThru)
        {
            [Todo]::new($newItem)
        }
    }
}