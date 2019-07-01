function ParseBoolValue([string] $Value)
{
    if ($Value)
    {
        [bool]::FalseString -ne $Value
    }
    else
    {
        $true
    }
}

function GetInstance
{
    $INMEMORYREPO = ParseBoolValue($env:POSHTODO_INMEMORYREPO)
    if ($INMEMORYREPO)
    {
        $instance = [InMemoryTodoListRepository]::GetInstance()
    }
    else
    {
        $instance = [FileTodoListRepository]::new()
    }

    return $instance
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
    (GetInstance).GetAll()
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
    (GetInstance).Exists($Name)
}

<#
    EXPECTED BEHAVIOR:
        - Returns void
        - _May_ throw if $List does not exist (i.e. ListAdd($List) was not invoked)
        - Changes are reflected in subsequent calls to GetLists
#>
function UpdateList([TodoList] $List)
{
    (GetInstance).Update($List)
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
    (GetInstance).Add($List)
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
    (GetInstance).Remove($List)
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

Export-ModuleMember -Function 'GetLists', 'ListExists', 'UpdateList', 'AddList', 'RemoveList', 'GetListsByName'