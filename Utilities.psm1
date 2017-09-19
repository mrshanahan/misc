###############################
# Filesystem utilities
###############################

# Updates the relevant timestamp for the given file.
function Update-FileTimestampAttribute
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]] $Paths,

        [ValidateSet('Write','Access','WriteAccess')]
        [string] $Property = 'WriteAccess',

        [switch] $PassThru
    )

    process
    {
        foreach ($Path in $Paths)
        {
            if (!(Test-Path $Path))
            {
                $Parent = Split-Path -Parent -Path $Path
                if (!([String]::IsNullOrEmpty($Parent)) -and !(Test-Path $Parent))
                {
                    throw "Can't find parent of file $Path"
                }

                $CreatedFile = New-Item -ItemType File -Path $Path
                if ($PassThru)
                {
                    $CreatedFile
                }
            }
            elseif (Test-Path $Path -PathType Container)
            {
                throw "Path should be a file, not directory"
            }
            else
            {
                $ExistingFile = Get-Item $Path
                if ($Property -eq 'Write' -or $Property -eq 'WriteAccess')
                {
                    $ExistingFile.LastWriteTime = Get-Date
                }
                if ($Property -eq 'Access' -or $Property -eq 'WriteAccess')
                {
                    $ExistingFile.LastAccessTime = Get-Date
                }
                if ($PassThru)
                {
                    $ExistingFile
                }
            }
        }
    }
}

# Compares the contents of two directories. Optionally include
# subdirectories (useful if there are empty subdirectories).
function Compare-Directories
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=1)]
        [string] $From,

        [Parameter(Mandatory=$true, Position=2)]
        [string] $To,

        [switch] $IncludeSubdirectories
    )

    if (!(Test-Path -PathType Container -Path $From))
    {
        throw "Could not find 'From' directory at $From"
    }
    if (!(Test-Path -PathType Container -Path $To))
    {
        throw "Could not find 'To' directory at $To"
    }

    $FromListing = Get-FileListing -Root $From -IncludeDirectories:$IncludeSubdirectories
    $ToListing = Get-FileListing -Root $To -IncludeDirectories:$IncludeSubdirectories

    Compare-Object -ReferenceObject $FromListing -DifferenceObject $ToListing
}

# Returns a listing of all files underneath the given root, with the
# root itself truncated. Useful for comparing diffs between directories.
function Get-FileListing
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=1)]
        [string] $Root,

        [switch] $IncludeDirectories
    )

    $FullRoot = Resolve-Path $Root | Select-Object -ExpandProperty Path
    $FullRoot = $FullRoot.TrimEnd('\') + '\'
    $FullRootPattern = "^$($FullRoot -replace '\\', '\\')"

    Get-ChildItem -Recurse -Path $FullRoot -File:(!$IncludeDirectories) |
        Select-Object -ExpandProperty FullName |
        ForEach-Object { $_ -replace $FullRootPattern, '' } |
        Sort-Object
}

# Uses robocopy to delete long file paths that posh/explorer can't
Function Remove-LongFilePath
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string] $Path
    )

    begin
    {
        function ProcessR([string] $Parent, [string] $SourceDir)
        {
            # If $Parent is a leaf, just return
            Write-Verbose "Processing '$Parent'"
            if (Test-Path -PathType Container -Path $Parent)
            {
                # Recursively delete all non-leaf children
                $Children = Get-ChildItem -Directory -Path $Parent
                foreach ($Child in $Children)
                {
                    ProcessR $Child.FullName $SourceDir
                }

                # At this point, $Parent should contain no Container nodes
                Write-Verbose "Deleting '$Parent'"
                robocopy "$SourceDir" "$Parent" /purge | Write-Verbose
                $RobocopyExitCode = $LastExitCode
                Write-Verbose "robocopy exit code: $RobocopyExitCode"

                # Exit codes 0, 1, 2, & 4 do not indicate error in robocopy. :/
                if ($RobocopyExitCode -ge 8)
                {
                    Write-Error "Failed to delete '$Parent'"
                }
            }
        }
    }

    process
    {
        $EmptyTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        Write-Verbose "robocopy source dir: '$EmptyTempDir'"
        New-Item -Force -ItemType Directory $EmptyTempDir -ErrorAction Stop | Out-Null
        try
        {
            ProcessR $Path $EmptyTempDir
        }
        finally
        {
            Remove-Item -Force -Recurse -Path $EmptyTempDir -ErrorAction Continue
        }
    }
}

