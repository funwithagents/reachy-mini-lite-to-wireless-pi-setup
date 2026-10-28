# PowerShell script to prepare an SD card for Reachy Mini daemon installation

param (
    [string]$DriveLetter,
    [string]$RepoUrl = "https://github.com/pollen-robotics/reachy_mini.git",
    [switch]$Force
)

function Normalize-DriveLetter {
    param([string]$Value)

    if (-not $Value) {
        return $null
    }

    $normalized = $Value.Trim().TrimEnd('\\').TrimEnd(':')
    if ($normalized.Length -ne 1) {
        Write-Error "Invalid drive letter '$Value'. Use a single letter, e.g. E or E:."
        exit 1
    }

    return $normalized.ToUpper()
}

function Get-BootPartitionCandidates {
    $requiredFiles = @("config.txt", "cmdline.txt")

    $volumes = Get-Volume -ErrorAction Stop |
        Where-Object { $_.DriveLetter -and $_.FileSystem -eq "FAT32" }

    $candidates = foreach ($volume in $volumes) {
        $dl = [string]$volume.DriveLetter
        $root = "${dl}:\\"
        if (-not (Test-Path $root)) {
            continue
        }

        $missingFiles = @()
        foreach ($required in $requiredFiles) {
            if (-not (Test-Path (Join-Path $root $required))) {
                $missingFiles += $required
            }
        }

        $label = [string]$volume.FileSystemLabel
        $labelMatch = $label -eq "bootfs"
        $hasRequiredFiles = $missingFiles.Count -eq 0
        $score = 0
        if ($labelMatch) {
            $score += 2
        }
        if ($hasRequiredFiles) {
            $score += 2
        }

        [PSCustomObject]@{
            DriveLetter      = $dl
            Root             = $root
            Label            = $label
            HasRequiredFiles = $hasRequiredFiles
            MissingFiles     = $missingFiles
            Score            = $score
        }
    }

    return $candidates | Where-Object { $_.Score -gt 0 }
}

$normalizedDriveLetter = Normalize-DriveLetter $DriveLetter
$candidates = Get-BootPartitionCandidates

if ($normalizedDriveLetter) {
    $BootPartition = "${normalizedDriveLetter}:\\"
    if (-not (Test-Path $BootPartition)) {
        Write-Error "Drive $normalizedDriveLetter does not exist or is not mounted."
        exit 1
    }

    $selected = $candidates | Where-Object { $_.DriveLetter -eq $normalizedDriveLetter }
    if (-not $selected) {
        Write-Warning "Drive $normalizedDriveLetter is not detected as a Raspberry Pi boot partition (FAT32 bootfs with expected files). Proceeding anyway because drive was explicitly provided."
    }
} else {
    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-Error "No candidate Raspberry Pi boot partition found. Expected a mounted FAT32 volume labeled 'bootfs' containing config.txt and cmdline.txt."
        exit 1
    }

    $best = $candidates | Sort-Object -Property Score -Descending
    $topScore = $best[0].Score
    $topCandidates = $best | Where-Object { $_.Score -eq $topScore }

    if ($topCandidates.Count -gt 1) {
        Write-Error "Multiple possible boot partitions found ($($topCandidates.DriveLetter -join ', ')). Re-run with -DriveLetter <letter>."
        exit 1
    }

    $normalizedDriveLetter = $topCandidates[0].DriveLetter
    $BootPartition = "${normalizedDriveLetter}:\\"
    Write-Host "Auto-detected boot partition: ${normalizedDriveLetter}: (Label='$($topCandidates[0].Label)')"
}

# Paths
$UserDataPath = Join-Path -Path $BootPartition -ChildPath "user-data"
$SetupScriptPath = Join-Path -Path $BootPartition -ChildPath "reachy-mini-setup.sh"

# Locate the setup script next to this PS1
$SourceScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "reachy-mini-setup.sh"
if (-not (Test-Path $SourceScriptPath)) {
    Write-Error "reachy-mini-setup.sh not found at '$SourceScriptPath'. It must be in the same folder as this script."
    exit 1
}

