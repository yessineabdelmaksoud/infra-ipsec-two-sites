# Command reference — setup, daily use, monitoring, troubleshooting

Every command used in this project, grouped by **what you want to do**.
Site A values are shown; for Site B use `SITE=b` and the Site B addresses
(`10.15.15.x`, WAN `192.168.100.12`). Explanations of *why* are in the phase docs.

**Where does each command run?** The prompt tells you:

| Prompt | Where | How to get there |
|---|---|---|
| `laptop$` | your computer, in the repository folder | a terminal, `cd infra` |
| `vm$` | inside a Linux VM | `ssh -i .secrets/infra_ed25519 infra@<IP>` |
| `opnsense#` | the OPNsense shell | `ssh -i .secrets/infra_ed25519 root@10.0.2.1` (after SSH is enabled, docs/02 step 4), or console option `8` |

**Variables of every `make` command:**

| Variable | Values | Default | Meaning |
|---|---|---|---|
| `SITE` | `a`, `b` | `a` | which site to act on |
| `MODE` | `distributed`, `lab` | `distributed` | `lab` = both sites on one computer: add `MODE=lab` to **Site B** commands there |
| `ARGS` | any Ansible options | — | e.g. `ARGS="-v"` (more detail), `ARGS="--check --diff"` (dry run) |

---

## 1. One-time setup of a computer

```bash
laptop$ ls /dev/kvm                                # must exist (else enable VT-x/AMD-V in the BIOS)
laptop$ git clone <repository-url> infra && cd infra
laptop$ sudo ./scripts/bootstrap-host.sh           # KVM, libvirt, groups, Docker hook, clean VM shutdown
                                                   # then log out and in once (libvirt group)
laptop$ make setup                                 # .venv with pinned Ansible + .secrets/infra_ed25519
```

Check it worked:

```bash
laptop$ virsh -c qemu:///system uri                # qemu:///system
laptop$ .venv/bin/ansible --version | head -1      # ansible [core 2.21.5]
laptop$ make help                                  # the list of targets
```

## 2. Build a site

```bash
laptop$ make all SITE=a                 # phases 1-4 in one go (~15 min the first time)

# or phase by phase, each followed by its test:
laptop$ make phase1 SITE=a && make test-phase1 SITE=a   # networks + 4 Linux VMs
laptop$ make phase2 SITE=a && make test-phase2 SITE=a   # OPNsense VM + console bootstrap
laptop$ make phase3 SITE=a && make test-phase3 SITE=a   # MySQL + web page
laptop$ make phase4 SITE=a && make test-phase4 SITE=a   # HAProxy + Keepalived + VIP failover
```

Site B **on the same computer** (rehearsal): `make all SITE=b MODE=lab`.
Site B **on its own computer**: `make all SITE=b`.

Then the OPNsense web interface (by hand, guides with every value):

| Step | Guide | Then run |
|---|---|---|
| Wizard, LAN-only GUI/SSH, root SSH key | [docs/02](02-phase2-opnsense.md) | `make opnsense-backup SITE=a` · `make test-phase2 SITE=a` |
| Destination NAT 80/443 → VIP, WAN rules | [docs/05](05-phase5-nat-firewall.md) | `make test-phase5 SITE=a` · `make opnsense-backup SITE=a` |
| IPsec (both students) | [docs/06](06-phase6-ipsec.md) | `make test-phase6 SITE=a` · `make opnsense-backup SITE=a` |

```bash
laptop$ make ipsec-psk                  # once, Student 1: creates .secrets/ipsec-psk
laptop$ cat .secrets/ipsec-psk          # the value to paste in VPN -> IPsec -> Pre-Shared Keys
```

## 3. Two computers: the WAN cable

```bash
laptop$ ip -br link                             # find the Ethernet port, e.g. enp3s0
laptop$ sudo ./scripts/wan-link.sh enp3s0       # on BOTH computers, after phase 1
laptop$ ping -c 3 192.168.100.2                 # from A: Site B's computer
laptop$ ping -c 3 192.168.100.12                # from A: Site B's OPNsense WAN
laptop$ sudo ./scripts/wan-link.sh enp3s0 --down   # detach the port again
```

