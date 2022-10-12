###############################
# Filesystem utilities
###############################

# Returns better-formatted drive info
function Get-DriveInfo
{
    [CmdletBinding()]
    param ()

    $drives = [System.IO.DriveInfo]::GetDrives()
    $drives | Select-Object -Property `
        Name,
        DriveType,
        RootDirectory,
        VolumeLabel,
        @{ Name = 'AvailableFreeSpaceGBs'; Expression = { $_.AvailableFreeSpace / 1GB } },
        @{ Name = 'TotalFreeSpaceGBs'; Expression = { $_.TotalFreeSpace / 1GB } },
        @{ Name = 'TotalSizeGBs'; Expression = { $_.TotalSize / 1GB } },
        @{ Name = 'ProportionSpaceFree'; Expression = { $_.AvailableFreeSpace / $_.TotalSize } }
}

# Returns most commonly-used system info in simple format
function Get-SystemInfo
{
    [CmdletBinding()]
    param ()

    $refComputer = Get-CimInstance Win32_OperatingSystem
    $refProcessor = Get-CimInstance Win32_Processor
    $properties = [ordered] @{
        ComputerName = $env:COMPUTERNAME
        OSVersion = $refComputer.Version
        OSReleaseID = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\').ReleaseID
        AvailableMemoryGBs = [Math]::Round($refComputer.FreePhysicalMemory / 1MB, 2)
        TotalMemoryGBs = [Math]::Round($refComputer.TotalVisibleMemorySize / 1MB, 2)
        PercentMemoryFree = ([Math]::Round($refComputer.FreePhysicalMemory / $refComputer.TotalVisibleMemorySize, 2)) * 100
        NumberOfProcessors = $env:NUMBER_OF_PROCESSORS
        PercentCpuUtilized = $refProcessor.LoadPercentage
    }

    foreach ($drive in ([System.IO.DriveInfo]::GetDrives()))
    {
        $name = $drive.Name.Replace(':\', '')
        $properties["${name}_TotalFreeSpaceGBs"] = [Math]::Round($drive.TotalFreeSpace / 1GB, 2)
        $properties["${name}_TotalSizeGBs"] = [Math]::Round($drive.TotalSize / 1GB, 2)
        $properties["${name}_PercentSpaceFree"] = ([Math]::Round($drive.TotalFreeSpace / $drive.TotalSize, 2)) * 100
    }

    New-Object PSObject -Property $properties
}

# Updates the relevant timestamp for the given file.
function Update-FileTimestampAttribute
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string] $Path,

        [ValidateSet('Write','Access','WriteAccess')]
        [string] $Property = 'WriteAccess',

        [switch] $PassThru
    )

    process
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

        [switch] $IncludeDirectories,

        [switch] $NoRecurse
    )

    if (!(Test-Path -PathType Container -Path $From))
    {
        throw "Could not find 'From' directory at $From"
    }
    if (!(Test-Path -PathType Container -Path $To))
    {
        throw "Could not find 'To' directory at $To"
    }

    $FromListing = Get-FileListing -Root $From -IncludeDirectories:$IncludeDirectories -NoRecurse:$NoRecurse
    $ToListing = Get-FileListing -Root $To -IncludeDirectories:$IncludeDirectories -NoRecurse:$NoRecurse

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

        [switch] $IncludeDirectories,

        [switch] $NoRecurse
    )

    # Using `Get-Item | Select-Object FullName` here instead of `Resolve-Path` b/c
    # Resolve-Path includes the entire PSDrive identifier if it's not on a standard
    # file system path (e.g. SMB share, registry, etc.)
    $FullRoot = Get-Item $Root | Select-Object -ExpandProperty FullName
    $FullRoot = $FullRoot.TrimEnd('\') + '\'
    $FullRootPattern = "^$([Regex]::Escape($FullRoot))"

    Get-ChildItem -Recurse:(!$NoRecurse) -Path $FullRoot -File:(!$IncludeDirectories) |
        Select-Object -ExpandProperty FullName |
        ForEach-Object { $_ -replace $FullRootPattern, '' } |
        Sort-Object
}

function Get-Children
{
    [CmdletBinding()]
    param (
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string] $Path = '.',

        [string] $Filter = ''
    )

    begin
    {
        $found = New-Object System.Collections.Generic.List[string]
        $next = New-Object System.Collections.Generic.List[string]

        $initial = (Resolve-Path $Path).Path
        $next.Add($initial)

        while ($next.Count -gt 0)
        {
            $dir = $next[0]
            $next.RemoveAt(0)

            $files = [System.IO.Directory]::GetFiles($dir)
            foreach ($f in $files)
            {
                if ($f -match $Filter)
                {
                    $found.Add($f)
                }
            }

            $subDirectories = [System.IO.Directory]::GetDirectories($dir)
            $next.AddRange($subDirectories)
        }

        $found
    }
}

# Uses robocopy to delete long file paths that posh/explorer can't
function Remove-LongFilePath
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
function ConvertTo-Encoding
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
function Get-ChildSizes
{
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [string] $Directory = '.',

        [switch] $IncludeFiles
    )

    process
    {
        If (-Not (Get-Item -Force $Directory) -is [System.IO.DirectoryInfo])
        {
            throw [System.ArgumentException] "$Directory is not a directory or does not exist.`n"
        }
        Get-ChildItem -Force -Path $Directory -Directory:(!$IncludeFiles) | Get-FolderSize
    }
}