# Converts a given file to a given encoding.
Function ConvertTo-Encoding
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string] $Path,

        [System.Text.Encoding] $Encoding = [System.Text.Encoding]::UTF8
    )

    process
    {
        if (!(Test-Path -PathType Leaf -Path $Path))
        {
            Write-Error "Could not find file at path '$Path'"
        }
        else
        {
            $TempPath = [System.IO.Path]::GetTempFileName()
            Write-Verbose "Converting file $Path -> $TempPath"
            Get-Content -Path $Path |
                ForEach-Object { [System.IO.File]::AppendAllText($TempPath, $_+"`n", $Encoding) }
            Write-Verbose "Moving $TempPath -> $Path"
            Move-Item -Force -Path $TempPath -Destination $Path
        }
    }
}

# Gets the size of alls items for each child of the given directory.
Function Get-ChildSizes ($dir=".\")
{
    If (-Not (Get-Item $dir) -is [System.IO.DirectoryInfo])
    {
        throw [System.ArgumentException] "$dir is not a directory or does not exist.`n"
    }
    Get-ChildItem $dir | Format-Table Name, @{Label="Size"; Expression={"{0:N4} MB" -f (Get-Size "$dir\\$($_.Name)")}}
}

# Gets the size of a given folder. Did not write it myself,
# but don't know where it came from.
function Get-FolderSize
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] [string[]] $Path,
        [int] $Precision = 4,
        [switch] $RoboOnly)
    begin {
        $FSO = New-Object -ComObject Scripting.FileSystemObject -ErrorAction Stop
        function Get-RoboFolderSizeInternal {
            [CmdletBinding()]
            param(
                # Paths to report size, file count, dir count, etc. for.
                [string[]] $Path,
                [int] $Precision = 4)
            begin {
                if (-not (Get-Command -Name robocopy -ErrorAction SilentlyContinue)) {
                    Write-Warning -Message "Fallback to robocopy failed because robocopy.exe could not be found. Path '$p'. $([datetime]::Now)."
                    return
                }
            }
            process {
                foreach ($p in $Path) {
                    Write-Verbose -Message "Processing path '$p' with Get-RoboFolderSizeInternal. $([datetime]::Now)."
                    $RoboCopyArgs = @("/L","/S","/NJH","/BYTES","/FP","/NC","/NDL","/TS","/XJ","/R:0","/W:0")
                    [datetime] $StartedTime = [datetime]::Now
                    [string] $Summary = robocopy $p NULL $RoboCopyArgs | Select-Object -Last 8
                    [datetime] $EndedTime = [datetime]::Now
                    [regex] $HeaderRegex = '\s+Total\s*Copied\s+Skipped\s+Mismatch\s+FAILED\s+Extras'
                    [regex] $DirLineRegex = 'Dirs\s*:\s*(?<DirCount>\d+)(?:\s*\d+){3}\s*(?<DirFailed>\d+)\s*\d+'
                    [regex] $FileLineRegex = 'Files\s*:\s*(?<FileCount>\d+)(?:\s*\d+){3}\s*(?<FileFailed>\d+)\s*\d+'
                    [regex] $BytesLineRegex = 'Bytes\s*:\s*(?<ByteCount>\d+)(?:\s*\d+){3}\s*(?<BytesFailed>\d+)\s*\d+'
                    [regex] $TimeLineRegex = 'Times\s*:\s*(?<TimeElapsed>\d+).*'
                    [regex] $EndedLineRegex = 'Ended\s*:\s*(?<EndedTime>.+)'
                    if ($Summary -match "$HeaderRegex\s+$DirLineRegex\s+$FileLineRegex\s+$BytesLineRegex\s+$TimeLineRegex\s+$EndedLineRegex") {
                        $TimeElapsed = [math]::Round([decimal] ($EndedTime - $StartedTime).TotalSeconds, $Precision)
                        New-Object PSObject -Property @{
                            Path = $p
                            TotalBytes = [decimal] $Matches['ByteCount']
                            TotalMBytes = [math]::Round(([decimal] $Matches['ByteCount'] / 1MB), $Precision)
                            TotalGBytes = [math]::Round(([decimal] $Matches['ByteCount'] / 1GB), $Precision)
                            BytesFailed = [decimal] $Matches['BytesFailed']
                            DirCount = [decimal] $Matches['DirCount']
                            FileCount = [decimal] $Matches['FileCount']
                            DirFailed = [decimal] $Matches['DirFailed']
                            FileFailed  = [decimal] $Matches['FileFailed']
                            TimeElapsed = $TimeElapsed
                            StartedTime = $StartedTime
                            EndedTime   = $EndedTime

                        } | Select Path, TotalBytes, TotalMBytes, TotalGBytes, DirCount, FileCount, DirFailed, FileFailed, TimeElapsed, StartedTime, EndedTime
                    }
                    else {
                        Write-Warning -Message "Path '$p' output from robocopy was not in an expected format."
                    }
                }
            }
        }
    }
    process {
        foreach ($p in $Path) {
            Write-Verbose -Message "Processing path '$p'. $([datetime]::Now)."
            if (-not (Test-Path -Path $p -PathType Container)) {
                Write-Warning -Message "$p does not exist or is a file and not a directory. Skipping."
                continue
            }
            if ($RoboOnly) {
                Get-RoboFolderSizeInternal -Path $p -Precision $Precision
                continue
            }
            $ErrorActionPreference = 'Stop'
            try {
                $StartFSOTime = [datetime]::Now
                $TotalBytes = $FSO.GetFolder($p).Size
                $EndFSOTime = [datetime]::Now
                if ($TotalBytes -eq $null) {
                    Get-RoboFolderSizeInternal -Path $p -Precision $Precision
                    continue
                }
            }
            catch {
                if ($_.Exception.Message -like '*PERMISSION*DENIED*') {
                    Write-Verbose "Caught a permission denied. Trying robocopy."
                    Get-RoboFolderSizeInternal -Path $p -Precision $Precision
                    continue
                }
                Write-Warning -Message "Encountered an error while processing path '$p': $_"
                continue
            }
            $ErrorActionPreference = 'Continue'
            New-Object PSObject -Property @{
                Path = $p
                TotalBytes = [decimal] $TotalBytes
                TotalMBytes = [math]::Round(([decimal] $TotalBytes / 1MB), $Precision)
                TotalGBytes = [math]::Round(([decimal] $TotalBytes / 1GB), $Precision)
                BytesFailed = $null
                DirCount = $null
                FileCount = $null
                DirFailed = $null
                FileFailed  = $null
                TimeElapsed = [math]::Round(([decimal] ($EndFSOTime - $StartFSOTime).TotalSeconds), $Precision)
                StartedTime = $StartFSOTime
                EndedTime = $EndFSOTime
            } | Select Path, TotalBytes, TotalMBytes, TotalGBytes, DirCount, FileCount, DirFailed, FileFailed, TimeElapsed, StartedTime, EndedTime
        }
    }
    end {
        [void][System.Runtime.Interopservices.Marshal]::ReleaseComObject($FSO)
        [gc]::Collect()
    }
}