## 4. Daily use

```bash
laptop$ make up SITE=a          # start the site's VMs (OPNsense first) and wait for SSH
laptop$ make status SITE=a      # one-screen health view (see section 5)
laptop$ make down SITE=a        # clean shutdown — ALWAYS before switching the computer off
```

Log into the machines:

```bash
laptop$ ssh -i .secrets/infra_ed25519 infra@10.0.2.5    # a-haproxy1
laptop$ ssh -i .secrets/infra_ed25519 infra@10.0.2.6    # a-haproxy2
laptop$ ssh -i .secrets/infra_ed25519 infra@10.0.2.7    # a-web
laptop$ ssh -i .secrets/infra_ed25519 infra@10.0.2.8    # a-db
laptop$ ssh -i .secrets/infra_ed25519 root@10.0.2.1     # a-opnsense (after docs/02 step 4-5)
```

Tip — a shortcut for your shell (put it in `~/.bashrc`, run from the repository):

```bash
vm() { ssh -i .secrets/infra_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR infra@"$1" "${@:2}"; }
laptop$ vm 10.0.2.7                          # interactive
laptop$ vm 10.0.2.6 ip -br addr show lan0    # one command
```

Web interfaces (browser **on the laptop**, which is on the LANs as `.254`):

| What | Site A | Site B |
|---|---|---|
| OPNsense GUI | https://10.0.2.1 | https://10.15.15.1 |
| Site through the VIP | http://10.0.2.100 | http://10.15.15.100 |
| Site through the WAN (as the Internet sees it) | http://192.168.100.11 | http://192.168.100.12 |
| HAProxy statistics | http://10.0.2.5:8404/stats · http://10.0.2.6:8404/stats | http://10.15.15.10:8404/stats · http://10.15.15.11:8404/stats |

Secrets (all in `.secrets/`, never in git):

```bash
laptop$ cat .secrets/mysql-app-a            # MySQL password of user app (Site A)
laptop$ cat .secrets/vm_console_password    # console login of user infra (virsh console)
laptop$ cat .secrets/ipsec-psk              # IPsec pre-shared key
laptop$ ls .secrets/opnsense/               # OPNsense config backups
```

## 5. Monitoring

### The whole site at a glance

```bash
laptop$ make status SITE=a
#  Site A — mode distributed
#  VMs:      a-opnsense=running, a-haproxy1=running, ...
#  VIP 10.0.2.100: a-haproxy1
#  Web via VIP:  OK, served by a-haproxy1
#  Web via WAN 192.168.100.11: OK, served by a-haproxy1
#  Tunnel to Site B 10.15.15.7: UP, no NAT (peer sees 10.0.2.7)
```

### Layer by layer

**Hypervisor (laptop)**

```bash
laptop$ virsh -c qemu:///system list --all              # VM states
laptop$ virsh -c qemu:///system net-list --all          # virtual networks
laptop$ virsh -c qemu:///system domstats --cpu-total --balloon a-web   # CPU / memory of a VM
laptop$ free -h                                         # RAM left on the laptop
laptop$ ip -br addr | grep virbr-i                      # the lab bridges and the laptop's addresses
laptop$ bridge link show                                # which VM cards are plugged into which bridge
```

**Web server (a-web)**

```bash
vm$ systemctl status nginx php8.3-fpm --no-pager
vm$ sudo tail -f /var/log/nginx/access.log              # every request (client = HAProxy node)
vm$ sudo tail -f /var/log/nginx/error.log
vm$ curl -s http://10.0.2.7/health                      # OK
vm$ curl -s http://10.0.2.7/whoami                      # the caller's address
```

**Database (a-db)**

```bash
vm$ systemctl status mysql --no-pager
vm$ ss -ltn 'sport = :3306'                             # listening on 10.0.2.8 only
vm$ sudo mysql -e "SHOW PROCESSLIST; SELECT * FROM infra.page_views;"
vm$ sudo mysql -e "SELECT user, host FROM mysql.user WHERE user='app';"
vm$ sudo tail -f /var/log/mysql/error.log
```