# Gets the size of a given folder. Did not write it myself,
# but don't know where it came from.
function Get-FolderSize
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        [int] $Precision = 4,

        [switch] $RoboOnly
    )

    begin
    {
        $FSO = New-Object -ComObject Scripting.FileSystemObject -ErrorAction Stop
        function Get-RoboFolderSizeInternal
        {
            [CmdletBinding()]
            param(
                # Paths to report size, file count, dir count, etc. for.
                [string[]] $Path,
                [int] $Precision = 4
            )
            begin
            {
                if (-not (Get-Command -Name robocopy -ErrorAction SilentlyContinue))
                {
                    Write-Warning -Message "Fallback to robocopy failed because robocopy.exe could not be found. Path '$p'. $([datetime]::Now)."
                    return
                }
            }
            process
            {
                foreach ($p in $Path)
                {
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
                    if ($Summary -match "$HeaderRegex\s+$DirLineRegex\s+$FileLineRegex\s+$BytesLineRegex\s+$TimeLineRegex\s+$EndedLineRegex")
                    {
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
                    else
                    {
                        Write-Warning -Message "Path '$p' output from robocopy was not in an expected format."
                    }
                }
            }
        }
    }

    process
    {
        $p = (Resolve-Path $Path).Path
        Write-Verbose -Message "Processing path '$p'. $([datetime]::Now)."
        if (-not (Test-Path -Path $p -PathType Container))
        {
            Write-Warning -Message "$p does not exist or is a file and not a directory. Skipping."
            return
        }
        if ($RoboOnly)
        {
            Get-RoboFolderSizeInternal -Path $p -Precision $Precision
            return
        }
        $ErrorActionPreference = 'Stop'
        try
        {
            $StartFSOTime = [datetime]::Now
            $TotalBytes = $FSO.GetFolder($p).Size
            $EndFSOTime = [datetime]::Now
            if ($TotalBytes -eq $null)
            {
                Get-RoboFolderSizeInternal -Path $p -Precision $Precision
                return;
            }
        }
        catch
        {
            if ($_.Exception.Message -like '*PERMISSION*DENIED*')
            {
                Write-Verbose "Caught a permission denied. Trying robocopy."
                Get-RoboFolderSizeInternal -Path $p -Precision $Precision
                return
            }
            else
            {
                Write-Warning -Message "Encountered an error while processing path '$p': $_"
                return
            }
            
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
        } | Select-Object Path, TotalBytes, TotalMBytes, TotalGBytes, DirCount, FileCount, DirFailed, FileFailed, TimeElapsed, StartedTime, EndedTime
    }

    end
    {
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
function Add-Index
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
function New-GenericObject
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
function Reset-ForegroundColor
{
    [console]::ForegroundColor = 'White'
}

# From: http://weblogs.asp.net/adweigert/powershell-adding-the-using-statement
# Allows the robust usage of an IDisposable within a script block.
function Invoke-Using {
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
function New-PSObject
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
function Get-ProfileInfo
{
    $ProfileTypes = $Profile | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name
    $ProfileTypes | % { @{Name = $_; Path = $Profile.$_; Exists = Test-Path $Profile.$_; } } | New-PSObject
}

# Simple alias for resolving DNS names
function dns
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)]
        [string] $Name,

        [ValidateNotNullOrEmpty]
        [string] $Server,

        [switch] $Reverse
    )

    $params = @{ Name = $Name }
    if ($Server)
    {
        $params.Server = $Server
    }
    if ($Reverse)
    {
        $params.Type = 'PTR'
    }

    Resolve-DnsName @params
}

