Function List-Out ($dir)
{
    Write-Output "$dir"
	Function List-Out_R ($dir, $chars)
	{
		If ((Get-Item $dir) -is [System.IO.DirectoryInfo])
		{        
			$children = Get-ChildItem $dir
			foreach ($c in $children)
			{
				
				Write-Output "$chars$c"
				List-Out_R "$dir\\$c" "-$chars"
			}
		}
	}
    List-Out_R $dir "-|"
}

Function Get-Size ($file) 
{
    If ((Get-Item $file) -is [System.IO.DirectoryInfo])
    {
        return (Get-ChildItem $file | ForEach-Object { Get-Size ("$file\\$($_.Name)") } | Measure-Object -Sum).Sum
    }
    Else
    {
        return (Get-Item $file).Length / ([Math]::Pow(1024,2))
    }
}

Function Get-ChildSizes ($dir=".\")
{
    If (-Not (Get-Item $dir) -is [System.IO.DirectoryInfo])
    {
        throw [System.ArgumentException] "$dir is not a directory or does not exist.`n"
    }
    Get-ChildItem $dir | Format-Table Name, @{Label="Size"; Expression={"{0:N4} MB" -f (Get-Size "$dir\\$($_.Name)")}}
}

Function Kill-AgentsProcess () {
	$proc = (Get-Process | where {$_.Name -Like "*kCura.Agent.Manager.WinForm*"})
	If ($proc)
	{
		Stop-Process $proc
		Return $?
	}
	Return $true
}

Function Open-InNotepadPP ($file)
{
    & "C:\Program Files (x86)\Notepad++\notepad++.exe" $file
}

Function Redirect-ToFile ([string] $file, [string[]] $lines=$null, [switch] $Append)
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

# From: http://weblogs.asp.net/adweigert/powershell-adding-the-using-statement
Function Using-Object {
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

function Get-FolderSize {
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

function ll
{
    ls | sort -Property LastWriteTime
}

###################################
# Vim editing
###################################

# From: http://www.expatpaul.eu/2014/04/vim-in-powershell/

Set-Alias vim "C:/Program Files (x86)/Vim/Vim74/./vim.exe"

# To edit the Powershell Profile
# (Not that I'll remember this)
Function Edit-Profile
{
    vim $profile.AllUsersAllHosts
}

# To edit Vim settings
Function Edit-Vimrc
{
    vim $HOME\_vimrc
}

Function Edit-AutoHotKey
{
    vim $HOME\profile.ahk
}