# Wrapper around Get-FolderSize to get the size of all immediate subdirectories of a directory.
function Get-FolderSizeListing($path=".")
{
    if (-Not (Test-Path $path))
    {
        Write-Error "Could not find path: $path"
        Return
    }
    ls $path -Directory | %{$_.FullName} | Get-FolderSize | select Path,TotalMBytes,TotalGBytes
    Return
}

##############################
# Powershell utilities
##############################

# Adds a running index to a piped-in collection
Function Add-Index
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object] $Value
    )

    begin
    {
        $CurrentIndex = -1
    }

    process
    {
        $CurrentIndex += 1
        New-Object PSObject -Property @{ Index = $CurrentIndex; Value = $Value }
    }
}

# Creates an instance of an object given the generic type name. The type name
# SHOULD NOT include the marker for number of arguments (e.g. you should use
# 'System.Collections.Generic.List', not 'System.Collections.Generic.List`1').
Function New-GenericObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $TypeName,

        [Parameter(Mandatory=$true, Position=1)]
        [Alias('Of')]
        [string[]] $TypeParameters,

        [Parameter(Position=2)]
        [object[]] $ArgumentList
    )
    
    $NumTypeParams = $TypeParameters.Length
    if ($TypeParameters.Length -eq 0)
    {
        throw 'Expecting at least one type parameter'
    }
    # TODO: Given TypeName 'Bleh`X', confirm X == $NumTypeParams
    if (!($TypeName -match '`[\d]+$'))
    {
        $FullTypeName = $TypeName + "``$NumTypeParams"
    }
    else
    {
        $FullTypeName = $TypeName
    }

    $GenericTypeDef = $FullTypeName -as 'Type'
    $TypeParametersLit = ($TypeParameters | ForEach-Object { $_ -as 'Type' })
    $GenericType = $GenericTypeDef.MakeGenericType($TypeParametersLit)

    New-Object $GenericType -ArgumentList $ArgumentList
}

