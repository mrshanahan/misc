Import-Module $PSScriptRoot\Utilities.psm1

# Returns true if cwd is in a Git repo, false otherwise.
Function Test-InGitRepo
{
    git rev-parse --show-top-level 2>&1 | Out-Null
    $?
}

# Returns the root of the repo if $Root is in a Git repo, otherwise returns the
# default (if provided) or throws (if not provided)
Function Check-RootOrDefault([string] $Root)
{
    if ([String]::IsNullOrEmpty($Root))
    {
        if (Test-InGitRepo ".")
        {
            $Root = Get-GitRoot "."
        }
    }
    if ([String]::IsNullOrEmpty($Root) -Or (!(Test-Path $Root)))
    {
        throw [System.ArgumentException] "Invalid root path was provided or current directory is not in a Git repository.`n"
    }
    return $Root
}

# Returns a HashTable containing info about the Git root and its solution map
Function Get-RootData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Root,

        [switch] $DontCreateSolutionMap
    )

    if (!(Test-Path $Root))
    {
        throw [System.ArgumentException] "Root path $Root not found.`n"
    }

    Push-Location $Root
    try
    {
        if (Test-InGitRepo $Root)
        {
            $rootPath = Get-GitRoot $Root
        }
        else
        {
            throw [System.ArgumentException] "This script only works effectively when run against a Git repository; $Root is not a repository.`n"
        }

        $rootName = (Split-Path -Leaf $rootPath)
        $solutionMapFolder = Join-Path $env:HOME '.solutionmaps'
        if (-not (Test-Path $solutionMapFolder))
        {
            Write-Verbose "Creating solution map folder: $solutionMapFolder"
            New-Item -ItemType Directory $solutionMapFolder | Out-Null
        }
        $solutionMapFile = [System.IO.Path]::Combine($solutionMapFolder, ".solutions-$rootName")
        if (!(Test-Path $solutionMapFile) -And $DontCreateSolutionMap)
        {
            New-Item -ItemType File $solutionMapFile | Out-Null
        }

        @{"Name" = $rootName; "Path" = $rootPath; "Map" = $solutionMapFile}
    }
    finally
    {
        Pop-Location
    }
}

# Loads project references from the given solution
Function Load-ProjectRefs
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Solution
    )

    $projectRegexText = "Project\(`"{([^}]*)}`"\)[\s]*=[\s]*`"([^`"]*)`",[\s]*`"([^`"]*)`",[\s]*`"{([^}]*)}`"[\n\s]*EndProject"
    $projectRegex = New-Object System.Text.RegularExpressions.Regex($projectRegexText, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $solutionParent = (Split-Path -Resolve -Parent $Solution)
    $projectMatches = $projectRegex.Matches((cat $Solution))
    $retVal = @()
    foreach ($match in $projectMatches)
    {
        $projectPath = [System.IO.Path]::Combine($solutionParent, $match.Groups[3].Value)
        $absoluteProjectPath = [System.IO.Path]::GetFullPath($projectPath)
        $projectDict = @{}
        $projectDict["Type"] = $match.Groups[1].Value
        $projectDict["Name"] = $match.Groups[2].Value
        $projectDict["Path"] = $absoluteProjectPath
        $projectDict["Guid"] = $match.Groups[4].Value
        $projectObj = New-Object -TypeName PSObject -Property $projectDict
        $retVal += ,$projectObj
    }
    return $retVal
}

###############################
# Begin public types/functions
###############################

Add-Type -TypeDefinition @"
    public enum VisualStudioVersion
    {
        VS2010,
        VS2012,
        VS2015,
        VS2017
    }
"@

$VersionToExe = @{
    [VisualStudioVersion]::VS2010 = "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\IDE\devenv.exe";
    [VisualStudioVersion]::VS2012 = "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\devenv.exe";
    [VisualStudioVersion]::VS2015 = "C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\devenv.exe"
    [VisualStudioVersion]::VS2017 = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\devenv.exe"
}

# Returns the Windows-style path to the Git root of the given working dir, else throws
Function Get-GitRoot
{
    [CmdletBinding()]
    param (
        [string] $wd = "."
    )

    $wd = Resolve-Path $wd
    Push-Location $wd
    try
    {
        $root = (git rev-parse --show-toplevel 2>$null)
        if ((!$?) -Or [String]::IsNullOrEmpty($root))
        {
            throw [System.Exception] "Path $wd is not in a git repo!"
        }
        $windowsRoot = (Resolve-Path $root).Path # git rev-parse returns a Unix-y path
        Return $windowsRoot
    }
    finally
    {
        Pop-Location
    }
}