##############################
# Unix standins/replacements
##############################

function Edit-String
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)]
        [string] $FindPattern,

        [Parameter(Position=1)]
        [string] $ReplacePattern,

        [Parameter(ValueFromPipeline)]
        [string] $Content
    )

    process
    {
        $Content -Replace $FindPattern, $ReplacePattern
    }
}

function Find-String
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)]
        [string] $Pattern,

        [Parameter(ValueFromPipeline)]
        [string] $Content
    )

    process
    {
        if ($Content -match $Pattern) { $Content }
    }
}

# Basically an alias for `measure | select Count`
function Measure-ObjectCount
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [object[]] $Input
    )

    $Input | Measure-Object | Select-Object -Property Count
}

# A poor man's `tee`.
function Out-ToFile ([string] $file, [string[]] $lines=$null, [switch] $Append)
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

function Get-InstalledProgram
{
    [CmdletBinding()]
    param (
        [switch] $Detailed
    )

    $properties = if ($Detailed) { @('*') } else { @('DisplayName', 'DisplayVersion', 'Publisher', 'NoModify', 'NoRepair', 'UninstallString') }

    Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ |
        Get-ItemProperty |
        Select-Object -Property $properties
}

function Get-FileTimestamp
{
    [CmdletBinding()]
    param (
        [switch] $UTC,

        [ValidateSet('Day', 'Hour', 'Minute', 'Second', 'Millisecond')]
        [string] $Resolution = 'Second'
    )

    $date = Get-Date
    if ($UTC)
    {
        $date = $date.ToUniversalTime()
    }

    $formats = @{
        Day         = 'yyyyMMdd'
        Hour        = 'yyyyMMdd\THH'
        Minute      = 'yyyyMMdd\THHmm'
        Second      = 'yyyyMMdd\THHmmss'
        Millisecond = 'yyyyMMdd\THHmmssfff'
    }

    $date | Get-Date -Format $formats[$Resolution]
}

function Invoke-ForEachObject
{

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)]
        [string] $Command,

        [Parameter(Position=1, ValueFromRemainingArguments)]
        [string[]] $Arguments = @(),

        [Parameter(ValueFromPipeline)]
        [object] $InputObject
    )

    process
    {
        $inputProcessed = $false

        $processedArguments = New-Object System.Collections.ArrayList
        foreach ($arg in $Arguments)
        {
            if ($arg -match '{}')
            {
                $processedArg = $arg -replace '{}', $InputObject
                $inputProcessed = $true
            }
            else
            {
                $processedArg = $arg
            }
            $null = $processedArguments.Add($processedArg)
        }

        if ($inputProcessed)
        {
            $expr = "${Command} $($processedArguments -join ' ')"
        }
        else
        {
            $expr = "${Command} $($processedArguments -join ' ') $InputObject"
        }

        Write-Verbose "Invoking: $expr"
        Invoke-Expression $expr
    }
}

