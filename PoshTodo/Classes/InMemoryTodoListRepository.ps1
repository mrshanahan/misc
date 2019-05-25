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

    hidden InMemoryTodoListRepository() {
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