# Inject the setup script (convert to LF line endings for bash compatibility)
if ($Force -or -not (Test-Path $SetupScriptPath)) {
    $content = Get-Content -Path $SourceScriptPath -Raw
    [System.IO.File]::WriteAllText($SetupScriptPath, $content.Replace("`r`n", "`n"))
    Write-Host "Injected reachy-mini-setup.sh into $SetupScriptPath"
} else {
    Write-Host "Setup script already exists. Use -Force to overwrite."
}

# GStreamer tarball is always downloaded during install from the reachy-mini-os
# repo so it matches the GStreamer version apt installs on Trixie.

# Inject runcmd entry into user-data for cloud-init
$RuncmdItem = "- [ bash, /boot/firmware/reachy-mini-setup.sh ]"
$RuncmdEntry = "  $RuncmdItem"
$RuncmdMarker = "reachy-mini-setup.sh"

# user-data is always written with WriteAllText: it uses UTF-8 without a BOM
# and keeps LF line endings, whereas Set-Content -Encoding UTF8 on Windows
# PowerShell 5.1 adds a BOM, and cloud-init then no longer sees #cloud-config.
if (-not (Test-Path $UserDataPath)) {
    # No user-data yet — write a minimal cloud-config
    [System.IO.File]::WriteAllText($UserDataPath, "#cloud-config`nruncmd:`n$RuncmdEntry`n")
    Write-Host "Created user-data with runcmd entry."
} else {
    $existing = Get-Content -Path $UserDataPath -Raw

    if ($existing -match [regex]::Escape($RuncmdMarker)) {
        if ($Force) {
            # Replace only the reachy-mini line in-place, keeping its indentation
            $updated = $existing -replace "(?m)^([ \t]*)-[ \t]*\[?[ \t]*bash,[ \t]*/boot/(firmware/)?reachy-mini-setup\.sh[^\r\n]*", "`$1$RuncmdItem"
            [System.IO.File]::WriteAllText($UserDataPath, $updated)
            Write-Host "Updated existing runcmd entry in user-data."
        } else {
            Write-Host "user-data already contains runcmd entry. Use -Force to update it."
        }
    } else {
        # Append runcmd block or add to existing runcmd section
        if ($existing -match "(?m)^runcmd:") {
            # Append as the LAST item of the existing runcmd list. Imager puts
            # `systemctl enable --now ssh` there, and the setup script ends with a
            # reboot, so it must run after everything else cloud-init queued.
            # The entry copies the indentation of the existing items: a deeper
            # indent would turn it into a continuation of the previous command.
            # The list ends at the next top-level key.
            $lines = $existing.TrimEnd("`r", "`n") -split "\r?\n"
            $out = New-Object System.Collections.Generic.List[string]
            $inRuncmd = $false
            $indent = $null
            foreach ($line in $lines) {
                if ($line -match "^runcmd:") {
                    $inRuncmd = $true
                } elseif ($inRuncmd) {
                    if ($line -match "^[^\s#-]") {
                        if ($null -eq $indent) { $indent = "  " }
                        $out.Add("$indent$RuncmdItem")
                        $inRuncmd = $false
                    } elseif ($null -eq $indent -and $line -match "^(\s*)-") {
                        $indent = $Matches[1]
                    }
                }
                $out.Add($line)
            }
            if ($inRuncmd) {
                if ($null -eq $indent) { $indent = "  " }
                $out.Add("$indent$RuncmdItem")
            }
            [System.IO.File]::WriteAllText($UserDataPath, ($out -join "`n") + "`n")
            Write-Host "Appended runcmd entry to existing runcmd section in user-data."
        } else {
            # No runcmd section — append one
            $appended = $existing.TrimEnd() + "`nruncmd:`n$RuncmdEntry`n"
            [System.IO.File]::WriteAllText($UserDataPath, $appended)
            Write-Host "Appended runcmd section to user-data."
        }
    }
}

Write-Host "SD card preparation complete. You can now eject the card."