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