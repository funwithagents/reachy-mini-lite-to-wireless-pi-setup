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

## Step 3 — First boot (WiFi, SSH and automatic installation)

1. Insert the SD card into the Raspberry Pi 4B.
2. Connect the Pi to Reachy Mini via the USB cable
   (USB-A on the Pi → USB-C on Reachy Mini).
3. Power on the Raspberry Pi.

There is a single install boot. Everything below is driven by **cloud-init**,
the first-boot configuration tool built into Pi OS Trixie, reading the
`user-data` and `network-config` files that Imager and `prepare-sd-card`
wrote to the boot partition. There is no separate installer service.

**What happens on first boot:**

1. *(~1-2 minutes)* cloud-init brings up WiFi, creates your user and password,
   sets the hostname, timezone and keyboard, installs `avahi-daemon` (for
   `<hostname>.local` resolution) and enables SSH. From this point you can
   SSH in.
2. *(~15 minutes, depending on internet connection and SD card)* cloud-init
   runs the last `runcmd` entry: `bash /boot/firmware/reachy-mini-setup.sh`.
   This runs as root, in the foreground, and does the whole install (no Rust
   compilation — the GStreamer plugins are pre-built):
   - apt installs GStreamer, ALSA utilities and build tools (same stack as the official Wireless image)
   - downloads the pre-built GStreamer WebRTC plugins from the `reachy-mini-os` GitHub releases (sha256-verified) into `/opt/gst-plugins-rs/`
   - installs `uv`, creates a Python 3.12 venv and installs `reachy-mini[wireless-version]` at the pinned version
   - writes udev rules for the robot's USB serial adapter (stable `/dev/reachy_mini` symlink) and audio board
   - grants your user a few scoped passwordless `sudo` commands the daemon needs
   - creates and enables the `reachy-mini-daemon` systemd service, running in wireless mode
   - writes `~/VERSION.txt`
3. The script reboots the Pi. The daemon starts for the first time on that
   reboot.

cloud-init marks the first boot as done, so the install script never runs
again on later boots. If it fails partway, either re-run it by hand over SSH
(`sudo bash /boot/firmware/reachy-mini-setup.sh`) or reflash the card.

---

## Step 4 — Monitoring the installation

Once SSH is up (a minute or two after power-on) you can watch the install
live. Use the username and hostname you set in Imager:

```bash
ssh <user>@<hostname>.local "sudo tail -f /var/log/cloud-init-output.log"
```

This is cloud-init's log of everything its `runcmd` commands print, so it
contains the full output of `reachy-mini-setup.sh`. It survives the reboot,
so you can also read it afterwards to diagnose a failed install.
`/var/log/cloud-init.log` is cloud-init's own internal log, useful if the
install never started at all (WiFi or `user-data` parsing problems).

> If `<hostname>.local` doesn't resolve, find the IP address from your
> router's DHCP client list, or scan with `nmap -sn 192.168.1.0/24`.

A successful install ends with a line like:
```
=== Reachy Mini setup complete! Rebooting in 5 seconds... ===
```

The SSH session drops when the Pi reboots. After it comes back up,
`~/VERSION.txt` on the Pi shows the installed daemon version:

```bash
ssh <user>@<hostname>.local cat VERSION.txt
```

---

## Step 5 — Verify the daemon is running

After the install reboot:

```bash
ssh <user>@<hostname>.local
systemctl status reachy-mini-daemon
```

You should see `active (running)`. From your laptop, check that the daemon is
in wireless mode and advertises the Pi's WiFi address:

```bash
curl -s http://<hostname>.local:8000/api/daemon/status | python3 -m json.tool | grep -E 'wireless_version|wlan_ip|error'
```

Expect `"wireless_version": true`, a non-null `"wlan_ip"` and `"error": null`.
Some startup-check errors in the journal are normal on this setup; see
"Things that are expected to log errors" below.

### Quick hardware test (no app needed)

The daemon boots with motors disabled, like the official Wireless image, so
enable them before asking for a move. Clear space around the head first.

