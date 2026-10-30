#!/usr/bin/env bash
# Joins this computer's lab WAN bridge to a physical Ethernet port, so the two
# students' computers (connected by a cable or a switch) share one WAN segment
# 192.168.100.0/24 and the two OPNsense firewalls can build the IPsec tunnel.
# Run it on BOTH computers (needs root, not persistent across reboots):
#   sudo ./scripts/wan-link.sh enp3s0          # attach
#   sudo ./scripts/wan-link.sh enp3s0 --down   # detach
# Then from Site A's computer: ping 192.168.100.2 (Site B's computer) and
# ping 192.168.100.12 (Site B's OPNsense WAN).
set -euo pipefail

BRIDGE=virbr-iwan
IFACE="${1:-}"
if [[ $EUID -ne 0 || -z "$IFACE" ]]; then
  echo "usage: sudo $0 <ethernet-interface> [--down]   (interfaces: $(ls /sys/class/net | tr '\n' ' '))" >&2
  exit 1
fi
if [[ ! -e /sys/class/net/$BRIDGE ]]; then
  echo "$BRIDGE does not exist: run 'make phase1 SITE=<a|b>' first" >&2
  exit 1
fi

if [[ "${2:-}" == "--down" ]]; then
  ip link set dev "$IFACE" nomaster
  echo "$IFACE detached from $BRIDGE"
  exit 0
fi

# The port only carries the lab WAN: it must not keep its own address or be
# managed by NetworkManager while it is a bridge port.
if command -v nmcli >/dev/null; then
  nmcli device set "$IFACE" managed no || true
fi
ip addr flush dev "$IFACE"
ip link set dev "$IFACE" up
ip link set dev "$IFACE" master "$BRIDGE"
echo "$IFACE attached to $BRIDGE:"
bridge link show master "$BRIDGE"
