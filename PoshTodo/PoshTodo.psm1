using namespace System.Collections.Generic

<#
    Todo list. Holds a collection of todo items plus some metadata about them.
#>
class TodoList
{
    hidden [List[Todo]] $Items
    [string] $Name
    [string] $Description

    TodoList(
        [string] $Name,
        [string] $Description
    ){
        $this.Name = $Name
        $this.Description = $Description
        $this.Items = New-Object List[Todo]
    }

    TodoList(
        [TodoList] $Other
    ){
        $this.Name = $Other.Name
        $this.Description = $Other.Description
        $this.Items = [List[Todo]]::new($Other.Items)
    }

    [void] AppendItem([Todo] $Item) {
        $this.Items.Add($Item)
        $Item.ParentListName = $this.Name
        $this.UpdateItemNumbers()
    }

    [bool] RemoveItem([Todo] $Item) {
        $actualItem = $this.FindItem($Item)
        if ($actualItem)
        {
            $null = $this.Items.Remove($actualItem)
            $Item.ParentListName = $null
            $Item.Number = -1
            $this.UpdateItemNumbers()
        }
        return ($null -ne $actualItem)
    }

    [bool] RemoveItemAt([int] $Number) {
        $item = $this.GetItem($Number)
        if ($null -ne $item)
        {
            return $this.RemoveItem($item)
        }
        return $false
    }

    [void] InsertItem([int] $Number, [Todo] $Item) {
        if ($Number -gt $this.Items.Count)
        {
            $index = $this.Items.Count
        }
        elseif ($Number -le 0)
        {
            $index = 0
        }
        else
        {
            $index = $Number - 1
        }
        $this.Items.Insert($index, $Item)
        $Item.ParentListName = $this.Name
        $this.UpdateItemNumbers()
    }

    [Todo] GetItem([int] $Number) {
        if ($this.IsNumberValid($Number))
        {
            $index = $Number - 1
            return $this.Items[$index]
        }
        return $null
    }

    [void] SetItem([Todo] $Item) {
        if ($this.IsNumberValid($Item.Number))
        {
            $index = $Item.Number - 1
            $this.Items[$index] = $Item
        }
    }

    hidden [bool] IsNumberValid([int] $Number) {
        return $Number -gt 0 -and $Number -le $this.Items.Count
    }

    hidden [Todo] FindItem([Todo] $Item) {
        foreach ($i in $this.Items)
        {
            if ($i.IsEqualTo($Item))
            {
                return $i
            }
        }
        return $null
    }

    hidden [void] UpdateItemNumbers() {
        for ($i = 0; $i -lt $this.Items.Count; $i += 1)
        {
            $this.Items[$i].Number = $i + 1
        }
    }
}

<#
    Single todo item. A collection of these make up a todo list.
#>
class Todo
{
    [string] $ParentListName
    [int] $Number
    [string] $Description
    [string] $Status
    [string[]] $Tags

    Todo(
        [string] $Description,
        [string[]] $Tags
    ){
        $this.Description = $Description
        $this.Status = 'TODO'
        $this.Tags = $Tags
    }

    Todo(
        [Todo] $Other
    ){
        $this.ParentListName = $Other.ParentListName
        $this.Number = $Other.Number
        $this.Description = $Other.Description
        $this.Status = $Other.Status
        if ($Other.Tags)
        {
            $this.Tags = $Other.Tags.Clone()
        }
        else
        {
            $this.Tags = @()
        }
    }

    [bool] IsEqualTo([Todo] $Other) {
        $numberEq = $this.Number -eq $Other.Number
        $descriptionEq = $this.Description -eq $Other.Description
        $statusEq = $this.Status -eq $Other.Status
        $tagsEq = [Todo]::AreTagsEqual($this.Tags, $Other.Tags)
        return $numberEq -and $descriptionEq -and $statusEq -and $tagsEq
    }

    [void] UpdateWith([Todo] $Other) {
        $this.Description = $Other.Description
        $this.Status = $Other.Status
        $this.Tags = $Other.Tags.Clone()
    }

    hidden static [bool] AreTagsEqual([string[]] $These, [string[]] $Those) {
        return (
            (($null -eq $These) -or ($These.Length -eq 0)) -and
            (($null -eq $Those) -or ($Those.Length -eq 0))
        ) -or (
            $null -ne $These -and
            $null -ne $Those -and
            [System.Linq.Enumerable]::SequenceEqual($These, $Those)
        )
    }
}

### Private repository functions

class InMemoryRepository
{
    hidden static [InMemoryRepository] $Instance = [InMemoryRepository]::new()

