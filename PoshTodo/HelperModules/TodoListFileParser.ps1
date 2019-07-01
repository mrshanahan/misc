using namespace System.Text.RegularExpressions

function ParseFile([string] $Path)
{
    if (-not (Test-Path $Path))
    {
        New-Item $Path -Force
    }
    $tokens = TokenizeContents($Path)
    $lists = ParseTokens($tokens)
    return $lists
}

function SerializeLists($Lists)
{
    $lines = @()
    foreach ($list in $Lists)
    {
        $listStartLine = "$($list.Name): $($list.Description)"
        $lines += $listStartLine
        foreach ($item in $list.Items)
        {
            $descriptionLine = "    - description: $($item.Description)"
            $tagsLine =        "      tags: $([string]::Join(',', $item.Tags))"
            $statusLine =      "      status: $($item.Status)"

            $lines += $descriptionLine
            $lines += $tagsLine
            $lines += $statusLine
        }
    }

    return $lines
}

$TODOLIST_START = [Regex]::new('^([^:\s]+):\s*(.*)$')
$TODOITEM_START = [Regex]::new('^\s+-(.*)$')
$TODOITEM_DESCRIPTION = [Regex]::new('\s+description:\s+(.*)$')
$TODOITEM_TAGS = [Regex]::new('\s+tags:\s*(.*)$')
$TODOITEM_STATUS = [Regex]::new('\s+status:\s+(.*)$')

class TodoListStartToken
{
    TodoListStartToken([string] $Name, [string] $Description) {
        $this.Name = $Name
        $this.Description = $Description
    }

    [string] $Name
    [string] $Description

    [string] ToString() {
        return "TodoListStartToken($($this.Name), $($this.Description))"
    }
}

class TodoItemStartToken
{
    [string] ToString() {
        return "TodoItemStartToken"
    }
}

class TodoItemDescriptionToken
{
    TodoItemDescriptionToken([string] $Description) {
        $this.Description = $Description
    }

    [string] $Description

    [string] ToString() {
        return "TodoItemDescriptionToken($($this.Description))"
    }
}

class TodoItemStatusToken
{
    TodoItemStatusToken([string] $Status) {
        $this.Status = $Status
    }

    [string] $Status

    [string] ToString() {
        return "TodoItemStatusToken($($this.Status))"
    }
}

class TodoItemTagsToken
{
    TodoItemTagsToken([string[]] $Tags) {
        $this.Tags = $Tags
    }

    [string[]] $Tags

    [string] ToString() {
        return "TodoItemTagsToken($($this.Tags))"
    }
}

function TokenizeContents([string] $Path)
{
    $lines = @(Get-Content -Path $Path | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
    $tokens = @()
    foreach ($line in $lines)
    {
        $remainingLine = $line
        if ($TODOLIST_START.IsMatch($remainingLine))
        {
            $match = $TODOLIST_START.Match($remainingLine)
            $tokens += [TodoListStartToken]::new($match.Groups[1].Value, $match.Groups[2].Value)
            $remainingLine = $null
        }
        elseif ($TODOITEM_START.IsMatch($remainingLine))
        {
            $match = $TODOITEM_START.Match($remainingLine)
            $tokens += [TodoItemStartToken]::new()
            $remainingLine = $match.Groups[1].Value
        }

        if ($remainingLine)
        {
            if ($TODOITEM_DESCRIPTION.IsMatch($remainingLine))
            {
                $match = $TODOITEM_DESCRIPTION.Match($remainingLine)
                $tokens += [TodoItemDescriptionToken]::new($match.Groups[1].Value)
            }
            elseif ($TODOITEM_TAGS.IsMatch($remainingLine))
            {
                $match = $TODOITEM_TAGS.Match($remainingLine)
                $tokens += [TodoItemTagsToken]::new($match.Groups[1].Value.Split(','))
            }
            elseif ($TODOITEM_STATUS.IsMatch($remainingLine))
            {
                $match = $TODOITEM_STATUS.Match($remainingLine)
                $tokens += [TodoItemStatusToken]::new($match.Groups[1].Value)
            }
            else
            {
                throw "Could not parse line: $line"
            }
        }
    }

    return $tokens
}

function ParseTokens($Tokens)
{
    $currentList = $null
    $currentIndex = 0
    $currentItem = $null
    $lists = @()

    while ($currentIndex -lt $Tokens.Length)
    {
        $token = $Tokens[$currentIndex]

        if ($token -is [TodoListStartToken])
        {
            if ($null -ne $currentList)
            {
                $lists += $currentList
            }
            $currentList = [TodoList]::new($token.Name, $token.Description)
            $currentIndex += 1
        }
        elseif ($token -is [TodoItemStartToken])
        {
            if ($null -eq $currentList)
            {
                throw 'Invalid token: expected todo list identifier to come before todo item'
            }
            $currentIndex += 1
            $token = $Tokens[$currentIndex]

            $description = ''
            $status = 'TODO'
            $tags = @()
            while (IsTodoItemPropertyToken($token))
            {
                if ($token -is [TodoItemDescriptionToken])
                {
                    $description = $token.Description
                }
                elseif ($token -is [TodoItemStatusToken])
                {
                    $status = $token.Status
                }
                elseif ($token -is [TodoItemTagsToken])
                {
                    $tags = $token.Tags
                }

                $currentIndex += 1
                $token = $Tokens[$currentIndex]
            }

            $currentItem = [Todo]::new($description, $tags)
            if ($status)
            {
                # TODO: Verify status (use enum)
                $currentItem.Status = $status
            }

            $currentList.AppendItem($currentItem)
        }
    }

    if ($null -ne $currentList)
    {
        $lists += $currentList
    }

    return $lists
}

function IsTodoItemPropertyToken($Token)
{
    return $Token -is [TodoItemDescriptionToken] -or
           $Token -is [TodoItemStatusToken] -or
           $Token -is [TodoItemTagsToken]
}

Export-ModuleMember -Function 'ParseFile','SerializeLists'