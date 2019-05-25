$DEFAULTTODOLISTFILE = Join-Path $env:HOME '.poshtodo\lists'
$global:TODOLISTFILE = $DEFAULTTODOLISTFILE
if ($env:POSHTODO_TODOLISTFILE)
{
    $global:TODOLISTFILE = $env:POSHTODO_TODOLISTFILE
}

class FileTodoListRepository
{
    [void] Add([TodoList] $List) {
        $lists = ParseFile($global:TODOLISTFILE)
        $lists += $List
        $this.Write($lists)
    }

    [TodoList[]] GetAll() {
        return ParseFile($global:TODOLISTFILE)
    }

    [TodoList] Get([string] $Name) {
        $lists = ParseFile($global:TODOLISTFILE)
        $filteredLists = @($lists | Where-Object Name -eq $Name)
        return $filteredLists[0]
    }

    [bool] Exists([string] $Name) {
        $list = $this.Get($Name)
        return $null -ne $list
    }

    [void] Update([TodoList] $List) {
        $lists = $this.GetAll()
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
        $lists = ParseFile($global:TODOLISTFILE)
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
        $content = SerializeLists($Lists)
        [System.IO.File]::WriteAllLines($global:TODOLISTFILE, $content)
    }
}