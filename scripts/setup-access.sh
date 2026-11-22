#!/usr/bin/env bash
# Set up remote access on a GitHub-hosted macOS runner:
#   - Tailscale (authkey if TS_AUTHKEY set, else interactive login URL in logs)
#   - SSH (remote login + your GitHub authorized_keys)
#   - VNC (screen sharing + legacy VNC password + vncuser account)
#
# Env knobs:
#   TS_AUTHKEY        - tailscale auth key (reusable/ephemeral). Optional.
#   TS_HOSTNAME       - tailnet hostname for the node. Default: gh-macos-<run_id>
#   SSH_KEYS_URL      - URL returning authorized_keys lines. Default: github.com/spacedouut.keys
#   EXTRA_SSH_KEYS    - literal pubkey line(s) appended to authorized_keys. Optional.
#   ENABLE_SSH        - "true"/"false". Default true.
#   ENABLE_VNC        - "true"/"false". Default true.
#   VNC_PASSWORD      - legacy VNC password (8 chars max effective). Random if unset.
#   VNC_USER_PASSWORD - password for the created `vncuser` account. Random if unset.
set -uo pipefail

ENABLE_SSH="${ENABLE_SSH:-true}"
ENABLE_VNC="${ENABLE_VNC:-true}"
TS_HOSTNAME="${TS_HOSTNAME:-gh-macos-${GITHUB_RUN_ID:-local}}"
SSH_KEYS_URL="${SSH_KEYS_URL:-https://github.com/spacedouut.keys}"
KICKSTART=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart

sec() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }

# Keep the VM (and its console session, for VNC) awake.
sudo pmset -a sleep 0 displaysleep 0 2>/dev/null || true
defaults -currentHost write com.apple.screensaver idleTime -int 0 2>/dev/null || true
caffeinate -dimsu &
CAFFEINE_PID=$!

sec "Install & start tailscaled"
brew list tailscale &>/dev/null || brew install tailscale
sudo pkill -x tailscaled 2>/dev/null || true
sleep 1
sudo nohup tailscaled --statedir=/tmp/tailscale-state >/tmp/tailscaled.log 2>&1 &
for i in $(seq 1 30); do sudo tailscale status &>/dev/null && break; sleep 1; done
sudo tailscale version

sec "Tailscale up"
if [ -n "${TS_AUTHKEY:-}" ]; then
  sudo tailscale up --auth-key "$TS_AUTHKEY" --hostname "$TS_HOSTNAME" --timeout 60s
else
  echo "No TS_AUTHKEY — starting interactive login. Watch for the URL below."
  sudo nohup tailscale up --hostname "$TS_HOSTNAME" >/tmp/tsup.log 2>&1 &
  LOGIN_URL=""
  for i in $(seq 1 15); do
    LOGIN_URL=$(grep -o 'https://login.tailscale.com/[a-zA-Z0-9/?&=_-]*' /tmp/tsup.log 2>/dev/null | head -1)
    [ -n "$LOGIN_URL" ] && break
    sleep 1
  done
  echo ">>> $LOGIN_URL <<<"
  echo ">>> Open the URL above on any device to add this runner to your tailnet <<<"
  [ -n "$LOGIN_URL" ] && echo "## Tailscale login: $LOGIN_URL" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi
sleep 2
TS_IP="$(sudo tailscale ip -4 2>/dev/null | head -1 || true)"
echo "tailscale ip: ${TS_IP:-<not connected yet>}"
sudo tailscale status 2>/dev/null | head -5 || true

