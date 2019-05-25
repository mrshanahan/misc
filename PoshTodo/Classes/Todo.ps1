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