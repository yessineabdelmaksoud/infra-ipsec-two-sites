#!/usr/bin/env bash
# One-time host preparation (needs root). Idempotent: safe to re-run.
#   sudo ./scripts/bootstrap-host.sh [username]
# Installs KVM/libvirt, grants the user access to libvirt, and installs a libvirt
# network hook so Docker's iptables FORWARD DROP policy does not block lab bridges.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi
TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
  echo "usage: sudo $0 <username>" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
  qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virtinst \
  python3-libvirt python3-lxml python3-venv xorriso bzip2 netcat-openbsd \
  dnsmasq-base iptables

usermod -aG libvirt,kvm "$TARGET_USER"
systemctl enable --now libvirtd.socket virtqemud.socket virtnetworkd.socket virtstoraged.socket 2>/dev/null \
  || systemctl enable --now libvirtd

# Docker sets the iptables FORWARD policy to DROP. Allow traffic to and from the
# lab bridges (virbr-i*) through DOCKER-USER, both when a libvirt network starts
# and after Docker (re)starts, whichever comes last.
# The helper lives under /etc/libvirt/hooks/: Ubuntu's libvirtd AppArmor profile
# only lets hooks execute from there (and /usr/sbin), not from /usr/local/sbin.
HELPER=/etc/libvirt/hooks/lib/infra-allow-lab-bridges
install -d -m 755 /etc/libvirt/hooks/lib
rm -f /usr/local/sbin/infra-allow-lab-bridges
cat > "$HELPER" <<'SCRIPT'
#!/bin/sh
# Installed by infra/scripts/bootstrap-host.sh
command -v iptables >/dev/null || exit 0
iptables -n -L DOCKER-USER >/dev/null 2>&1 || exit 0
for dir in -i -o; do
  iptables -C DOCKER-USER $dir virbr-i+ -j ACCEPT 2>/dev/null \
    || iptables -I DOCKER-USER $dir virbr-i+ -j ACCEPT
done
SCRIPT
chmod 755 "$HELPER"

cat > /etc/libvirt/hooks/network <<'HOOK'
#!/bin/sh
# Installed by infra/scripts/bootstrap-host.sh — args: <network> <operation> <sub-op>
case "$2" in
  started|updated) exec /etc/libvirt/hooks/lib/infra-allow-lab-bridges ;;
esac
HOOK
chmod 755 /etc/libvirt/hooks/network

cat > /etc/systemd/system/infra-allow-lab-bridges.service <<'UNIT'
[Unit]
Description=Allow libvirt lab bridges through Docker's FORWARD policy
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
ExecStart=/etc/libvirt/hooks/lib/infra-allow-lab-bridges

[Install]
WantedBy=docker.service
UNIT
systemctl daemon-reload
systemctl enable infra-allow-lab-bridges.service
systemctl start infra-allow-lab-bridges.service || true
# The network daemon only reads hooks at start.
systemctl try-restart virtnetworkd.service libvirtd.service 2>/dev/null || true

echo
echo "Host ready. Next (as $TARGET_USER, no sudo): make setup && make phase1 SITE=<a|b>"