**Proxies and VIP (a-haproxy1 / a-haproxy2)**

```bash
vm$ ip -br addr show lan0                               # the VIP appears on the MASTER only
vm$ systemctl status haproxy keepalived --no-pager
vm$ sudo journalctl -u keepalived -f                    # "Entering MASTER STATE" / "BACKUP STATE"
vm$ sudo journalctl -u haproxy -f                       # one line per request + health check changes
vm$ sudo tcpdump -ni lan0 vrrp                          # VRRP adverts, one per second from the MASTER
laptop$ curl -s 'http://10.0.2.5:8404/stats;csv' | cut -d, -f1,2,18 | column -ts,   # backend UP/DOWN
```

Watch the VIP and the page live (two terminals, good for the demo):

```bash
laptop$ watch -n1 "for h in 10.0.2.5 10.0.2.6; do echo -n \"\$h: \"; ssh -i .secrets/infra_ed25519 -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null infra@\$h 'ip -4 -br addr show lan0'; done"
laptop$ while true; do curl -s -m 2 http://10.0.2.100/ | grep -o 'id="proxy">[^<]*' || echo DOWN; sleep 1; done
```

**OPNsense (GUI)**

| Page | What you see |
|---|---|
| **Lobby → Dashboard** | CPU, memory, interfaces, gateways at a glance |
| **Interfaces → Overview** | addresses and state of WAN and LAN |
| **System → Gateways → Configuration** | `WAN_GW` online/offline |
| **Firewall → Log Files → Live View** | every passed/blocked packet, live (filter on port 3306 or 80) |
| **Firewall → NAT → Destination NAT** | the 80/443 → VIP forwards |
| **VPN → IPsec → Status Overview** | Phase 1 / Phase 2 state, bytes in/out |
| **VPN → IPsec → Log File** | IKE negotiation messages (`NO_PROPOSAL_CHOSEN`, `AUTHENTICATION_FAILED`...) |
| **Interfaces → Diagnostics → Ping / Packet Capture** | test and capture from the firewall itself |

**OPNsense (shell)**

```bash
opnsense# swanctl --list-sas            # IKE SA + CHILD SA: ESTABLISHED / INSTALLED, bytes, SPIs
opnsense# swanctl --list-conns          # configured connections and their proposals
opnsense# pfctl -s nat                  # NAT rules in force (the 80/443 rdr to the VIP)
opnsense# pfctl -s rules | less         # filter rules in force
opnsense# pfctl -s states | grep 3306   # active connections to a port
opnsense# tcpdump -ni vtnet1 esp        # ESP packets on the WAN (encrypted)
opnsense# tcpdump -ni enc0              # the same traffic *before encryption / after decryption*
```

**The IPsec tunnel from the laptop (lab mode)**

```bash
laptop$ sudo tcpdump -ni virbr-iwan esp or udp port 500 or udp port 4500   # only firewall-to-firewall, encrypted
laptop$ sudo tcpdump -ni virbr-ib icmp                                     # clear text inside Site B's LAN
vm$ ping 10.15.15.7                      # from a-web, to generate traffic
vm$ curl -s http://10.15.15.7/whoami     # 10.0.2.7 = no NAT between the LANs
vm$ tracepath -n 10.15.15.7              # 1: 10.0.2.1, then 10.15.15.7
```

## 6. Tests

```bash
laptop$ make test-phase1 SITE=a      # addressing + LAN ping mesh
laptop$ make test-phase2 SITE=a      # Internet + DNS through OPNsense, GUI closed on WAN, no leak between sites
laptop$ make test-phase3 SITE=a      # page shows MySQL data, app user only from the web VM
laptop$ make test-phase4 SITE=a      # REAL failover: stops keepalived then haproxy on the MASTER, restores them
laptop$ make test-phase5 SITE=a      # from the WAN: page OK, 3306/22/8404 blocked, failover through the WAN
laptop$ make test-phase6 SITE=a      # tunnel up, ping the other site, no NAT
laptop$ make acceptance SITE=a       # the six spec tests -> deliverables/site_a/acceptance-report.md
```

