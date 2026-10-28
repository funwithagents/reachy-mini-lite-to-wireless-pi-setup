#!/bin/bash
# Prepare an SD card for Reachy Mini daemon installation (Linux / macOS)
# Usage: ./prepare-sd-card.sh [-f|--force] [/path/to/bootfs]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=false
BOOT_PATH=""

# --- Parse arguments ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [-f|--force] [/path/to/bootfs]"
            echo ""
            echo "Prepares a Raspberry Pi SD card for automatic Reachy Mini daemon installation."
            echo ""
            echo "Options:"
            echo "  -f, --force   Overwrite existing files on the boot partition"
            echo "  /path/...     Explicit path to the boot partition mount point"
            echo ""
            echo "If no path is given, auto-detects the mounted bootfs partition"
            echo "(/media/\$USER/bootfs or /mnt/bootfs on Linux, /Volumes/bootfs on macOS)."
            exit 0
            ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) BOOT_PATH="$1"; shift ;;
    esac
done

# --- Locate boot partition ---------------------------------------------------
find_boot_partition() {
    local candidates=() valid=() c path line

    # Strategy 1 (Linux): findmnt with LABEL filter
    if command -v findmnt >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && candidates+=("$line")
        done < <(findmnt -rn -o TARGET -S LABEL=bootfs 2>/dev/null || true)
    fi

    # Strategy 2: common auto-mount paths (Linux desktops, macOS)
    for path in /media/*/bootfs /run/media/*/bootfs /mnt/bootfs /Volumes/bootfs; do
        [[ -d "$path" ]] || continue
        local dup=false
        for c in ${candidates[@]+"${candidates[@]}"}; do
            [[ "$c" == "$path" ]] && dup=true
        done
        [[ "$dup" == false ]] && candidates+=("$path")
    done

    # Filter: must contain config.txt and cmdline.txt
    for c in ${candidates[@]+"${candidates[@]}"}; do
        if [[ -f "$c/config.txt" && -f "$c/cmdline.txt" ]]; then
            valid+=("$c")
        fi
    done

    if [[ ${#valid[@]} -eq 0 ]]; then
        echo "ERROR: No Raspberry Pi boot partition found." >&2
        echo "Expected a mounted FAT32 partition labeled 'bootfs' containing config.txt and cmdline.txt." >&2
        echo "Try specifying the path explicitly: $0 /media/\$USER/bootfs  (macOS: /Volumes/bootfs)" >&2
        exit 1
    fi

    if [[ ${#valid[@]} -gt 1 ]]; then
        echo "ERROR: Multiple boot partitions found:" >&2
        printf '  %s\n' "${valid[@]}" >&2
        echo "Re-run with an explicit path." >&2
        exit 1
    fi

    echo "${valid[0]}"
}

if [[ -z "$BOOT_PATH" ]]; then
    BOOT_PATH="$(find_boot_partition)"
    echo "Auto-detected boot partition: $BOOT_PATH"
else
    if [[ ! -d "$BOOT_PATH" ]]; then
        echo "ERROR: Path '$BOOT_PATH' does not exist or is not a directory." >&2
        exit 1
    fi
    if [[ ! -f "$BOOT_PATH/config.txt" ]]; then
        echo "WARNING: '$BOOT_PATH' does not look like a Pi boot partition (no config.txt). Proceeding anyway."
    fi
fi

# --- Inject setup script -----------------------------------------------------
SOURCE_SCRIPT="$SCRIPT_DIR/reachy-mini-setup.sh"
DEST_SCRIPT="$BOOT_PATH/reachy-mini-setup.sh"

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
    echo "ERROR: reachy-mini-setup.sh not found at '$SOURCE_SCRIPT'." >&2
    echo "It must be in the same folder as this script." >&2
    exit 1
fi

if [[ "$FORCE" == true ]] || [[ ! -f "$DEST_SCRIPT" ]]; then
    # Strip CR in case the repo was checked out with CRLF line endings
    tr -d '\r' < "$SOURCE_SCRIPT" > "$DEST_SCRIPT"
    echo "Injected reachy-mini-setup.sh into $DEST_SCRIPT"
else
    echo "Setup script already exists. Use --force to overwrite."
fi

# GStreamer tarball is always downloaded during install from the reachy-mini-os
# repo so it matches the GStreamer version apt installs on Trixie.

# --- Inject runcmd into user-data --------------------------------------------
# No `sed -i` here: GNU and BSD (macOS) sed disagree on its syntax, so edits go
# through awk into a temp file that then replaces user-data.
USER_DATA="$BOOT_PATH/user-data"
RUNCMD_ENTRY="  - [ bash, /boot/firmware/reachy-mini-setup.sh ]"
RUNCMD_MARKER="reachy-mini-setup.sh"

write_user_data() {
    # $1 = new content (stdin); replaces user-data atomically
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/user-data.XXXXXX")"
    cat > "$tmp"
    cat "$tmp" > "$USER_DATA"
    rm -f "$tmp"
}

if [[ ! -f "$USER_DATA" ]]; then
    # No user-data yet — write a minimal cloud-config
    printf '#cloud-config\nruncmd:\n%s\n' "$RUNCMD_ENTRY" > "$USER_DATA"
    echo "Created user-data with runcmd entry."
elif grep -q "$RUNCMD_MARKER" "$USER_DATA"; then
    if [[ "$FORCE" == true ]]; then
        awk -v entry="$RUNCMD_ENTRY" '
            /bash.*\/boot\/firmware\/reachy-mini-setup\.sh/ { print entry; next }
            { print }
        ' "$USER_DATA" | write_user_data
        echo "Updated existing runcmd entry in user-data."
    else
        echo "user-data already contains runcmd entry. Use --force to update it."
    fi
else
    if grep -q "^runcmd:" "$USER_DATA"; then
        # Append as the LAST item of the existing runcmd list. Imager puts
        # `systemctl enable --now ssh` there, and the setup script ends with a
        # reboot, so it must run after everything else cloud-init queued.
        awk -v entry="$RUNCMD_ENTRY" '
            /^runcmd:/ { in_runcmd = 1; print; next }
            in_runcmd && !/^[[:space:]]*-/ && !/^[[:space:]]*$/ { print entry; in_runcmd = 0 }
            { print }
            END { if (in_runcmd) print entry }
        ' "$USER_DATA" | write_user_data
        echo "Appended runcmd entry to existing runcmd section in user-data."
    else
        printf '\nruncmd:\n%s\n' "$RUNCMD_ENTRY" >> "$USER_DATA"
        echo "Appended runcmd section to user-data."
    fi
fi

echo ""
echo "SD card preparation complete. You can now safely unmount and eject the card."
case "$(uname -s)" in
    Darwin) echo "  diskutil unmount \"$BOOT_PATH\"" ;;
    *)      echo "  sudo umount \"$BOOT_PATH\"" ;;
esac