# Changes the foreground color of the terminal prompt back to the
# default (in this case, white).
Function Reset-ForegroundColor
{
    [console]::ForegroundColor = 'White'
}

# From: http://weblogs.asp.net/adweigert/powershell-adding-the-using-statement
# Allows the robust usage of an IDisposable within a script block.
Function Invoke-Using {
    param (
        [System.IDisposable] $inputObject = $(throw "The parameter -inputObject is required."),
        [ScriptBlock] $scriptBlock = $(throw "The parameter -scriptBlock is required.")
    )

    Try {
        &$scriptBlock
    } Finally {
        if ($inputObject -ne $null) {
            if ($inputObject.psbase -eq $null) {
                $inputObject.Dispose()
            } else {
                $inputObject.psbase.Dispose()
            }
        }
    }
}

New-Alias -Name Using-Object -Value Invoke-Using

# Creates a PSObject from the given properties.
Function New-PSObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [Hashtable] $Properties = @{}
    )

    process
    {
        New-Object PSObject -Property $Properties
    }
}

# Returns information about the different Powershell Profiles (AllUsersAllHosts, CurrentHostCurrentHost, etc.).
Function Get-ProfileInfo
{
    $ProfileTypes = $Profile | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name
    $ProfileTypes | % { @{Name = $_; Path = $Profile.$_; Exists = Test-Path $Profile.$_; } } | New-PSObject
}

##############################
# Unix standins/replacements
##############################

New-Alias -Name touch -Value Update-FileTimestampAttribute
New-Alias -Name grep -Value Select-String

# Basically an alias for `measure | select Count`
Function count
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [object[]] $Input
    )

    $Input | Measure-Object | Select-Object -Property Count
}

# A poor man's `tee`.
Function Out-ToFile ([string] $file, [string[]] $lines=$null, [switch] $Append)
{
    begin
    {
        $RedirectToFileBufferMaxSize = 500
        $RedirectToFileBuffer = @()
        if ($Append -And ($lines -ne $null))
        {
            Add-Content $file $lines
        }
        else
        {
            Set-Content $file $lines
        }
    }

    process
    {
        $RedirectToFileBuffer += $_
        if ($RedirectToFileBuffer -ge $RedirectToFileBufferMaxSize)
        {
            Add-Content $file $RedirectToFileBuffer
            $RedirectToFileBuffer = @()
        }
    }

    end
    {
        Add-Content $file $RedirectToFileBuffer
        $RedirectToFileBuffer = $null
    }
}

New-Alias -Name Redirect-ToFile -Value Out-ToFile

##############################
# Git utilities
##############################

# Gets the list of Git stashes in the given repo(s). Mainly used for keeping
# track of/managing stashes across different clones of the same repo.
Function Get-GitStashes
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string] $Repository = (git rev-parse --show-toplevel 2>$null),

        [switch] $IgnoreNonRepositories,

        [switch] $PassThru
    )

    process
    {
        Write-Verbose "$Repository"
        if ([string]::IsNullOrEmpty($Repository))
        {
            throw 'Could not get Git repository from current location. Navigate to a Git repository or supply one as a parameter.'
        }
        elseif (!(Test-Path $Repository -PathType Any))
        {
            throw "Path $Repository does not exist."
        }
        elseif (!(Test-Path $Repository -PathType Container))
        {
            throw "Path $Repository is not a directory."
        }
        else
        {
            $FullRepository = Resolve-Path -Path $Repository
            Write-Verbose "Getting stash for: $FullRepository"
            Push-Location $FullRepository
            try
            {
                $Stashes = (git stash list 2>$null)
                $IsRepo = $LASTEXITCODE -eq 0
            }
            finally
            {
                Pop-Location
            }

            if (!$IsRepo)
            {
                if (!$IgnoreNonRepositories)
                {
                    Write-Warning "Failed to get stashes: $FullRepository may not be a Git repository."
                }
                else
                {
                    Write-Verbose "Skipping non-repository $FullRepository"
                }
            }
            else
            {
                if ($PassThru)
                {
                    @{Repository = $FullRepository; Stashes = $Stashes} | New-PSObject
                }
                else
                {
                    Write-Host "$FullRepository`:"
                    $Stashes | Write-Host
                    Write-Host
                }
            }
        }
    }
}

