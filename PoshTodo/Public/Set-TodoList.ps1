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