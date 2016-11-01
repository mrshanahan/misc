###################################
# Project finder functions
###################################

Function Has-Parent([string] $parent, [string] $dir, [bool] $silent)
{
    $retVal = $false
    if ([String]::IsNullOrEmpty($dir))
    {
        $dir = Get-Location
    }

    if ((-Not (Test-Path $dir)) -And $silent)
    {
        Write-Warning "Path $dir not found"
        return $false
    }

    $curDir = Resolve-Path $dir

    while (-Not [String]::IsNullOrEmpty($curDir))
    {
        $dirToCheck = [System.IO.Path]::Combine($curDir, $parent)
        $retVal = (Test-Path $dirToCheck)
        if ($retVal)
        {
            $curDir = $null
        }
        else
        {
            $curDir = Split-Path -Parent $curDir
        }
    }

    return $retVal
}

Function IsIn-HgRepo([string] $dir = $null, [switch] $Silent)
{
    Return (Has-Parent ".hg" $dir $Silent)
}

Function IsIn-GitRepo([string] $dir = $null, [switch] $Silent)
{
    Return (Has-Parent ".git" $dir $Silent)
}

Function Check-RootOrDefault([string] $Root)
{
    if ([String]::IsNullOrEmpty($Root))
    {
        if (IsIn-HgRepo -Silent)
        {
            $Root = (hg root 2>$null)
        }
        elseif (IsIn-GitRepo -Silent)
        {
            $Root = Get-GitRoot "."
        }
    }
    if ([String]::IsNullOrEmpty($Root) -Or (!(Test-Path $Root)))
    {
        throw [System.ArgumentException] "Invalid root path was provided or current directory is not in an hg repository.`n"
    }
    return $Root
}

Function Get-RootData([Parameter(Mandatory=$true)][string] $Root, [switch] $DontCreateSolutionMap)
{
    if (!(Test-Path $Root))
    {
        throw [System.ArgumentException] "Root path $Root not found.`n"
    }
    $rootData = @{}
    pushd $Root
    try
    {
        if (IsIn-HgRepo $Root)
        {
            $rootPath = (hg root 2>$null) # We're gonna assume that this returns an absolute path so we don't have to pepper -Resolve everywhere
        }
        elseif (IsIn-GitRepo $Root)
        {
            $rootPath = Get-GitRoot $Root
        }
        else
        {
            throw [System.ArgumentException] "This script only works effectively when run for an hg or git repository; $Root is not a repository.`n"
        }

        $rootName = (Split-Path -Leaf $rootPath)
        $solutionMapFile = [System.IO.Path]::Combine((Split-Path -Parent $rootPath), ".solutions-$rootName")
        if (!(Test-Path $solutionMapFile) -And $DontCreateSolutionMap)
        {
            New-Item -ItemType File $solutionMapFile >$null
        }
        $rootData = @{"Name" = $rootName; "Path" = $rootPath; "Map" = $solutionMapFile}
    }
    finally
    {
        popd
    }

    return $rootData
}

Function Find-SolutionsWithProject([Parameter(Mandatory=$true)][string] $ProjectPattern, [string] $Root, [switch] $Exact)
{
    $Root = Check-RootOrDefault $Root
    pushd $Root
    try
    {
        $rootData = Get-RootData $Root
        $solutionMapFile = $rootData.Get_Item("Map")
        $matchingSolutions = @()
        if ($Exact)
        {
            $cleanPattern = $ProjectPattern
            $matchFunc =
            {
                param([string] $proj)
                return $proj -eq $cleanPattern
            }
        }
        else
        {
            $cleanPattern = [String]::Format("*{0}*", $ProjectPattern.Trim("*"))
            $matchFunc = 
            {
                param([string] $proj)
                return $proj -like $cleanPattern
            }
        }
        foreach ($solution in (cat $solutionMapFile))
        {
            if (Test-Path $solution)
            {
                $projects = Load-ProjectRefs($solution)
                $matchingProjects = ($projects | where {$matchFunc.Invoke($_.Name)})
                if ($matchingProjects)
                {
                    $matchingSolutions += ,$solution
                }
            }
        }

        return $matchingSolutions
    }
    finally
    {
        popd
    }
}

Function Update-SolutionMap([string] $Root)
{
    $Root = Check-RootOrDefault $Root
    pushd $Root
    try
    {
        $rootData = Get-RootData $Root
        $rootName = $rootData.Get_Item("Name")
        $rootPath = $rootData.Get_Item("Path")
        $solutionMapFile = $rootData.Get_Item("Map")
        $solutions = (ls $Root -Recurse -Include *.sln | %{$_.FullName}) # `select FullName` gives us back hashmaps with a single FullName key; we just want strings
        
        Set-Content -Path $solutionMapFile -Value $solutions
    }
    finally
    {
        popd
    }
}

Function Get-GitRoot([string] $wd = ".")
{
    $wd = Resolve-Path $wd
    pushd $wd
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
        popd
    }
}

Function Load-ProjectRefs([Parameter(Mandatory=$true)][string] $Solution)
{
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

Add-Type -TypeDefinition @"
    public enum VisualStudioVersion
    {
        VS2010,
        VS2012,
        VS2015
    }
"@

$VersionToExe = @{
    [VisualStudioVersion]::VS2010 = "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\IDE\devenv.exe";
    [VisualStudioVersion]::VS2012 = "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\devenv.exe";
    [VisualStudioVersion]::VS2015 = "C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\devenv.exe"
}

Function Open-Solution([string] $SolutionPattern = "*", [string] $Root, [switch] $TakeFirst, [VisualStudioVersion] $With = [VisualStudioVersion]::VS2015)
{
    if ([String]::IsNullOrEmpty($SolutionPattern))
    {
        throw [System.ArgumentException] "`$SolutionPattern must not be null or empty!`n"
    }
    $Root = Check-RootOrDefault $Root

    $SolutionPattern = [String]::Format("*{0}*", $SolutionPattern.Trim("*"))

    $rootData = Get-RootData $Root -DontCreateSolutionMap
    $solutionMap = $rootData.Get_Item("Map")
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
        Write-Output "Multiple solutions matching pattern $SolutionPattern found; please be more specific:"
        Write-Output $possibleSolutions
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

Function List-Solutions([string] $Root)
{
    $Root = Check-RootOrDefault $Root

    $rootData = Get-RootData $Root -DontCreateSolutionMap
    $solutionMap = $rootData.Get_Item("Map")
    Write-Output (cat $solutionMap)
}