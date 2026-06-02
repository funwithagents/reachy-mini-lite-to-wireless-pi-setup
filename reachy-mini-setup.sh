#!/bin/bash
set -e

# Reachy Mini Daemon — Raspberry Pi 4B Setup Script
# --------------------------------------------------
# Installs the daemon on Pi OS Trixie Lite (64-bit) using:
#   - Pre-built GStreamer WebRTC plugin (no Rust compile)
#   - PipeWire for audio (same as the official CM4 image)
#   - Daemon from PyPI via uv
#
# Expected run time: 15 minutes (depending on SD and download speed)

# --- Configuration -----------------------------------------------------------
# Leave DAEMON_SOURCE empty to install the latest release from PyPI.
# Set to a git URL or local path to install from a custom branch instead, e.g.:
#   DAEMON_SOURCE="git+https://github.com/your-fork/reachy_mini@my-branch"
#   DAEMON_SOURCE="/boot/firmware/reachy_mini_src"   (copy of repo on SD card)
DAEMON_SOURCE=""
GST_TARBALL_URL="https://github.com/pollen-robotics/reachy-mini-os/raw/develop/stage2/05-reachy-mini/files/gst-plugins-rs-rpi.tar.gz"
GST_INSTALL_DIR="/opt/gst-plugins-rs"

# --- Detect user -------------------------------------------------------------
ACTUAL_USER=$(getent passwd 1000 | cut -d: -f1)
ACTUAL_HOME="/home/$ACTUAL_USER"
ACTUAL_UID=$(id -u "$ACTUAL_USER")
VENV_DIR="$ACTUAL_HOME/reachy_mini/.venv"

echo "=== Installing Reachy Mini daemon (latest) for user: $ACTUAL_USER ==="

# --- System packages ---------------------------------------------------------
echo "[1/7] Installing system packages..."

PACKAGES=(
    curl git
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
    gstreamer1.0-plugins-good
    gstreamer1.0-alsa
    gstreamer1.0-plugins-bad
    gstreamer1.0-nice
    python3-gi
    python3-gi-cairo
    pipewire-audio
    gstreamer1.0-pipewire
    wireplumber
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

# --- PipeWire: enable linger so it starts at boot without a login session ----
echo "[2/7] Configuring PipeWire..."
loginctl enable-linger "$ACTUAL_USER"

# --- GStreamer WebRTC plugin (pre-built) -------------------------------------
echo "[3/7] Installing pre-built GStreamer WebRTC plugin..."
# The tarball must match the GStreamer version installed by apt (which advances
# with Trixie), so we always download the latest from the reachy-mini-os repo.
if ! curl -fsSL "$GST_TARBALL_URL" | tar -xz -C /; then
    echo "ERROR: GStreamer tarball download failed. Check internet connectivity."
    exit 1
fi
echo "  Downloaded and extracted from GitHub."

# --- Python environment & daemon --------------------------------------------
echo "[4/7] Installing uv and daemon..."
sudo -u "$ACTUAL_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
UV="$ACTUAL_HOME/.local/bin/uv"

mkdir -p "$ACTUAL_HOME/reachy_mini"
chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/reachy_mini"
sudo -u "$ACTUAL_USER" "$UV" venv "$VENV_DIR" --python 3.12
if [[ -n "$DAEMON_SOURCE" ]]; then
    echo "  Installing from custom source: $DAEMON_SOURCE"
    sudo -u "$ACTUAL_USER" "$UV" pip install --python "$VENV_DIR/bin/python" \
        "${DAEMON_SOURCE}[gstreamer]"
else
    sudo -u "$ACTUAL_USER" "$UV" pip install --python "$VENV_DIR/bin/python" \
        "reachy-mini[gstreamer]"
fi

# --- udev rules --------------------------------------------------------------
echo "[5/7] Configuring udev rules..."
cat > /etc/udev/rules.d/99-reachy-mini.rules <<'UDEV'
# CH340 serial (robot body)
SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", MODE="0666", GROUP="dialout"
# Reachy Mini Audio (USB sound card)
SUBSYSTEM=="usb", ATTRS{idVendor}=="38fb", ATTRS{idProduct}=="1001", MODE="0666", GROUP="dialout"
UDEV
udevadm control --reload-rules && udevadm trigger
usermod -aG dialout "$ACTUAL_USER"

# --- systemd service ---------------------------------------------------------
echo "[6/7] Creating systemd service..."
tee /etc/systemd/system/reachy-mini-daemon.service > /dev/null <<SVCEOF
[Unit]
Description=Reachy Mini Daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$VENV_DIR/bin/reachy-mini-daemon --no-localhost-only
WorkingDirectory=$ACTUAL_HOME/reachy_mini
Restart=always
User=$ACTUAL_USER
Environment=PATH=$ACTUAL_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=GST_PLUGIN_PATH=${GST_INSTALL_DIR}/lib/aarch64-linux-gnu
Environment=XDG_RUNTIME_DIR=/run/user/${ACTUAL_UID}

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
setup-date: $(date '+%Y-%m-%d %H:%M')
platform: $(uname -m) / $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
EOF
chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/VERSION.txt"

echo "=== Reachy Mini setup complete! Rebooting in 5 seconds... ==="
sleep 5
reboot