# NB: This is a pretty naive implementation, so it's not going to be anywhere
# as fast as `cut`, but it doesn't do anything that's particularly slow in PowerShell,
# so it should be fine for day-to-day.
function Split-String
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position=0)]
        [string] $Delimiter,

        [Parameter(Mandatory, Position=1)]
        [string] $Fields,

        [Parameter(ValueFromPipeline)]
        [string] $InputString
    )

    begin
    {
        if ([string]::IsNullOrEmpty($Delimiter))
        {
            throw "Expected valid, non-empty delimeter, instead got: '$Delimiter'"
        }

        function NewSpec([Nullable[int]] $From, [Nullable[int]] $To)
        {
            [PSCustomObject] @{ From = $From; To = $To }
        }

        function ValidateField([string] $Field)
        {
            $i = [int] $Field
            if ($i -le 0)
            {
                throw "Fields are numbered from 1"
            }
            $i
        }

        function ParseFields([string] $Fields)
        {
            # We're basically just copying the various `cut` formations:
            #     num   : /\d+/
            #     range : <num> '-' <num> | <num> '-' | '-' <num>
            #     spec  : <num> | <range>
            #     list  : <spec> (',' <spec>)*
            # Valid input is: <list>

            $specs = @($Fields -split ',')
            $parsedSpecs = New-Object System.Collections.ArrayList
            foreach ($spec in $specs)
            {
                if ($spec -match '^(\d+)-(\d+)$')
                {
                    $from = ValidateField $Matches[1]
                    $to = ValidateField $Matches[2]
                    if ($from -gt $to)
                    {
                        throw "Invalid field range: $($Matches[0])"
                    }
                    $parsed = NewSpec $from $to
                }
                elseif ($spec -match '^(\d+)-$')
                {
                    $from = ValidateField $Matches[1]
                    $parsed = NewSpec $from $null
                }
                elseif ($spec -match '^-(\d+)$')
                {
                    $to = ValidateField $Matches[1]
                    $parsed = NewSpec $null $to
                }
                elseif ($spec -match '^\d+$')
                {
                    $field = ValidateField $Matches[0]
                    $parsed = NewSpec $field $field
                }
                else
                {
                    throw "Invalid field specification: $spec"
                }
                $null = $parsedSpecs.Add($parsed)
            }

            return $parsedSpecs
        }

        $fieldSpecs = ParseFields $Fields

        function InRangeOf([int] $Number, $FieldSpec)
        {
            if ($null -eq $FieldSpec.From)
            {
                $Number -le $FieldSpec.To
            }
            elseif ($null -eq $FieldSpec.To)
            {
                $Number -ge $FieldSpec.From
            }
            else
            {
                $Number -ge $FieldSpec.From -and $Number -le $FieldSpec.To
            }
        }

        $lastHighestLength = 0
        $matchingIndices = New-Object System.Collections.ArrayList
    }

    process
    {
        # This isn't how `cut` works but after some experimentation I don't
        # really like how `cut` handles multiple delimiters in a row, so we're
        # doin' it my way baybeeee
        $split = @($InputString.Split($Delimiter, [System.StringSplitOptions]::RemoveEmptyEntries))
        if ($split.Length -le 1)
        {
            Write-Output $split
        }
        else
        {
            # This saves us on processing the field specs each time for every index.
            # We calculate the indices determined by the field spec only for indices that we haven't seen yet,
            # i.e. for the portion of the split input string that is beyond the longest split input string we've
            # seen so far. Consider if the biggest number of fields we last saw was 3:
            # - If we see an input with only <= 3 fields, we already have the matching indices cached.
            # - If we see an input with 6 fields, we'll only check if indices 3, 4, and 5 meet the criteria,
            #   and then we'll add those to the cache. Then we don't have to check again for any number of fields
            #   less than or equal to 6.

            if ($split.Length -gt $lastHighestLength)
            {
                $remainingIndices = New-Object System.Collections.ArrayList(,($lastHighestLength .. ($split.Length - 1)))
                foreach ($spec in $fieldSpecs)
                {
                    # We gotta do a little song and dance here so we don't modify a collection
                    # as we iterate through it.
                    for ($j = 0; $j -lt $remainingIndices.Count; $j++)
                    {
                        $i = $remainingIndices[$j]
                        #Write-Host "testing:" ($i+1) $spec
                        if (InRangeOf ($i+1) $spec)
                        {
                            #Write-Host "match:" ($i+1) $spec
                            $null = $matchingIndices.Add($i)
                            $remainingIndices.RemoveAt($j)
                            $j--
                        }
                    }
                }
                $lastHighestLength = $split.Length
            }

            $outputEls = New-Object System.Collections.ArrayList
            foreach ($i in $matchingIndices)
            {
                $null = $outputEls.Add($split[$i])
            }
            $output = $outputEls -join $Delimiter
            Write-Output $output
        }
    }
}

