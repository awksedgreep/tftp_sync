#!/usr/bin/env bash
set -euo pipefail

APP_NAME="tftp_sync"
APP_USER="tftp_sync"
APP_GROUP="tftp_sync"
APP_DIR="/opt/tftp_sync"
RELEASE_DIR="$APP_DIR/_build/prod/rel/$APP_NAME"
SERVICE_FILE="/etc/systemd/system/tftp_sync.service"

TFTP_SOURCE_DIR="/srv/tftp"
TFTP_API_URL="http://192.168.160.220:4000"

echo "==> Creating application user/group ($APP_USER)..."
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER" || true
fi

echo "==> Ensuring app directory exists and has correct ownership..."
sudo mkdir -p "$APP_DIR"
sudo chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"

echo "==> Copying project into $APP_DIR (if not already there)..."
# If you're running this from the source tree, sync it into APP_DIR.
if [ "$(pwd)" != "$APP_DIR" ]; then
  sudo rsync -a --delete "$(pwd)/" "$APP_DIR/"
  sudo chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
fi

cd "$APP_DIR"

echo "==> Building release in $APP_DIR..."
export MIX_ENV=prod

sudo -u "$APP_USER" mix deps.get
sudo -u "$APP_USER" mix compile
sudo -u "$APP_USER" mix release

echo "==> Writing systemd unit to $SERVICE_FILE..."
sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=tftp_sync daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
ExecStart=$RELEASE_DIR/bin/$APP_NAME start
Restart=always
RestartSec=5

# Hardening (tune as needed)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

echo "==> Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable "$APP_NAME"
sudo systemctl restart "$APP_NAME"

echo "==> Deployment complete. Check status with:"
echo "    systemctl status $APP_NAME"
echo "    journalctl -u $APP_NAME -f"