Function Find-SolutionsWithProject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string[]] $ProjectPatterns,

        [string] $Root,

        [switch] $NoExact
    )

    $Root = Check-RootOrDefault $Root
    Push-Location $Root
    try
    {
        $rootData = Get-RootData $Root
        $solutionMapFile = $rootData.Map
        if ($NoExact)
        {
            $matchFunc =
            {
                param([string] $proj, [string] $pattern)
                return $proj -like [String]::Format("*{0}*", $pattern.Trim("*"))
            }
        }
        else
        {
            $matchFunc =
            {
                param([string] $proj, [string] $pattern)
                return $proj -eq $pattern
            }
        }
        $matchingSolutionsSetCollection = @()
        foreach ($projectPattern in $ProjectPatterns)
        {
            $matchingSolutions = @()
            foreach ($solution in (cat $solutionMapFile))
            {
                if (Test-Path $solution)
                {
                    $projects = Load-ProjectRefs($solution)
                    $matchingProjects = ($projects | where {$matchFunc.Invoke($_.Name, $projectPattern)})
                    if ($matchingProjects)
                    {
                        $matchingSolutions += ,$solution
                    }
                }
            }

            $matchingSolutionsSet = New-GenericObject System.Collections.Generic.HashSet -Of string
            foreach ($soln in $matchingSolutions)
            {
                $matchingSolutionsSet.Add($soln) | Out-Null
            }
            $matchingSolutionsSetCollection += ,$matchingSolutionsSet
            Write-Verbose "Solution set for '$projectPattern': $matchingSolutionsSet"
        }
        $runningSolutionsSet = $matchingSolutionsSetCollection[0]
        foreach ($solutionsSet in $matchingSolutionsSetCollection)
        {
            $runningSolutionsSet.IntersectWith($solutionsSet)
        }

        return $runningSolutionsSet
    }
    finally
    {
        Pop-Location
    }
}

Function Update-SolutionMap
{
    [CmdletBinding()]
    param (
        [string] $Root
    )

    $Root = Check-RootOrDefault $Root
    Push-Location $Root
    try
    {
        $rootData = Get-RootData $Root
        $solutionMapFile = $rootData.Map
        $solutions = [System.IO.Directory]::GetFiles($Root, "*.sln", [System.IO.SearchOption]::AllDirectories)

        Set-Content -Path $solutionMapFile -Value $solutions
    }
    finally
    {
        Pop-Location
    }
}

Function Open-Solution
{
    [CmdletBinding()]
    param (
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [string] $SolutionPattern = "*",

        [string] $Root,

        [switch] $TakeFirst,

        [VisualStudioVersion] $With = [VisualStudioVersion]::VS2017
    )

    if ([String]::IsNullOrEmpty($SolutionPattern))
    {
        throw [System.ArgumentException] "`$SolutionPattern must not be null or empty!`n"
    }
    $Root = Check-RootOrDefault $Root

    $SolutionPattern = [String]::Format("*{0}*", $SolutionPattern.Trim("*"))

    $rootData = Get-RootData $Root -DontCreateSolutionMap
    $solutionMap = $rootData.Map
    if (!(Test-Path $solutionMap))
    {
        Update-SolutionMap $Root
    }

    $possibleSolutions = @()
    foreach ($solution in (cat $solutionMap))
    {
        if ($solution -Like $SolutionPattern)
        {
            $possibleSolutions += ,$solution
        }
    }
    if ($possibleSolutions.Count -gt 1 -And (!$TakeFirst))
    {
        $messages = @("Multiple solutions matching pattern $SolutionPattern found; please be more specific:") + $possibleSolutions
        $messages | Out-String | Write-Warning
    }
    elseif ($possibleSolutions.Count -eq 0)
    {
        Write-Warning "No solutions found matching pattern $SolutionPattern"
    }
    else
    {
        & $VersionToExe[$With] $possibleSolutions[0]
    }
}

Function Get-Solutions
{
    [CmdletBinding()]
    param (
        [string] $Root
    )

    $Root = Check-RootOrDefault $Root

    $rootData = Get-RootData $Root -DontCreateSolutionMap
    $solutionMap = $rootData.Map
    Write-Output (cat $solutionMap)
}

New-Alias -Name List-Solutions -Value Get-Solutions

Export-ModuleMember -Function 'Get-GitRoot','Get-Solutions','Find-SolutionsWithProject','Open-Solution','Update-SolutionMap' `
                    -Alias 'List-Solutions'