```bash
R=http://<hostname>.local:8000/api
curl -X POST $R/volume/test-sound            # speaker
curl -X POST $R/motors/set_mode/enabled      # torque on
curl -X POST $R/move/play/wake_up            # head rises, wake-up sound, antennas move
sleep 8
curl -X POST $R/move/play/goto_sleep
```

If the sounds play but nothing moves, the motors are still disabled.

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

## How this differs from the official Wireless image

The Reachy Mini Wireless is a Compute Module 4 inside the robot, running the
image built by [`reachy-mini-os`](https://github.com/pollen-robotics/reachy-mini-os)
(pi-gen, Pi OS Trixie Lite). This setup reproduces the software side of that
image on a Pi 4B plugged into a Reachy Mini **Lite** over USB. The hardware is
different, and that drives every choice below.

| | Wireless (CM4 inside the robot) | Lite body + this Pi 4B |
|---|---|---|
| Motors | UART `/dev/ttyAMA3` | USB CH343 adapter → `/dev/reachy_mini` (udev symlink) |
| Camera | CSI `imx708`, `libcamerasrc` + hardware H.264 encoder | USB UVC camera, MJPEG decoded and re-encoded **in software** |
| Audio | "Reachy Mini Audio" USB board via ALSA (`~/.asoundrc`) | same board, same ALSA path |
| IMU | BMI088 on I2C bus 4 | none (daemon logs a warning and continues) |
| Power switch | GPIO shutdown service | none |
| WiFi setup | BLE provisioning service + `nmcli` | done by Imager / cloud-init |
| Layout | user `pollen`, `/venvs/mini_daemon`, `/restore`, `/bluetooth`, `/opt/uv` | your user, `~/reachy_mini/.venv`, `~/.local/bin/uv` |

### Why the daemon runs with `--wireless-version`

The daemon has exactly two network behaviours, selected by this flag
(`src/reachy_mini/daemon/app/main.py`, `_resolve_bind_host`):

- **Lite / desktop mode (default)**: the HTTP API binds `127.0.0.1` and the
  status it reports has `wlan_ip: null`. The SDK client on your laptop uses
  `wlan_ip` as the WebRTC signalling host and falls back to `localhost` when
  it is missing — so video and audio would be requested from the **laptop**,
  not the Pi. `--fastapi-host 0.0.0.0` makes the API reachable but does not
  fix `wlan_ip`.
- **Wireless mode**: binds `0.0.0.0`, reports the `wlan0` IP as `wlan_ip`,
  advertises itself over mDNS as a "Reachy Mini Wireless", enables the
  wireless-only API routes (update, wifi, cache, logs), and uses ALSA via
  `~/.asoundrc` for audio (written by the daemon on first start).

Earlier daemon releases (≤ 1.8.0) had a `--no-localhost-only` flag that gave
Lite mode the wireless network behaviour. It was removed in 1.9.0 (July
2026), so wireless mode is now the only supported way to drive the robot
from another machine. The two things wireless mode assumes that a Lite body
cannot provide are handled explicitly:

- **Serial port**: wireless mode looks for `/dev/ttyAMA3` and nothing else,
  so the service passes `--serialport /dev/reachy_mini`, a udev symlink to
  the Lite's USB adapter (VID:PID `1a86:55d3`).
- **IMU**: initialisation fails with a logged warning; nothing else depends
  on it.

### Things that are expected to log errors

On every boot the daemon runs the Wireless "startup checks"
(`src/reachy_mini/utils/wireless_version/startup_check.py`). They look for
the fleet layout and try to self-heal it with `sudo`. On this setup they
log errors and move on; none of them is fatal:

- `/venvs` does not exist / user `pollen` does not exist (ownership check)
- `Wireless daemon service has changed, updating...` followed by a `sudo cp`
  failure: the packaged unit expects `/venvs/mini_daemon`, ours does not,
  and the scoped sudoers does not allow `cp`. The installed unit is kept.
- `gpio-shutdown service not installed`, then a `sudo cp` failure
- `Source bluetooth service` copy failures

Likewise the dashboard's **Update** and **WiFi** pages exist but target the
fleet layout; update the daemon by re-running the setup with a new
`REACHY_MINI_VERSION` instead.

### Audio: ALSA, not PipeWire

The official image installs PipeWire packages but never runs them: the
daemon is a system service without a user session, and in wireless mode it
checks `~/.asoundrc` first and uses `alsasrc`/`alsasink` on the `dmix` /
`dsnoop` aliases defined there. This setup does the same and simply does not
install PipeWire, so nothing else can hold the card. The volume endpoints
fall back to `amixer` automatically when no PulseAudio server is present.

### Video: expect CPU load

The Wireless streams from the CSI camera through the Pi's hardware H.264
encoder (with a patched `v4l2h264enc` for congestion control). A USB camera
takes the generic V4L2 path: MJPEG → `jpegdec` → raw → `webrtcsink`, which
encodes in software. On a Pi 4B this is the main CPU consumer; if the stream
stutters, lower the camera resolution from the app rather than looking for
a network problem. The `MALLOC_ARENA_MAX=2` setting from the official unit is
kept to bound memory growth.

### GStreamer WebRTC plugins

`webrtcsink`, `webrtcsrc` and `rtpgccbwe` come from `gst-plugins-rs`, which
is not packaged by Debian. The official image downloads a tarball built by
`reachy-mini-os` CI against Trixie's GStreamer 1.26 and published as a
GitHub **release asset** (the tarball used to live in the git tree as an
LFS file; that path now 404s). The setup script uses the same URL and
sha256 as `stage2/05-reachy-mini/files/gst-plugins-rs.pin` in that repo.

---

## Troubleshooting

All daemon output goes to the journal:

```bash
journalctl -u reachy-mini-daemon -n 100 --no-pager
```

### Daemon keeps restarting: "No Reachy Mini serial port found" or cannot open serial port

```bash
ls -l /dev/reachy_mini          # must point at a ttyACM* device
lsusb | grep -i 1a86            # the CH343 adapter must be listed
```

If the symlink is missing, the USB cable or the robot's power is the usual
cause. Re-trigger udev with `sudo udevadm trigger` after plugging in.

### API reachable but no video or audio in the app

1. Confirm wireless mode and the advertised IP:
   ```bash
   curl -s http://<hostname>.local:8000/api/daemon/status | python3 -m json.tool | grep -E 'wireless_version|wlan_ip'
   ```
   `wireless_version` must be `true` and `wlan_ip` must be the Pi's WiFi
   address. A `null` `wlan_ip` means the Pi is not on `wlan0` (Ethernet-only
   Pi): the daemon only reads that interface.
2. The signalling server must listen:
   ```bash
   ss -tlnp | grep 8443
   ```
3. The plugins must be visible:
   ```bash
   gst-inspect-1.0 webrtcsink && gst-inspect-1.0 rtpgccbwe
   ```
   (`GST_PLUGIN_PATH` is set for login shells by `/etc/profile.d/reachy-mini-gst.sh`.)

### No audio (speaker silent or mic dead)

```bash
arecord -l                      # must list "Reachy Mini Audio"
cat ~/.asoundrc                 # card number must match arecord -l
speaker-test -D reachymini_audio_sink -c 2 -t wav -l 1
arecord -D reachymini_audio_src -d 2 -f S16_LE -r 16000 -c 2 /tmp/t.wav
```

The daemon rewrites `~/.asoundrc` at start if the card number changed. If
`arecord -l` shows `Subdevices: 0/1`, the daemon holds the card, which is
correct while it runs.

### Camera not found

```bash
gst-device-monitor-1.0 Video/Source | grep -A3 "Reachy"
v4l2-ctl --list-devices
```

The detection matches a device whose name contains `Reachy`; a generic UVC
name will not be picked up.

---

## Maintenance — adapting for future OS or daemon releases

### Files in this folder

| File | Purpose |
|------|---------|
| `reachy-mini-setup.sh` | Main install script. Runs once on first boot (via cloud-init `runcmd`). |
| `prepare-sd-card.ps1` | Windows helper to inject the script into the SD boot partition. |
| `prepare-sd-card.sh` | Linux / macOS helper — same as the PS1 script but for bash (GNU and BSD tools). |
| `README.md` | This file. |

### Configuration knobs (top of `reachy-mini-setup.sh`)

| Variable | Meaning |
|---|---|
| `REACHY_MINI_VERSION` | Daemon version installed from PyPI. Keep it equal to the SDK version of the app on your laptop. Empty = latest. |
| `DAEMON_SOURCE` | Git URL or absolute path to install instead of PyPI, e.g. `git+https://github.com/your-fork/reachy_mini@my-branch` or `/boot/firmware/reachy_mini_src` (copy the repo to the SD card first). Installed as `reachy-mini[wireless-version] @ <source>`. |
| `GST_PLUGINS_RS_URL` / `_SHA256` | Pre-built plugin tarball. Copy both from `stage2/05-reachy-mini/files/gst-plugins-rs.pin` in `reachy-mini-os` when they bump it. |
| `SERIAL_SYMLINK` | Device node the udev rule creates and the service passes to `--serialport`. |

After editing, re-run `prepare-sd-card.sh --force` (or `-Force`) to copy the
new script to the card, or on a running Pi:
`sudo bash /boot/firmware/reachy-mini-setup.sh`.

### What to change when the daemon releases a new version

1. Bump `REACHY_MINI_VERSION`, and the app on the laptop to match.
2. Check `reachy-mini-os` `stage2/05-reachy-mini/01-run-chroot.sh` for the
   version the official image pins, and `files/gst-plugins-rs.pin` for the
   plugin tarball. If they moved to a GStreamer newer than Trixie's 1.26,
   the apt packages here must follow.
3. Check that `--wireless-version`, `--serialport` and
   `--no-wake-up-on-start` still exist (`reachy-mini-daemon --help`).

### What to change for a new Pi OS release

| Concern | Where to look |
|---|---|
| GStreamer major version | `apt-cache policy libgstreamer1.0-0` on the Pi must match what the plugin tarball was built against (1.26 today). |
| cloud-init changes | `prepare-sd-card.*` — verify the `user-data` format and the `runcmd` path. |
| Default Python version | `uv venv --python 3.12` — bump when the daemon supports newer. |
| Boot partition mount point | Script reads `/boot/firmware/` — Pi OS has used this since Bookworm. |
| Network interface name | `wlan_ip` is read from `wlan0`; if the OS renames interfaces, the daemon's `get_ip_address()` default needs a patch. |

### Key daemon code paths (for debugging)

| File | What it does |
|------|-------------|
| `daemon/app/main.py` `_resolve_bind_host()` | `0.0.0.0` only with `--wireless-version` |
| `daemon/daemon.py` (search `wlan_ip`) | Advertised IP, wireless only |
| `daemon/utils.py` `find_serial_port()` | `/dev/ttyAMA3` in wireless mode, VID/PID scan otherwise |
| `media/device_detection.py` `find_video_device()` | Camera by name: `Reachy` > `Arducam_12MP` > `imx708` |
| `media/media_server.py` `_build_audio_source()` | `.asoundrc` present → ALSA; else PipeWire/Pulse via GStreamer device monitor |
| `media/audio_utils.py` `write_asoundrc_to_home()` | The `dmix`/`dsnoop` config the daemon writes |
| `utils/wireless_version/startup_check.py` | The boot-time fleet checks that log errors here |
| `reachy_mini.py` (search `signalling_host`) | Client side: `wlan_ip or "localhost"` |

### Rebuilding the plugin tarball

Not needed normally: dispatch the `Build gst-plugins-rs` workflow in
`reachy-mini-os` with a `gst-plugins-rs` tag, which publishes a release
asset and its sha256. To build locally on a Pi (slow, needs a recent Rust
toolchain):

```bash
git clone --depth 1 --branch gstreamer-1.29.2 https://github.com/GStreamer/gst-plugins-rs.git
cd gst-plugins-rs
cargo build --release --locked -p gst-plugin-webrtc -p gst-plugin-rtp -p gst-plugin-tracers
```

Then copy the three `.so` files from `target/release/` to
`/opt/gst-plugins-rs/lib/aarch64-linux-gnu/gstreamer-1.0/`.
