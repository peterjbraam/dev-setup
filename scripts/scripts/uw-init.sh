#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${1:-${SUDO_USER:-${USER:-braam}}}"

if ! id "$USER_NAME" >/dev/null 2>&1; then
  echo "User does not exist: $USER_NAME" >&2
  exit 1
fi

USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
  echo "Could not determine home directory for $USER_NAME" >&2
  exit 1
fi

echo "==> Installing XRDP + Xfce"
sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies

echo "==> Writing /etc/X11/Xwrapper.config"
printf "allowed_users=anybody\n" | sudo tee /etc/X11/Xwrapper.config >/dev/null

echo "==> Configuring /etc/xrdp/startwm.sh"
sudo cp /etc/xrdp/startwm.sh "/etc/xrdp/startwm.sh.bak.$(date +%Y%m%d-%H%M%S)"
sudo awk '
  BEGIN {done=0}
  /startxfce4/ {next}
  {print}
  END {
    print "unset DBUS_SESSION_BUS_ADDRESS"
    print "unset XDG_RUNTIME_DIR"
    print "startxfce4"
  }
' /etc/xrdp/startwm.sh | sudo tee /etc/xrdp/startwm.sh.new >/dev/null
sudo mv /etc/xrdp/startwm.sh.new /etc/xrdp/startwm.sh
sudo chmod 755 /etc/xrdp/startwm.sh

echo "==> Writing ${USER_HOME}/.xsession"
printf "xfce4-session\n" | sudo tee "${USER_HOME}/.xsession" >/dev/null
sudo chown "$USER_NAME:$USER_NAME" "${USER_HOME}/.xsession"
sudo chmod 644 "${USER_HOME}/.xsession"

echo "==> Clearing stale Xfce/XRDP session state for $USER_NAME"
sudo rm -f "${USER_HOME}"/.cache/sessions/* 2>/dev/null || true
sudo pkill -u "$USER_NAME" xfce4-session 2>/dev/null || true
sudo pkill -u "$USER_NAME" xfwm4 2>/dev/null || true
sudo pkill -u "$USER_NAME" xrdp-chansrv 2>/dev/null || true
sudo pkill -u "$USER_NAME" Xorg 2>/dev/null || true

echo "==> Disabling lightdm if present"
if dpkg -s lightdm >/dev/null 2>&1; then
  sudo systemctl disable lightdm 2>/dev/null || true
fi

echo "==> Enabling XRDP services"
sudo systemctl enable xrdp xrdp-sesman
sudo systemctl restart xrdp xrdp-sesman

echo
echo "==> Verification"
sudo systemctl --no-pager --full status xrdp xrdp-sesman || true
echo
echo "==> Port check"
ss -ltnp | grep 3389 || true
echo
echo "==> User session file"
sudo sed -n '1,20p' "${USER_HOME}/.xsession"
echo
echo "==> IP addresses"
hostname -I
echo
echo "Done. Connect from the Mac with:"
echo "  ./uw.sh \$(hostname -I | awk '{print \$1}') $USER_NAME"