    static [InMemoryRepository] GetInstance() {
        return [InMemoryRepository]::Instance
    }

    static [void] Reset() {
        ([InMemoryRepository]::Instance)._lists.Clear()
    }

    hidden [Dictionary[string, TodoList]] $_lists

    hidden InMemoryRepository() {
        $this._lists = New-Object 'Dictionary[string, TodoList]'
        $defaultList = [TodoList]::new('Default', 'Default todo list')
        $this._lists.Add($defaultList.Name, $defaultList)
    }

    [void] Add([TodoList] $List) {
        $this._lists.Add($List.Name, $List)
    }

    [TodoList[]] GetAll() {
        return @($this._lists.Values)
    }

    [TodoList] Get([string] $Name) {
        return $this._lists[$Name]
    }

    [bool] Exists([string] $Name) {
        return $this._lists.ContainsKey($Name)
    }

    [void] Update([TodoList] $List) {
        if (-not $this._lists.ContainsKey($List.Name))
        {
            throw "No such list with name '$($List.Name)'"
        }

        $this._lists[$List.Name] = $List
    }

    [void] Remove([TodoList] $List) {
        if ($List.Name -ne 'Default')
        {
            $null = $this._lists.Remove($List.Name)
        }
    }
}

<#
    EXPECTED BEHAVIOR:
        - Returns IEnumerable[TodoList]
        - Does not return lists removed by RemoveList and not re-added
        - Returns all lists added by AddList and not removed
        - Returned lists reflect all updates made to them by UpdateList
        - ListExists($L.Name) -eq $true IFF (GetLists) -contains $L
#>
function GetLists
{
    [InMemoryRepository]::GetInstance().GetAll()
}

<#
    EXPECTED BEHAVIOR:
        - Returns bool
        - ListExists($L.Name) -eq $true IFF (GetLists) -contains $L
        - ListExists($L.Name) -eq $false IFF (GetLists) -notcontains $L
        - Does not throw if no such list exists
#>
function ListExists([string] $Name)
{
    [InMemoryRepository]::GetInstance().Exists($Name)
}

<#
    EXPECTED BEHAVIOR:
        - Returns void
        - _May_ throw if $List does not exist (i.e. ListAdd($List) was not invoked)
        - Changes are reflected in subsequent calls to GetLists
#>
function UpdateList([TodoList] $List)
{
    [InMemoryRepository]::GetInstance().Update($List)
}

<#
    EXPECTED BEHAVIOR:
        - Returns void
        - _May_ throw if list with name $List.Name already exists
        - $List will appear in subsequent calls to GetLists
        - Subsequent calls of ListExists($N) s.t. $List.Name -eq $N will return True (unless removed)
#>
function AddList([TodoList] $List)
{
    [InMemoryRepository]::GetInstance().Add($List)
}

<#
    EXPECTED BEHAVIOR:
        - Returns void
        - _May_ throw if list with name $List.Name doesn't exist
        - Does not throw if ListExists($List.Name) -eq True
        - $List will not appear in subsequent calls to GetLists
        - Subsequent calls of ListExists($N) s.t. $List.Name -eq $N will return False (unless re-added)
#>
function RemoveList([TodoList] $List)
{
    [InMemoryRepository]::GetInstance().Remove($List)
}

### Gemeral private functions

function GetListsByName([string[]] $Name)
{
    $lists = @(GetLists | Where-Object Name -in $Name)
    if ($lists.Count -ne $Name.Count)
    {
        $namesNotFound = [HashSet[string]]::new($Name)
        $listNames = [string[]] @(GetLists | ForEach-Object Name)
        $namesNotFound.ExceptWith($listNames)
        $suffix = if ($namesNotFound.Count -ne 1) { "s" } else { "" }
        throw "Could not find list${suffix} with name${suffix}: $namesNotFound"
    }
    else
    {
        $lists
    }
}

### Public functions


# TODO: Add glob filtering on name

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

<#
    .SYNOPSIS
        Updates a todo list

    .DESCRIPTION
        Updates the relevant properties of the given todo list.

    .PARAMETER Name
        Name(s) of the todo list(s) to update. Must be provided if List is not.

    .PARAMETER List
        Object reference to the todo list to update. Must be provided if Name is not.
        This reference will not be updated; instead, the underlying list of todo
        lists will be updated, and a new todo list with the relevant properties
        updated will be returned if PassThru is provided.

    .PARAMETER Description
        New description for the given todo list(s).

    .PARAMETER PassThru
        If provided, returns copies of the updated todo lists.

    .INPUTS
        Todo lists to update (if Name is not provided).

    .OUTPUTS
        Updated todo lists, if PassThru is provided.

    .EXAMPLE
        Update-TodoList -Name 'Foo' -Description 'Tracks important foo items'

        Updates the list with name 'Foo' to have the given description.

    .EXAMPLE
        Get-TodoList | Where-Object Name -like 'Foo*' | Update-TodoList -Description 'Tracks important foo items'

        Updates all lists with name beginning with 'Foo' to have the given description.
