# Setting up a Reachy Mini Lite with a Raspberry Pi

![A Reachy Mini Lite turned into a Wireless (well, ahum... wifi) version](reachy%20mini%20lite%20as%20wireless.png)

This guide explains how to run the Reachy Mini daemon on a Raspberry Pi 4B (or similar, ymmv)
so that you can use Reachy Mini Lite wirelessly — no laptop tethered to the
robot, just power to both devices and a shared WiFi network.

**Hardware layout**
```
[Laptop / desktop]  ←── WiFi ───→  [Raspberry Pi]
                                          │
                                         USB
                                          │
                                    [Reachy Mini Lite]
```

---

## Prerequisites

| Item | Notes |
|------|-------|
| Raspberry Pi | 2 GB or more recommended |
| microSD card | 16 GB minimum, 32 GB recommended (Class 10 / A1) |
| USB-A to USB-C cable | To connect the Pi to Reachy Mini |
| Power supply for the Pi | Official 5 V / 3 A USB-C recommended |
| Windows, Linux or macOS PC | For flashing and SD card preparation |
| [Raspberry Pi Imager](https://www.raspberrypi.com/software/) | Install before starting |

---

## Step 1 — Flash the SD card

1. Open **Raspberry Pi Imager**.
2. Click **"Choose Device"** → select **Raspberry Pi 4/5/X**.
3. Click **"Choose OS"** → **Raspberry Pi OS (other)** →
   **Raspberry Pi OS Lite (64-bit)**.
4. Click **"Choose Storage"** → select your SD card.
5. Click **"Next"**. When asked *"Would you like to apply OS customisation
   settings?"* click **"Edit Settings"**.

### OS Customisation (required)

In the **General** tab:

| Setting | Recommended value |
|---------|-------------------|
| Hostname | any name you like |
| Username | default
| Password | default
| **Configure wireless LAN** | ✅ Enter your WiFi SSID and password |
| Wireless LAN country | Set to your country code |
| Locale / timezone | Set to your location |


In the **Services** tab:

- **Enable SSH** ✅ → *Use password authentication*

Click **Save**, then **Yes** to apply settings, then confirm to write.

> **Why is OS Customisation required?**  
> Pi OS Trixie (Nov 2025+) uses **cloud-init** instead of `firstrun.sh`.
> Imager writes `user-data` and `network-config` files to the boot partition
> containing your WiFi credentials, user account, and SSH settings.
> The `prepare-sd-card` script appends the installer from this repo to that
> `user-data`, so it runs automatically during the first boot.


## Step 2 — Prepare the SD card for automatic setup

This step injects the Reachy Mini deamon install script into the Pi's first-boot script
so everything installs automatically after the Pi connects to WiFi.

### 2a — Re-insert the SD card and access the boot partition

Raspberry Pi Imager ejects the card automatically when writing finishes.
Re-insert it.

<details>
<summary><strong>Windows</strong></summary>

**Windows will likely show one or two "You need to format the
disk" dialogs — click Cancel on all of them.** Those are for the Linux
(ext4) partition that Windows cannot read.

The FAT32 boot partition (labelled `bootfs`, ~256 MB) may or may not get a
drive letter automatically. If it does not appear in Windows Explorer:

1. Open **Disk Management**: press `Win + R`, type `diskmgmt.msc`, press Enter.
2. Find your SD card in the list (look for ~256 MB FAT32 partition labelled
   `bootfs` or with no label, on a removable disk).
3. Right-click that partition → **Change Drive Letter and Paths…** →
   **Add** → pick any letter (e.g. `E`) → **OK**.

The `bootfs` partition should now be visible in Windows Explorer.
</details>

<details>
<summary><strong>Linux</strong></summary>

Most desktop environments auto-mount the boot partition at
`/media/$USER/bootfs`. If it doesn't appear, mount it manually:

```bash
sudo mkdir -p /mnt/bootfs
sudo mount /dev/sdX1 /mnt/bootfs   # replace sdX1 with your SD card's first partition
```

Use `lsblk` to identify the correct device.
</details>

<details>
<summary><strong>macOS</strong></summary>

macOS auto-mounts the boot partition at `/Volumes/bootfs`. If it does not
appear, run `diskutil list` to find the card and `diskutil mount <identifier>`
to mount its first (FAT32) partition. macOS will show a "disk not readable"
dialog for the Linux (ext4) partition — click **Ignore**.
</details>

### 2b — Run the preparation script

<details>
<summary><strong>Windows (PowerShell)</strong></summary>

Open **PowerShell** (no Administrator needed) and run:

```powershell
.\prepare-sd-card.ps1
```

The script auto-detects the SD boot partition by looking for a mounted
FAT32 volume labeled `bootfs` with Raspberry Pi boot files. If detection is
ambiguous or fails, pass the drive letter you assigned above:

```powershell
.\prepare-sd-card.ps1 -DriveLetter E
```

> **Updating the installer after a card is already prepared**  
> The script skips re-injection if the installer marker already exists in
> `user-data`. Use `-Force` to strip the old version and re-embed the current
> one (needed after editing `reachy-mini-setup.sh`):
> ```powershell
> .\prepare-sd-card.ps1 -Force
> ```
</details>

<details>
<summary><strong>Linux / macOS (Bash)</strong></summary>

```bash
chmod +x prepare-sd-card.sh
./prepare-sd-card.sh
```

The script auto-detects the mounted `bootfs` partition (`/media/$USER/bootfs`
or `/mnt/bootfs` on Linux, `/Volumes/bootfs` on macOS). It only needs bash 3.2+
and awk, so it runs unchanged on macOS. If detection fails, pass the mount
point explicitly:

```bash
./prepare-sd-card.sh /media/$USER/bootfs    # Linux
./prepare-sd-card.sh /Volumes/bootfs         # macOS
```

> **Updating the installer after a card is already prepared**  
> Use `--force` to overwrite existing files:
> ```bash
> ./prepare-sd-card.sh --force
> ```
</details>

You should see output ending with `SD card preparation complete.`

### 2c — Safely eject the SD card

- **Windows**: In Windows Explorer right-click the boot partition drive → **Eject**.
- **Linux**: `sudo umount /media/$USER/bootfs` (or the mount point shown by the script), then remove the card.
- **macOS**: `diskutil unmount /Volumes/bootfs` (or eject it from Finder), then remove the card.

---

## Step 3 — First boot (WiFi and SSH setup)

1. Insert the SD card into the Raspberry Pi 4B.
2. Connect the Pi to Reachy Mini via the USB cable
   (USB-A on the Pi → USB-C on Reachy Mini).
3. Power on the Raspberry Pi.

**What happens on first boot (~1-2 minutes):**
- cloud-init runs: sets up your user, password, WiFi, SSH, and registers the
  Reachy Mini installer as a one-shot systemd service.
- The Pi reboots automatically.

---

## Step 4 — Automatic Reachy Mini deamon installation (second boot)

After the Pi reboots it connects to WiFi and the installer service starts.
This takes **15 minutes** depending on your internet connection and SD card (no Rust
compilation — the GStreamer plugin is pre-built).

The install:


### Monitoring progress

Once the Pi is on your network you can SSH in and watch the log:

ssh pollen@192.168.0.116 "tail -f /tmp/reachy-install.log"
# password: root

> If `raspberrypi.local` doesn't resolve, find the IP address from your
> router's DHCP client list, or scan with `nmap -sn 192.168.1.0/24`.

A successful install ends with a line like:
```
[...] === Reachy Mini setup complete! Rebooting in 5 seconds... ===
```

After the final reboot, `~/VERSION.txt` on the Pi shows the installed
version:


---

## Step 5 — Verify the daemon is running

After the install reboot:

```bash
ssh pi@raspberrypi.local
systemctl status reachy-mini-daemon
```

You should see `active (running)`. The daemon listens for connections from
the Reachy Mini conversation app.

---

## Step 6 — Connect the desktop app

Install the conversation app on your laptop:

```bash
# macOS / Linux
brew install git-xet   # macOS only; skip on Linux
git xet install
git clone https://huggingface.co/spaces/pollen-robotics/reachy_mini_conversation_app
cd reachy_mini_conversation_app
uv sync
source .venv/bin/activate
reachy-mini-conversation-app --gradio --robot-host raspberrypi.local
```

Then open your browser at `http://localhost:7860/`.

Replace `raspberrypi.local` with your Pi's IP address if mDNS is not
available on your network.

---

## Platform notes — Raspberry Pi 4B with Pi OS Trixie

Pi OS Trixie (Debian 13, Nov 2025+) differs from the Wireless CM4 image in
a few ways that affect the daemon. The setup script handles all of this
automatically; this section explains what was done and why.

### Daemon must bind on all interfaces

By default the daemon binds only to `localhost` (suitable for the desktop
app running on the same machine). On the Pi the desktop app runs on a
**different machine**, so the daemon must accept connections from the
network.

The setup script starts the daemon with `--no-localhost-only`:

```ini
ExecStart=/home/pollen/reachy_mini/.venv/bin/reachy-mini-daemon --no-localhost-only
```

Without this flag, `daemon_status.wlan_ip` is `None` and the SDK falls back
to `ws://localhost:8443` — which resolves to the **user's laptop**, not the
Pi. WebRTC signaling fails silently and video/audio never stream.

### PipeWire for audio — same as the CM4 image

Pi OS Trixie Lite ships with **no audio server**. The setup script installs
`pipewire-audio`, `gstreamer1.0-pipewire`, and `wireplumber` — the same
stack the official CM4 image uses.

With PipeWire active, the daemon's stock `find_audio_device()` returns a
PipeWire `node.name` (e.g.
`alsa_input.usb-Pollen_Robotics_Reachy_Mini_Audio_…-00.analog-stereo`) and
uses `pulsesrc` / `pulsesink` through PipeWire-Pulse. **No `.asoundrc` or
custom ALSA config is needed.**

### systemd service needs `XDG_RUNTIME_DIR`

PipeWire runs as a **user service** (under `pollen`). The daemon runs as a
**system service** (under `multi-user.target`). System services don't
inherit the user session environment, so GStreamer can't find PipeWire's
socket — it falls back to raw ALSA and returns `hw:` device IDs instead of
PipeWire node names.

The fix is a single environment variable in the service file:

```ini
Environment=XDG_RUNTIME_DIR=/run/user/1000
```

Combined with `loginctl enable-linger pollen`, PipeWire's socket at
`/run/user/1000/pipewire-0` exists from boot and the daemon can connect.

### GStreamer WebRTC plugin — pre-built binary

The `gst-plugin-webrtc` Rust crate takes 25+ minutes to compile on a Pi 4B
and needs >2 GB of free disk. The setup script instead extracts the same
pre-built `gst-plugins-rs-rpi.tar.gz` tarball used by the official CM4
pi-gen pipeline — installed to `/opt/gst-plugins-rs/`.

---

## Troubleshooting

### No video in the desktop app

1. Check that the daemon is running with `--no-localhost-only`:
   ```bash
   systemctl show reachy-mini-daemon --property=ExecStart
   ```
2. Verify the GStreamer WebRTC pipeline started — the IPC socket and
   signaling port must both be present:
   ```bash
   ls /tmp/reachymini_camera_socket   # must exist
   ss -tlnp | grep 8443               # must show LISTEN
   ```
3. If either is missing, check daemon logs for GStreamer errors:
   ```bash
   journalctl -u reachy-mini-daemon -n 50 --no-pager | grep -iE 'error|warn|alsa|gst'
   ```

### No audio (speaker silent)

Verify PipeWire sees the device:

```bash
wpctl status | grep -A5 "Audio"
```

Test playback through PipeWire:

```bash
GST_PLUGIN_PATH=/opt/gst-plugins-rs/lib/aarch64-linux-gnu \
gst-launch-1.0 audiotestsrc num-buffers=80 \
  ! audio/x-raw,rate=16000,channels=2,format=S16LE \
  ! pulsesink
```

For deeper GStreamer diagnostics, copy the helper scripts from this folder to the Pi and run them as the `pollen` user (they need the user PipeWire session):

```bash
scp test_pipewire_gst.py dump_gst_audio_props.py pollen@<pi-ip>:~
ssh pollen@<pi-ip> "XDG_RUNTIME_DIR=/run/user/1000 GST_PLUGIN_PATH=/opt/gst-plugins-rs/lib/aarch64-linux-gnu python3 test_pipewire_gst.py"
```

- `test_pipewire_gst.py` — checks `pulsesrc`/`pulsesink` work and lists all audio sources/sinks GStreamer sees through PipeWire.
- `dump_gst_audio_props.py` — dumps every raw property of each audio source device (useful to verify the `node.name` that `find_audio_device()` will return).

If that fails, check PipeWire is running for user pollen:

```bash
systemctl --user status pipewire wireplumber
```

### Daemon falls back to ALSA instead of PipeWire

If logs show `Using ALSA dsnoop` or `hw:CARD=Audio`, the daemon can't
reach PipeWire. Verify:

```bash
# XDG_RUNTIME_DIR must be set in the service
systemctl show reachy-mini-daemon --property=Environment | grep XDG

# PipeWire socket must exist
ls /run/user/1000/pipewire-0

# Linger must be enabled
loginctl show-user pollen --property=Linger
```

### Microphone not captured / no audio in WebRTC stream

The capture device should be held by the daemon when the GStreamer pipeline
is running. Confirm:

```bash
arecord -l   # Subdevices: 0/1 means the daemon holds it — correct
```

If `Subdevices: 1/1` (available), the daemon's audio capture pipeline
crashed. Check daemon logs for errors.

---

## Maintenance — adapting for future OS or daemon releases

This section documents the moving parts so that future revisions are easy.

### Files in this folder

| File | Purpose |
|------|---------|
| `reachy-mini-setup.sh` | Main install script. Runs once on first boot (via cloud-init `runcmd`). |
| `prepare-sd-card.ps1` | Windows helper to inject the script + tarball into the SD boot partition. |
| `prepare-sd-card.sh` | Linux helper — same as the PS1 script but for bash. |
| `README.md` | This file. |

### Installing a custom daemon branch (for development)

To test a fork or unreleased branch of the daemon without publishing to PyPI,
set `DAEMON_SOURCE` at the top of `reachy-mini-setup.sh` before running
`prepare-sd-card.ps1` / `prepare-sd-card.sh`:

```bash
# Install from a git branch
DAEMON_SOURCE="git+https://github.com/your-fork/reachy_mini@my-branch"

# Install from a local copy placed on the SD card
# (copy the repo to ./reachy_mini_src/ before running prepare-sd-card)
DAEMON_SOURCE="/boot/firmware/reachy_mini_src"
```

`uv pip install` accepts both git URLs and local paths, so both forms work
with the `[gstreamer]` extra appended automatically. Leave `DAEMON_SOURCE`
empty (the default) to always install the latest release from PyPI.

### What to change when the daemon releases a new version

1. Verify the PyPI extras still match (currently `[gstreamer]`).
2. If the new daemon requires a newer GStreamer plugin, rebuild the tarball
   (see "Pre-built GStreamer tarball" below) and commit the new version to
   the `reachy-mini-os` repo.

### What to change for a new Pi OS release

| Concern | Where to look |
|---------|---------------|
| PipeWire version / packages | `apt-get install` list in `reachy-mini-setup.sh` — verify package names haven't changed. |
| cloud-init changes | `prepare-sd-card.ps1` — verify `user-data` YAML format and `runcmd` path still apply. |
| Default Python version | `uv venv --python 3.12` — bump if the daemon supports a newer Python. |
| systemd user session path | `XDG_RUNTIME_DIR=/run/user/<UID>` — remains `1000` as long as the user is the first non-root account. |
| Boot partition mount point | Script checks `/boot/firmware/` for the tarball — Pi OS has used this since Bookworm. |

### Why PipeWire (not raw ALSA or PulseAudio)

- The official CM4 image uses PipeWire → matching it means the **stock
  daemon code** works with zero modifications.
- PipeWire handles sample-rate conversion, multi-process access, and
  device routing automatically — no `.asoundrc` / dsnoop config needed.
- `loginctl enable-linger` + `XDG_RUNTIME_DIR` in the service file is the
  only extra wiring needed for a system-level service to reach a user-level
  PipeWire instance.

### Key daemon code paths (for debugging)

| File | Function | What it does |
|------|----------|-------------|
| `src/reachy_mini/media/device_detection.py` | `find_audio_device()` | Returns `node.name` when PipeWire is available → triggers `pulsesrc` path |
| `src/reachy_mini/media/media_server.py` | `_build_audio_source()` | If ID doesn't start with `hw:` → uses `pulsesrc` (PipeWire-Pulse) |
| `src/reachy_mini/media/audio_utils.py` | `has_reachymini_asoundrc()` | Returns `False` when no `.asoundrc` → skips CM4 ALSA path |

### Pre-built GStreamer tarball

The tarball `gst-plugins-rs-rpi.tar.gz` (82 MB) contains `gst-plugin-webrtc`
compiled for `aarch64-linux-gnu`. It extracts to `/opt/gst-plugins-rs/`.
The setup script always downloads the latest tarball from the `develop` branch
of [`reachy-mini-os`](https://github.com/pollen-robotics/reachy-mini-os) during
install — this keeps it in sync with the GStreamer version Trixie's apt installs.

To rebuild (on a Pi or cross-compile):
```bash
git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git
cd gst-plugins-rs && git checkout <version-tag>
cargo cinstall -p gst-plugin-webrtc --prefix=/opt/gst-plugins-rs --release
tar -czf gst-plugins-rs-rpi.tar.gz -C / opt/gst-plugins-rs
```


