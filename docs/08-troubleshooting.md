# 08 — Troubleshooting and daily use

## Daily use

```bash
make up SITE=a            # after rebooting the computer: start the site's VMs (OPNsense first)
make down SITE=a          # before switching the computer off: clean shutdown of all VMs
make help                 # every command
```

Both sites on one computer: add `MODE=lab` to every **Site B** command.
RAM: one site needs about 4.3 GiB, both sites about 8.7 GiB. `make down SITE=b MODE=lab`
frees Site B when you only work on Site A.

## Golden rule: never hard-kill OPNsense

We found (2026-10-30) that the **OPNsense nano image does not boot again after a
hard power-off** — the VM uses CPU but prints nothing on its console: it hangs in the
first boot stage, before the FreeBSD loader. A clean shutdown + start is fine; a
`virsh destroy`, a crash or switching the laptop off with VMs running is not.

What we did about it:

- `make down` shuts the VMs down **cleanly** (ACPI) — use it before switching off.
- [scripts/bootstrap-host.sh](../scripts/bootstrap-host.sh) sets libvirt-guests to
  **shut down** (not suspend/kill) VMs when the computer shuts down. Re-run
  `sudo ./scripts/bootstrap-host.sh` once if your computer was bootstrapped before this change.
- Recovery when it happens:

  ```bash
  make opnsense-rebuild SITE=a     # fresh firewall disk + console bootstrap (~70 s)
  ```

  Then **restore your configuration**: GUI → **System → Configuration → Backups →
  Restore**, choose `.secrets/opnsense/a-opnsense-config.xml` (made by `make
  opnsense-backup`). Without a backup you redo the UI steps of docs/02, 05 and 06.
  **So: `make opnsense-backup` after every GUI session.**

How to recognise it: `make test-phase2` fails with *No route to host* on `https://10.0.2.1`,
`virsh -c qemu:///system list` shows the VM *running*, and
`virsh -c qemu:///system console a-opnsense` shows nothing at all.

## Symptoms and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| `virsh: permission denied` | terminal opened before the bootstrap added you to `libvirt` | log out/in, or `sg libvirt -c "..."`; `make` handles it for you |
| `make phase1 SITE=b` refused on the Site A computer | Site B without `MODE=lab` would redefine the shared WAN | add `MODE=lab` |
| VMs have no Internet | OPNsense down, or WAN gateway missing | `make test-phase2`; docs/02 "If something goes wrong" |
| `apt` lock errors | Ubuntu automatic updates | `make phase3` (role `base` removes them) |
| VMs' Internet stops when Docker restarts | Docker's FORWARD DROP policy | re-run `sudo ./scripts/bootstrap-host.sh` (installs the hook) |
| A VM looks dead | | `virsh -c qemu:///system console a-web` (user `infra`, password `.secrets/vm_console_password`, exit `Ctrl + ]`) |
| Everything is broken | | `make destroy SITE=a` then `make all SITE=a` (VMs rebuilt in ~10 min; the OPNsense GUI steps must be redone or restored from backup) |

## Why can't the LANs talk without IPsec, even on one computer?

On one computer, the hypervisor has an address on **both** LANs (`10.0.2.254`
and `10.15.15.254`) to manage the VMs. Without care, OPNsense A would send
`10.15.15.7` to its WAN gateway (the hypervisor), which would happily forward it
to Site B's LAN — a path **outside the tunnel**, with NAT. We found this while
writing the acceptance test (`/whoami` answered `10.15.15.254` instead of
`10.0.2.7`).

Fix: a libvirt **network filter** on each OPNsense WAN card
([wan-filter.xml.j2](../roles/opnsense_vm/templates/wan-filter.xml.j2)) drops
packets towards the lab LANs, like the real Internet never routes private
addresses. `make test-phase2` checks it: the other site may only answer through
IPsec, with our real address.

```bash
virsh -c qemu:///system nwfilter-dumpxml infra-wan-no-lab-lan
```