#>
function Set-TodoList
{
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName='byName', Position=0)]
        [string[]] $Name,

        [Parameter(ParameterSetName='byName', Position=1)]
        [string] $Description,

        [Parameter(ParameterSetName='byObject', Position=0, ValueFromPipeline)]
        [TodoList] $List,

        [switch] $PassThru
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'byName')
        {
            $nameArr = @($Name)
            $lists = @(GetListsByName($nameArr))
            foreach ($l in $lists)
            {
                if ($MyInvocation.BoundParameters.Keys -match 'Description')
                {
                    $l.Description = $Description
                }

                UpdateList($l)
            }
        }
        else
        {
            UpdateList($List)
            $lists = @($List)
        }

        if ($PassThru)
        {
            $lists
        }
    }
}

<#
    .SYNOPSIS
        Removes an existing todo list

    .DESCRIPTION
        Removes an existing todo list by name or by object reference. The list
        should not be returned by subsequent invocations of Get-TodoList. If a
        provided list does not exist, no error will be thrown.

    .PARAMETER Name
        Name(s) of the todo list(s) to remove. Must be provided if List is not.

    .PARAMETER List
        Object reference to the todo list to remove. Must be provided if Name is not.

    .INPUTS
        Todo lists to remove (if Name is not provided).

    .EXAMPLE
        Remove-TodoList -Name 'Foo','Bar'

        Removes the 'Foo' and 'Bar' todo lists. Will not throw if either does not exist.

    .EXAMPLE
        Get-TodoList | Where-Object Name -like 'Foo*' | Remove-TodoList

        Removes all todo lists with names beginning with 'Foo'.
#>
function Remove-TodoList
{
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName='byName', Position=0)]
        [string[]] $Name,

        [Parameter(ParameterSetName='byObject', Position=0, ValueFromPipeline)]
        [TodoList] $List
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'byName')
        {
            $listsToRemove = GetLists | Where-Object Name -in $Name
        }
        else
        {
            $listsToRemove = @($List)
        }

        foreach ($l in $listsToRemove)
        {
            if (ListExists($l.Name))
            {
                RemoveList($l)
            }
            else
            {
                Write-Verbose "List $($l.Name) does not exist; skipping"
            }
        }
    }
}

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
        [string] $ListName = 'Default',

        [Parameter(ParameterSetName='byList', ValueFromPipeline)]
        [TodoList] $List,

        [Nullable[int]] $Number,

        [string[]] $Tag
    )

    process
    {
        if (-not $List)
        {
            $nameArr = @($ListName)
            $List = GetListsByName($nameArr)
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
            $clonedItems | Where-Object { $tagHash.Overlaps($_.Tags) }
        }
        else
        {
            $clonedItems
        }
    }
}

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

<#
    .SYNOPSIS
        Marks the given todo item as completed.

    .DESCRIPTION
        Updates the given todo item so that its status is 'COMPLETE'. Item can be updated
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
function Complete-Todo
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

        $matchingItem.Status = 'COMPLETE'
        if ($Item)
        {
            $Item.Status = 'COMPLETE'
        }
        if ($List -and $null -ne $matchingItem)
        {
            $List.SetItem($matchingItem)
            UpdateList($List)
        }
    }
}

<#
    .SYNOPSIS
        Resets a given todo item's progress

    .DESCRIPTION
        Updates the given todo item so that its status is 'TODO'. Item can be updated
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
function Reset-Todo
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

        $matchingItem.Status = 'TODO'
        if ($Item)
        {
            $Item.Status = 'TODO'
        }
        if ($List -and $null -ne $matchingItem)
        {
            $List.SetItem($matchingItem)
            UpdateList($List)
        }
    }
}

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

New-Alias -Name stodo -Value Set-Todo
New-Alias -Name rmtodo -Value Remove-Todo
New-Alias -Name ntodo -Value New-Todo
New-Alias -Name sttodo -Value Start-Todo
New-Alias -Name ctodo -Value Complete-Todo
New-Alias -Name retodo -Value Reset-Todo
New-Alias -Name mvtodo -Value Move-Todo