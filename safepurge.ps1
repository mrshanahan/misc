# Author: Matt Shanahan
# Dumb little script to back up untracked files in AppData if you forget to add them before you purge.

$HgRoot = (hg root 2>&1)
if ($HgRoot.GetType() -ne [String]) {
	Write-Error $HgRoot[0]
	Exit -1
}
$FilesToPurge = (hg st | where {$_ -Match "^\? "} | %{$_ -Replace "^\? ", ""} | %{Join-Path $HgRoot $_})
$RootTrimRegex = [Regex]"^(\w:(\\)?|\\+)"
if ($FilesToPurge) {
	$PurgeDataRoot = "$env:APPDATA\SafePurge"
	mkdir -Force $PurgeDataRoot >$null
	$Timestamp = [System.DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
	$PurgeDataFolder = (Join-Path $PurgeDataRoot $Timestamp)
	mkdir -Force $PurgeDataFolder >$null
	Write-Output "Backing up the following files:"
	foreach ($file in $FilesToPurge) {
		$FileObj = (gi $file)
		$Parent = (gi $file).DirectoryName
		$ParentNoRoot = $RootTrimRegex.Replace($parent, "")
		$SafePurgeTarget = Join-Path $PurgeDataFolder $parentNoRoot
		if (!(Test-Path $SafePurgeTarget)) {
			mkdir -Force $SafePurgeTarget >$null
		}
		Write-Output ([string]::Format("{0} -> {1}", $file, (Join-Path $SafePurgeTarget (Split-Path -Leaf $file))))
	}
}
Write-Output "hg purge --all"
hg purge --all
