#!/bin/bash
set -euo pipefail

# Reachy Mini Daemon — Raspberry Pi 4B Setup Script
# --------------------------------------------------
# Turns a Pi OS Trixie Lite (64-bit) Raspberry Pi into the "brain" of a
# Reachy Mini Lite, so the Lite behaves like a Reachy Mini Wireless on the
# network. It mirrors what the official Wireless image does
# (https://github.com/pollen-robotics/reachy-mini-os, stage2/05-reachy-mini)
# minus the CM4-only hardware (CSI camera, IMU, UART motors, GPIO power
# switch, BLE provisioning):
#   - Pre-built GStreamer WebRTC plugins from the reachy-mini-os releases
#     (no Rust compile), sha256-verified
#   - Daemon from PyPI via uv, with the [wireless-version] extra
#   - Daemon run with --wireless-version so it binds the LAN and advertises
#     its IP for WebRTC, with the USB serial port given explicitly
#   - Audio through ALSA (~/.asoundrc), exactly like the official image
#
# Expected run time: ~15 minutes (depending on SD and download speed)

# --- Configuration -----------------------------------------------------------
# Daemon version to install. Pinning keeps the install reproducible; the
# conversation app on your laptop should use the same SDK version.
# Leave empty to install the latest release from PyPI.
REACHY_MINI_VERSION="1.13.0"

# Leave DAEMON_SOURCE empty to install from PyPI. Set to a git URL or an
# absolute local path to install from a custom branch instead, e.g.:
#   DAEMON_SOURCE="git+https://github.com/your-fork/reachy_mini@my-branch"
#   DAEMON_SOURCE="/boot/firmware/reachy_mini_src"   (copy of repo on SD card)
# When set, REACHY_MINI_VERSION is ignored.
DAEMON_SOURCE=""

# Pre-built gst-plugins-rs (webrtcsink/webrtcsrc/rtpgccbwe) for aarch64,
# built by reachy-mini-os CI against Trixie's GStreamer 1.26. Copied from
# stage2/05-reachy-mini/files/gst-plugins-rs.pin in that repo; update both
# values together when they bump the pin.
GST_PLUGINS_RS_URL="https://github.com/pollen-robotics/reachy-mini-os/releases/download/gst-plugins-rs-gstreamer-1.29.2/gst-plugins-rs-rpi.tar.gz"
GST_PLUGINS_RS_SHA256="6a9174a98a601cba9096cc18855b6c7929f20e1f3667e64464e4319a8a22a177"
GST_INSTALL_DIR="/opt/gst-plugins-rs"

# Stable device node for the robot's USB serial adapter (created by udev).
SERIAL_SYMLINK="/dev/reachy_mini"

# --- Detect user -------------------------------------------------------------
ACTUAL_USER=$(getent passwd 1000 | cut -d: -f1)
ACTUAL_HOME="/home/$ACTUAL_USER"
VENV_DIR="$ACTUAL_HOME/reachy_mini/.venv"

echo "=== Installing Reachy Mini daemon for user: $ACTUAL_USER ==="

# --- System packages ---------------------------------------------------------
echo "[1/7] Installing system packages..."

# Same GStreamer/ALSA stack as the official Wireless image
# (reachy-mini-os stage2/01-sys-tweaks/00-packages-nr), without the camera
# (libcamera), IMU (i2c-tools) and audio-firmware (dfu-util) tooling.
# No PipeWire: in --wireless-version mode the daemon talks ALSA directly
# through ~/.asoundrc, so a sound server would only compete for the card.
PACKAGES=(
    curl git git-lfs ca-certificates
    build-essential pkg-config python3-dev
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
    libgstreamer-plugins-bad1.0-dev
    libglib2.0-dev
    libssl-dev
    libgirepository1.0-dev
    libcairo2-dev
    libportaudio2
    libnice10
    gstreamer1.0-tools
    gstreamer1.0-plugins-base-apps
    gstreamer1.0-plugins-good
    gstreamer1.0-alsa
    gstreamer1.0-plugins-bad
    gstreamer1.0-nice
    alsa-utils
    python3-gi
    python3-gi-cairo
)

# Trixie is rolling-release: packages can be superseded on the mirror during
# the download window, causing 404s. Clean the cache and retry once if needed.
apt_install() {
    apt-get clean
    apt-get update
    apt-get install -y --no-install-recommends "${PACKAGES[@]}"
}

apt_install || {
    echo "  apt install failed — refreshing package lists and retrying..."
    apt_install
}

apt-get clean

# --- GStreamer WebRTC plugins (pre-built) ------------------------------------
echo "[2/7] Installing pre-built GStreamer WebRTC plugins..."
TARBALL="$(mktemp /tmp/gst-plugins-rs.XXXXXX.tar.gz)"
if ! curl -fL --retry 3 -o "$TARBALL" "$GST_PLUGINS_RS_URL"; then
    echo "ERROR: GStreamer plugin download failed. Check internet connectivity and GST_PLUGINS_RS_URL."
    exit 1
fi
echo "${GST_PLUGINS_RS_SHA256}  ${TARBALL}" | sha256sum -c -
tar -xzf "$TARBALL" -C /
rm -f "$TARBALL"
echo "  Installed to ${GST_INSTALL_DIR}."

# Make the plugins visible to interactive sessions too (gst-inspect-1.0 etc.)
GST_PLUGIN_PATH_VALUE="${GST_INSTALL_DIR}/lib/aarch64-linux-gnu"
cat > /etc/profile.d/reachy-mini-gst.sh <<EOF
export GST_PLUGIN_PATH=\${GST_PLUGIN_PATH:+\$GST_PLUGIN_PATH:}${GST_PLUGIN_PATH_VALUE}
EOF