# Removes branches in the current Git repository that track a no-
# longer-existing remote branch.
Function Remove-OrphanedLocalBranches
{
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [switch] $DryRun,

        [switch] $Force
    )

    if ($DryRun -and $Force)
    {
        Write-Warning 'Both -DryRun and -Force specified; ignoring -Force'
    }

    if (!(Test-InGitRepo))
    {
        throw 'Not in a Git repo'
    }
    else
    {
        $Orphans = (git branch -vv | Where-Object { $_ -match '\[.*gone\]' } | ForEach-Object { $_.TrimStart().Split()[0] })
        if ($DryRun)
        {
            if ($Orphans.Count -gt 0)
            {
                Write-Host 'Running this command without -DryRun will delete the following branches:'
                $Orphans | Write-Host
            }
            else
            {
                Write-Host 'Running this command without -DryRun will delete no branches.'
            }
        }
        else
        {
            foreach ($Orphan in $Orphans)
            {
                if (!$Force -and !$PSCmdlet.ShouldProcess("local branch: $Orphan", 'delete'))
                {
                    Write-Warning "Skipping $Orphan"
                }
                else
                {
                    git branch -d $Orphan
                }
            }
        }
    }
}

# Returns true if cwd is in a Git repo, false otherwise.
Function Test-InGitRepo
{
    git rev-parse --show-top-level 2>&1 | Out-Null
    $?
}

# Removes all files untracked by Git in the current repo.
function Remove-UntrackedFiles
{
    [CmdletBinding()]
    param (
        [string] $Pattern,

        [switch] $WhatIf
    )

    if ([String]::IsNullOrEmpty($Pattern))
    {
        $Pattern = "*"
    }

    $filesToRemove = (git status --short | ? {$_ -like '[?][?] *'} | ForEach-Object {$_.TrimStart('?? ')} | ? {$_ -like "$Pattern"})
    if ($filesToRemove -ne $null)
    {
        foreach ($f in $filesToRemove)
        {
            Remove-Item -Recurse (Resolve-Path $f) -WhatIf:$WhatIf
        }
    }
}

##################################
# Assorted workflow utilities
##################################

# Opens the given file in Notepad++.
Function Open-InNotepadPP ($file)
{
    & "C:\Program Files (x86)\Notepad++\notepad++.exe" $file
}

# Compiles a UML diagram from the given path. Assumes that java.exe is in
# the current user's path and that the PlantUML jar is located somewhere.
function New-PlantUmlDiagram
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]
        $Path,

        [string]
        $JarPath = "$HOME\bin\plantuml.jar"
    )

    process {
        $pathNorm = Resolve-Path $Path
        if ($pathNorm -ne $null)
        {
            Write-Verbose "Compiling diagram at '$Path'"

            # Paths are quoted b/c we're calling out of Powershell land
            java -jar "$JarPath" "$pathNorm"
            if ($LastExitCode -ne 0)
            {
                throw "Failed to compile PlantUML diagram in '$Path'"
            }
        }
    }
}

New-Alias -Name "Compile-PlantUmlDiagram" -Value "New-PlantUmlDiagram"

###################################
# Vim editing
###################################

# From: http://www.expatpaul.eu/2014/04/vim-in-powershell/

Set-Alias vim "C:\Program Files (x86)\Vim\vim80\vim.exe"

# To edit the Powershell Profile
Function Edit-Profile
{
    vim $profile.CurrentUserCurrentHost
}

# To edit Vim settings
Function Edit-Vimrc
{
    vim $HOME\_vimrc
}

# To edit the AutoHotkey profile
Function Edit-AutoHotKey
{
    vim $HOME\profile.ahk
}