## 7. Deliverables and backups

```bash
laptop$ make opnsense-backup SITE=a     # .secrets/opnsense/a-opnsense-config.xml (needs SSH on OPNsense)
laptop$ make deliverables SITE=a        # keepalived.conf, haproxy.cfg, redacted OPNsense XML, addressing plan
laptop$ rsvg-convert -w 2240 deliverables/network-diagram.svg -o deliverables/network-diagram.png
```

## 8. Repair, rebuild, remove

```bash
laptop$ make opnsense-rebuild SITE=a                  # firewall no longer boots (after a hard power-off)
                                                      # then GUI: System -> Configuration -> Backups -> Restore
laptop$ virsh -c qemu:///system console a-web         # "screen" of a VM (login infra / .secrets/vm_console_password; exit Ctrl + ])
laptop$ virsh -c qemu:///system console a-opnsense    # OPNsense console menu
laptop$ virsh -c qemu:///system shutdown a-web        # clean stop of one VM (never "destroy" OPNsense)
laptop$ make phase3 SITE=a ARGS="--check --diff"      # what Ansible WOULD change, without changing it
laptop$ make destroy SITE=a                           # delete the site's VMs, disks and LAN (keeps the images)
laptop$ make destroy SITE=a ARGS="-e destroy_wan=true"   # ... and the shared WAN network
laptop$ make all SITE=a                               # rebuild everything automatic
```

## 9. Git and sharing

```bash
laptop$ git status                      # .secrets/ .cache/ .venv/ never appear (git-ignored)
laptop$ git add -A && git commit -m "..."
laptop$ git push
laptop$ git bundle create infra.bundle --all   # the whole repository as one file (USB stick)
other$  git clone infra.bundle infra
```

## 10. What we actually ran to build this (history)

The real sequence on Student 1's computer, both sites in lab mode:

```bash
# 2026-10-24 — setup
sudo ./scripts/bootstrap-host.sh
make setup

# 2026-10-25 — Phase 1, both sites
make phase1 SITE=a && make test-phase1 SITE=a
make phase1 SITE=b MODE=lab && make test-phase1 SITE=b MODE=lab
make phase1 SITE=a                       # second run: changed=0 (idempotent)

# 2026-10-26 — Phase 2 (OPNsense VM + console bootstrap)
make phase2 SITE=a && make test-phase2 SITE=a
make phase2 SITE=b MODE=lab && make test-phase2 SITE=b MODE=lab

# 2026-10-30 — the firewalls no longer booted after the laptop was switched off
virsh -c qemu:///system dominfo a-opnsense                              # CPU busy...
virsh -c qemu:///system console a-opnsense --force                      # ...but no output at all
virsh -c qemu:///system qemu-monitor-command a-opnsense --hmp 'info registers'   # stuck in the first boot stage
make opnsense-rebuild SITE=a && make test-phase2 SITE=a
make opnsense-rebuild SITE=b MODE=lab && make up SITE=b MODE=lab && make test-phase2 SITE=b MODE=lab

# 2026-10-30 — Phases 3 and 4, both sites
make phase3 SITE=a && make test-phase3 SITE=a
make phase4 SITE=a && make test-phase4 SITE=a
make phase3 SITE=b MODE=lab && make phase4 SITE=b MODE=lab
make test-phase3 SITE=b MODE=lab && make test-phase4 SITE=b MODE=lab

# 2026-10-30 — WAN filter (closes the A<->B path outside the tunnel), deliverables, acceptance
make phase2 SITE=a && make phase2 SITE=b MODE=lab
make test-phase2 SITE=a && make test-phase2 SITE=b MODE=lab
make deliverables SITE=a && make deliverables SITE=b MODE=lab
make acceptance SITE=a && make acceptance SITE=b MODE=lab   # 3 and 4 PASS; the rest waits for the GUI steps
```
