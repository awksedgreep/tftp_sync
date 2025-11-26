#!/usr/bin/env bash
set -euo pipefail

APP_NAME="tftp_sync"
APP_DIR="/opt/tftp_sync"
SERVICE_FILE="/etc/systemd/system/tftp_sync.service"

echo "==> Installing deps and compiling..."
cd "$APP_DIR"
mix deps.get --only prod
MIX_ENV=prod mix compile

echo "==> Writing systemd unit to $SERVICE_FILE..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=tftp_sync daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/env MIX_ENV=prod mix run --no-halt
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable "$APP_NAME"
systemctl restart "$APP_NAME"

echo "==> Done. Check with:"
echo "    systemctl status $APP_NAME"
echo "    journalctl -u $APP_NAME -f"