New-Alias -Name Redirect-ToFile -Value Out-ToFile

# Unix-y aliases
New-Alias -Name count -Value Measure-ObjectCount
New-Alias -Name touch -Value Update-FileTimestampAttribute
New-Alias -Name sed -Value Edit-String
New-Alias -Name grep -Value Find-String
New-Alias -Name xargs -Value Invoke-ForEachObject
New-Alias -Name cut -Value Split-String

##############################
# Git utilities
##############################

# Tests whether the given path represents a Git repo.
function Test-GitRepo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string] $Repository = (Get-Location).Path
    )

    process
    {
        if (Test-Path -Path $Repository -PathType Container)
        {
            Push-Location -Path $Repository
            try
            {
                & git rev-parse --show-toplevel 2>&1 >$null
                $LastExitCode -eq 0
            }
            finally
            {
                Pop-Location
            }
        }
        else
        {
            $false
        }
    }
}

# Gets the list of Git stashes in the given repo(s). Mainly used for keeping
# track of/managing stashes across different clones of the same repo.
function Get-GitStashes
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
        [Alias('FullName')]
        [string] $Repository = (git rev-parse --show-toplevel 2>$null),

        [switch] $IgnoreNonRepositories,

        [switch] $PassThru
    )

    process
    {
        if ([string]::IsNullOrEmpty($Repository))
        {
            throw 'Could not get Git repository from current location. Navigate to a Git repository or supply one as a parameter.'
        }
        $repositoryPaths = Get-Item -Path $Repository
        foreach ($repositoryPath in $repositoryPaths)
        {
            $isDirectory = Test-Path -Path $repositoryPath -PathType Container
            if (!$isDirectory -and !$IgnoreNonRepositories)
            {
                Write-Error "Not a directory: $repositoryPath"
            }
            elseif (!$isDirectory)
            {
                Write-Verbose "Skipping non-repository $repositoryPath"
            }
            else
            {
                $fullRepository = Resolve-Path -Path $repositoryPath
                Write-Verbose "Getting stash for: $fullRepository"
                Push-Location $fullRepository
                try
                {
                    $stashes = (git stash list 2>$null)
                    $isRepo = $LASTEXITCODE -eq 0
                }
                finally
                {
                    Pop-Location
                }

                if (!$isRepo)
                {
                    if (!$IgnoreNonRepositories)
                    {
                        Write-Warning "Failed to get stashes: $fullRepository may not be a Git repository."
                    }
                    else
                    {
                        Write-Verbose "Skipping non-repository $fullRepository"
                    }
                }
                else
                {
                    if ($PassThru)
                    {
                        @{Repository = $fullRepository; Stashes = $stashes} | New-PSObject
                    }
                    else
                    {
                        Write-Host "$fullRepository`:"
                        if (-not ([string]::IsNullOrEmpty($stashes)))
                        {
                            $stashes | Write-Host
                        }
                        else
                        {
                            Write-Host '<none>'
                        }
                        Write-Host
                    }
                }
            }
        }
    }
}

