#!/bin/bash
set -euo pipefail

IP="${1:-192.168.64.93}"
USER_NAME="${2:-braam}"
RDP_FILE="/tmp/ubuntu-vm-${USER_NAME}.rdp"

cat >"$RDP_FILE" <<EOF
full address:s:${IP}:3389
username:s:${USER_NAME}
prompt for credentials on client:i:1
screen mode id:i:2
use multimon:i:0
authentication level:i:2
redirectclipboard:i:1
drivestoredirect:s:
EOF

open -a "Windows App" "$RDP_FILE" 2>/dev/null || \
open -a "Microsoft Remote Desktop" "$RDP_FILE"
