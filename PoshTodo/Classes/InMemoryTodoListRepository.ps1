class InMemoryTodoListRepository
{
    hidden static [InMemoryTodoListRepository] $Instance = [InMemoryTodoListRepository]::new()

    static [InMemoryTodoListRepository] GetInstance() {
        return [InMemoryTodoListRepository]::Instance
    }

    static [void] Reset() {
        ([InMemoryTodoListRepository]::Instance)._lists.Clear()
    }

    hidden [Dictionary[string, TodoList]] $_lists

    hidden [string] $_working = $null

    hidden InMemoryTodoListRepository() {
        $this._lists = New-Object 'Dictionary[string, TodoList]'
        $this._working = $null
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
        $null = $this._lists.Remove($List.Name)
    }

    [void] SetWorking([string] $Name) {
        $this._working = $Name
    }

    [string] GetWorking() {
        return $this._working
    }
}