New-Alias -Name List-GitStashes -Value Get-GitStashes

function Remove-AllOtherLocalBranches
{
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [switch] $Force
    )

    if (!(Test-GitRepo))
    {
        throw 'Not in a Git repo'
    }
    else
    {
        $localBranches = git branch | grep '^\s*[^*]' | ForEach-Object Trim -WhatIf:$false
        foreach ($branch in $localBranches)
        {
            if (($Force -and !$WhatIfPreference) -or $PSCmdlet.ShouldProcess("local branch: $branch", 'delete'))
            {
                $output = git branch -D $branch 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    Write-Error "Failed to delete branch $branch; Git output:`n$output"
                }
                else
                {
                    Write-Verbose "GIT: $output"
                }
            }
        }
    }
}

# Removes branches in the current Git repository that track a no-
# longer-existing remote branch.
function Remove-OrphanedLocalBranches
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

    if (!(Test-GitRepo))
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
                    git branch -D $Orphan
                }
            }
        }
    }
}

<#
    Invokes a script block on each Git branch in the given repository.

    - TODO: Remove all local branches created by this script (optional?)
    - TODO: Exit if git errors out
        - sub-TODO: Make it amenable to ErrorAction
#>
function Invoke-GitBranch
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param (
        [Parameter(Position=0)]
        [ScriptBlock] $Expression,

        [string] $GitRoot = '.',

        [string] $BranchFilter = '',

        [switch] $IncludeRemotes,

        [switch] $Force,

        [switch] $AsObject
    )

    Push-Location $GitRoot
    try
    {
        $originalBranch = & git rev-parse --abbrev-ref HEAD
        $branches = & git branch -a |
                    ForEach-Object {
                        if ($_ -match '^\s+remotes/origin/([^\s]*)' -and $IncludeRemotes)
                        {
                            # Remote branches
                            $Matches[1]
                        }
                        elseif ($_ -match '^\*\s+([^\s]*)')
                        {
                            # Current branch
                            $Matches[1]
                        }
                        elseif ($_ -match '^\s+(?!\s*remotes/)')
                        {
                            # Local branches
                            $_.TrimStart(' ')
                        }
                    } |
                    Sort-Object -Unique | Where-Object { $_ -ne 'HEAD' }

        foreach ($branch in $branches)
        {
            if (($branch -match $BranchFilter) -and $PSCmdlet.ShouldProcess($branch, "Checkout and invoke expression"))
            {
                & git checkout $branch 2>&1 | Write-Verbose
                $output = $branch | ForEach-Object $Expression
                if ($AsObject)
                {
                    New-Object PSObject -Property @{Branch = $branch; Value = $output}
                }
                else
                {
                    $output
                }
            }
        }
    }
    finally
    {
        & git checkout $originalBranch 2>&1 | Write-Verbose
        Pop-Location
    }
}

New-Alias -Name ForEach-GitBranch -Value Invoke-GitBranch

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
        $Pattern = ".*"
    }

    $filesToRemove = (git status --short | ? {$_ -like '[?][?] *'} | ForEach-Object {$_.TrimStart('?? ')} | ? {$_ -match "$Pattern"})
    if ($filesToRemove -ne $null)
    {
        foreach ($f in $filesToRemove)
        {
            Remove-Item -Recurse -Force (Resolve-Path $f) -WhatIf:$WhatIf
        }
    }
}

