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