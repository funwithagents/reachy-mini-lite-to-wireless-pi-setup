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
$RuncmdEntry = "  - [ bash, /boot/firmware/reachy-mini-setup.sh ]"
$RuncmdMarker = "reachy-mini-setup.sh"

if (-not (Test-Path $UserDataPath)) {
    # No user-data yet — write a minimal cloud-config
    @"
#cloud-config
runcmd:
$RuncmdEntry
"@ | Set-Content -Path $UserDataPath -Encoding UTF8
    Write-Host "Created user-data with runcmd entry."
} else {
    $existing = Get-Content -Path $UserDataPath -Raw

    if ($existing -match [regex]::Escape($RuncmdMarker)) {
        if ($Force) {
            # Replace only the reachy-mini line in-place
            $updated = $existing -replace "(?m)^\s*-\s*\[?\s*bash,\s*/boot/reachy-mini-setup\.sh.*$", $RuncmdEntry
            [System.IO.File]::WriteAllText($UserDataPath, $updated)
            Write-Host "Updated existing runcmd entry in user-data."
        } else {
            Write-Host "user-data already contains runcmd entry. Use -Force to update it."
        }
    } else {
        # Append runcmd block or add to existing runcmd section
        if ($existing -match "(?m)^runcmd:") {
            # Insert our line after the runcmd: header
            $updated = $existing -replace "(?m)^(runcmd:\s*\r?\n)", "`$1$RuncmdEntry`n"
            [System.IO.File]::WriteAllText($UserDataPath, $updated)
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