# --- Git LFS for uv (apps from HF Spaces use LFS) ----------------------------
# Mirrors reachy-mini-os#56: login shells + system services.
grep -qxF 'UV_GIT_LFS=1' /etc/environment || echo 'UV_GIT_LFS=1' >> /etc/environment
install -d -m 0755 /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/10-uv-git-lfs.conf <<'EOF'
[Manager]
DefaultEnvironment="UV_GIT_LFS=1"
EOF

# --- Python environment & daemon --------------------------------------------
echo "[3/7] Installing uv and daemon..."
sudo -u "$ACTUAL_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
UV="$ACTUAL_HOME/.local/bin/uv"

mkdir -p "$ACTUAL_HOME/reachy_mini"
chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/reachy_mini"
sudo -u "$ACTUAL_USER" "$UV" venv "$VENV_DIR" --python 3.12

if [[ -n "$DAEMON_SOURCE" ]]; then
    # PEP 508 direct reference: works for git+https URLs and absolute paths.
    SPEC="reachy-mini[wireless-version] @ ${DAEMON_SOURCE}"
elif [[ -n "$REACHY_MINI_VERSION" ]]; then
    SPEC="reachy-mini[wireless-version]==${REACHY_MINI_VERSION}"
else
    SPEC="reachy-mini[wireless-version]"
fi
echo "  Installing: $SPEC"
sudo -u "$ACTUAL_USER" env UV_GIT_LFS=1 "$UV" pip install --python "$VENV_DIR/bin/python" "$SPEC"

# --- udev rules --------------------------------------------------------------
echo "[4/7] Configuring udev rules..."
cat > /etc/udev/rules.d/99-reachy-mini.rules <<UDEV
# Robot body: CH343 USB serial (cdc-acm). Stable symlink for --serialport.
SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", MODE="0666", SYMLINK+="${SERIAL_SYMLINK#/dev/}"
# Reachy Mini Audio (USB sound card + mic array). pyusb needs rw access.
SUBSYSTEM=="usb", ATTRS{idVendor}=="38fb", ATTRS{idProduct}=="1001", MODE="0666"
# Older ReSpeaker firmware
SUBSYSTEM=="usb", ATTRS{idVendor}=="2886", ATTRS{idProduct}=="001a", MODE="0666"
UDEV
udevadm control --reload-rules && udevadm trigger
usermod -aG dialout,audio,plugdev "$ACTUAL_USER"

# --- Scoped passwordless sudo ------------------------------------------------
echo "[5/7] Granting scoped sudo..."
# The daemon's "restart" action and the wireless startup checks shell out to
# sudo with no TTY. Grant only the fixed commands they need (same approach as
# the official image; it uses more because it also manages BLE/WiFi).
cat > /etc/sudoers.d/010-reachy-mini <<EOF
Cmnd_Alias REACHY = \\
    /usr/bin/systemctl restart reachy-mini-daemon, \\
    /usr/bin/systemctl daemon-reload, \\
    /usr/sbin/rfkill unblock wifi, \\
    /usr/sbin/shutdown -h now
${ACTUAL_USER} ALL=(root) NOPASSWD: REACHY
EOF
chmod 0440 /etc/sudoers.d/010-reachy-mini
visudo -cf /etc/sudoers.d/010-reachy-mini

# --- systemd service ---------------------------------------------------------
echo "[6/7] Creating systemd service..."
# --wireless-version: bind the API on all interfaces, advertise the Pi's
#   wlan0 IP so SDK clients know where the WebRTC signalling server is, and
#   use ALSA via ~/.asoundrc (the daemon writes it on first start).
# --serialport: in wireless mode the daemon expects the CM4 UART; point it at
#   the Lite's USB adapter instead.
# --no-wake-up-on-start: same as the official image; the app wakes the robot.
tee /etc/systemd/system/reachy-mini-daemon.service > /dev/null <<SVCEOF
[Unit]
Description=Reachy Mini Daemon (Lite body, wireless mode)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$VENV_DIR/bin/reachy-mini-daemon --wireless-version --serialport ${SERIAL_SYMLINK} --no-wake-up-on-start
WorkingDirectory=$ACTUAL_HOME/reachy_mini
Restart=on-failure
RestartSec=3s
User=$ACTUAL_USER
Environment=PATH=$ACTUAL_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=GST_PLUGIN_PATH=${GST_PLUGIN_PATH_VALUE}
Environment=UV_GIT_LFS=1
# Cap glibc malloc arenas on the Pi 4 (reachy_mini#1165, same as official unit)
Environment=MALLOC_ARENA_MAX=2

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable reachy-mini-daemon

# --- Version marker ----------------------------------------------------------
echo "[7/7] Finalizing..."
INSTALLED_VERSION=$(sudo -u "$ACTUAL_USER" "$UV" pip show --python "$VENV_DIR/bin/python" reachy-mini 2>/dev/null | grep '^Version:' | cut -d' ' -f2)
cat > "$ACTUAL_HOME/VERSION.txt" <<EOF
reachy-mini-daemon: ${INSTALLED_VERSION}
gst-plugins-rs: ${GST_PLUGINS_RS_URL##*/download/}
setup-date: $(date '+%Y-%m-%d %H:%M')
platform: $(uname -m) / $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
EOF
chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/VERSION.txt"

echo "=== Reachy Mini setup complete! Rebooting in 5 seconds... ==="
sleep 5
reboot
