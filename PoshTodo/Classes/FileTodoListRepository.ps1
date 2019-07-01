$DEFAULTTODOLISTFILE = Join-Path $env:HOME '.poshtodo\lists'

function GetTodoList
{
    if ([string]::IsNullOrWhiteSpace($env:POSHTODO_TODOLISTFILE))
    {
        $env:POSHTODO_TODOLISTFILE = $DEFAULTTODOLISTFILE
    }
    $env:POSHTODO_TODOLISTFILE
}

# NB: Any function that returns a list in PowerShell should
# generally be wrapped in @(...) lest a singleton list be
# extracted into the single object. E.g. if Foo() returns
# @('bar') and is assigned to a variable $baz thusly:
#
#     $baz = Foo
#
# $baz will contain an object of type string instead of string[].
# The following will populate $baz with an array containing
# a single object:
#
#     $baz = @(Foo
#
class FileTodoListRepository
{
    [void] Add([TodoList] $List) {
        $lists = @(ParseFile((GetTodoList)))
        $lists += $List
        $this.Write($lists)
    }

    [TodoList[]] GetAll() {
        return @(ParseFile((GetTodoList)))
    }

    [TodoList] Get([string] $Name) {
        $lists = @(ParseFile((GetTodoList)))
        $filteredLists = @($lists | Where-Object Name -eq $Name)
        return $filteredLists[0]
    }

    [bool] Exists([string] $Name) {
        $list = $this.Get($Name)
        return $null -ne $list
    }

    [void] Update([TodoList] $List) {
        $lists = @($this.GetAll())
        $updatedLists = @()
        foreach ($l in $lists)
        {
            if ($l.Name -eq $List.Name)
            {
                $updatedLists += $List
            }
            else
            {
                $updatedLists += $l
            }
        }
        $this.Write($updatedLists)
    }

    [void] Remove([TodoList] $List) {
        $lists = @(ParseFile((GetTodoList)))
        $updatedLists = @()
        foreach ($l in $lists)
        {
            if ($l.Name -ne $List.Name)
            {
                $updatedLists += $l
            }
        }
        $this.Write($updatedLists)
    }

    hidden [void] Write([TodoList[]] $Lists) {
        $content = @(SerializeLists($Lists))
        [System.IO.File]::WriteAllLines((GetTodoList), $content)
    }
}