if [ "$ENABLE_SSH" = "true" ]; then
  sec "Enable SSH (Remote Login)"
  sudo systemsetup -setremotelogin on 2>/dev/null \
    || sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  curl -fsSL "$SSH_KEYS_URL" >> ~/.ssh/authorized_keys 2>/dev/null \
    && echo "installed keys from $SSH_KEYS_URL" || echo "WARN: could not fetch $SSH_KEYS_URL"
  [ -n "${EXTRA_SSH_KEYS:-}" ] && printf '%s\n' "$EXTRA_SSH_KEYS" >> ~/.ssh/authorized_keys
  sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo "authorized_keys entries: $(wc -l < ~/.ssh/authorized_keys | tr -d ' ')"
  sudo launchctl list 2>/dev/null | grep -i ssh || true
fi

if [ "$ENABLE_VNC" = "true" ]; then
  sec "Enable Screen Sharing / VNC"
  VNC_PASSWORD="${VNC_PASSWORD:-$(openssl rand -hex 4)}"          # legacy VNC auth caps at 8 chars
  VNC_USER_PASSWORD="${VNC_USER_PASSWORD:-$(openssl rand -hex 8)}"

  # Dedicated GUI user (Apple Screen Sharing app auths as a real user).
  if ! dscl . -read /Users/vncuser &>/dev/null; then
    sudo dscl . -create /Users/vncuser
    sudo dscl . -create /Users/vncuser UserShell /bin/bash
    sudo dscl . -create /Users/vncuser RealName "VNC User"
    sudo dscl . -create /Users/vncuser UniqueID 1001
    sudo dscl . -create /Users/vncuser PrimaryGroupID 80
    sudo dscl . -create /Users/vncuser NFSHomeDirectory /Users/vncuser
    sudo createhomedir -c -u vncuser >/dev/null 2>&1 || true
  fi
  sudo dscl . -passwd /Users/vncuser "$VNC_USER_PASSWORD"
  sudo dscl . -append /Groups/admin GroupMembership vncuser 2>/dev/null || true

  sudo "$KICKSTART" -activate -configure -access -on -restart -agent \
    -privs -all -allowAccessFor -allUsers 2>&1 | tail -3
  sudo "$KICKSTART" -configure -clientopts -setvnclegacy -vnclegacy yes 2>&1 | tail -2
  sudo "$KICKSTART" -configure -clientopts -setvncpw -vncpw "$VNC_PASSWORD" 2>&1 | tail -2

  # Belt-and-suspenders: hashed VNC password file (classic trick).
  echo "$VNC_PASSWORD" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' \
    | sudo tee /Library/Preferences/com.apple.VNCSettings.txt >/dev/null
  sudo "$KICKSTART" -restart -agent -console 2>&1 | tail -2 || true

  echo "VNC legacy password : $VNC_PASSWORD"
  echo "vncuser password    : $VNC_USER_PASSWORD"
fi

sec "Summary"
cat <<EOF
runner hostname : $(hostname)
local user      : $(whoami)
tailscale ip    : ${TS_IP:-<pending - check `tailscale status`>}
EOF
[ "$ENABLE_SSH" = "true" ] && echo "ssh             : ssh $(whoami)@${TS_IP:-<ts-ip>}"
[ "$ENABLE_VNC" = "true" ] && echo "vnc             : vnc://${TS_IP:-<ts-ip>}:5900"

{
  echo "## Remote access"
  echo ""
  echo "| thing | value |"
  echo "|---|---|"
  echo "| tailscale ip | \`${TS_IP:-pending}\` |"
  [ "$ENABLE_SSH" = "true" ] && echo "| ssh | \`ssh $(whoami)@${TS_IP:-<ts-ip>}\` |"
  [ "$ENABLE_VNC" = "true" ] && echo "| vnc | \`vnc://${TS_IP:-<ts-ip>}:5900\` |"
  [ "$ENABLE_VNC" = "true" ] && echo "| vnc legacy pw | \`${VNC_PASSWORD}\` |"
  [ "$ENABLE_VNC" = "true" ] && echo "| vncuser pw | \`${VNC_USER_PASSWORD}\` |"
} >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true

kill "$CAFFEINE_PID" 2>/dev/null || true
exit 0
