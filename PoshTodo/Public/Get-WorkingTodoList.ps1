function Get-WorkingTodoList
{
    [CmdletBinding()]
    param ()

    process
    {
        $name = GetWorkingList
        if (-not (ListExists($name)))
        {
            Write-Warning "Could not find working todo list '$name'; if deleted, set another list as your working list using Set-WorkingTodoList"
        }
        else
        {
            $name
        }
    }
}