# Returns all open PRs for the given orgs & repos.
function Get-OpenGitHubPullRequest
{
    param (
        [string[]] $Organizations = @('relativityone','relativitydev'),
        [string] $RepositoryFilter = '^testdk',
        [switch] $SkipDependabot
    )

    $statusMap = @{
        'COMMENTED'         = '\xF0\x9F\x92\xAC' # 💬
        'REVIEW_REQUIRED'   = '\u231A' # ⌚
        'CHANGES_REQUESTED' = '\u274C' # ❌
        'APPROVED'          = '\u2705' # ✅
        ''                  = '\u2754' # ❔
    }

    $prFilter = 'true'
    if ($SkipDependabot)
    {
        $prFilter = 'ne .author.login \"dependabot\"'
    }

    $reviewDecisionBlock = ''
    foreach ($status in $statusMap.Keys)
    {
        $reviewDecisionBlock += "{{if eq .reviewDecision \`"${status}\`"}}{{print \`"$($statusMap[$status])\`"}}{{end}}"
    }

    $reviewStateBlock = ''
    foreach ($status in $statusMap.Keys)
    {
        $reviewStateBlock += "{{if eq .state \`"${status}\`"}}{{print \`"$($statusMap[$status])\`"}}{{end}}"
    }

    $outputTemplate =
"{{range .}}" +
    "{{if ${prFilter}}}" +
        "${reviewDecisionBlock} {{print .title}}: {{printf \`"%s\n\t\`" .url}}" +
            "review-decision: {{if eq .reviewDecision \`"\`"}}{{print \`"\`"}}{{else}}{{print .reviewDecision}}{{end}}{{print \`"\n\t\`"}}" +
            "author: {{printf \`"%s\n\t\`" .author.login}}" +
            "created-at: {{printf \`"%s\n\t\`" .createdAt}}" +
            "reviews:{{print \`"\n\`"}}" +
            "{{range .latestReviews}}" +
                "{{print \`"\t\t\`" }}${reviewStateBlock} {{printf \`"%s\n\`" .author.login }}" +
            "{{else}}" +
                "{{print \`"\t\tNo reviews.\n\`"}}" +
            "{{end}}" +
    "{{end}}" +
"{{end}}"
    foreach ($org in $Organizations)
    {
        gh repo list "${org}" --limit 1000 --json name,nameWithOwner --jq ".[] | select(.name | test(\`"${RepositoryFilter}\`")) | .nameWithOwner" |
            ForEach-Object {
                gh pr list --repo "${_}" --json author,createdAt,id,title,body,url,reviewDecision,latestReviews --template "${outputTemplate}"
            }
    }
}

New-Alias -Name gh-prs -Value Get-OpenGitHubPullRequest

# These two are posh-git specific - they disable & enable the post-git
# prompt on PowerShell, respectively.

Function Disable-PoshGitPrompt
{
    $GitPromptSettings.EnablePromptStatus = $false
}

Function Enable-PoshGitPrompt
{
    $GitPromptSettings.EnablePromptStatus = $true
}

##################################
# Assorted workflow utilities
##################################

function Open-InChrome
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string] $Path
    )

    process
    {
        $FullPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
        if ($FullPath -eq $null)
        {
            Write-Error "Could not find path $Path"
        }
        else
        {
            Write-Verbose "Provided path $Path resolved to $FullPath"
            $Uri = New-Object System.Uri -ArgumentList $FullPath
            Start-Process 'chrome.exe' "$($Uri.AbsolutePath)", '--profile-directory="Default"'
        }
    }
}

# Opens the given file in Notepad++.
function Open-InNotepadPP
{
    param (
        [Parameter(ValueFromPipeline)]
        [string] $File
    )

    process
    {
        & "C:\Program Files (x86)\Notepad++\notepad++.exe" $File
    }
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

Set-Alias vim "C:\tools\neovim\Neovim\bin\nvim.exe"

# To edit the Powershell Profile
function Edit-Profile
{
    vim $profile.CurrentUserCurrentHost
}

# To edit Vim settings
function Edit-Vimrc
{
    vim $HOME\_vimrc
}

# To edit the AutoHotkey profile
function Edit-AutoHotKey
{
    vim $HOME\profile.ahk
}

function Edit-Todo
{
    vim $HOME\todo.txt
}

function Edit-HostsFile
{
    vim C:\Windows\System32\drivers\etc\hosts
}

function Edit-TerminalSettings
{
    vim "$(Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')"
}
