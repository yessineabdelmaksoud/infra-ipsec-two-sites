# Infrastructure IT — two sites joined by an IPsec VPN, built as code

Two equivalent IT sites, each with a public web service backed by MySQL and a
highly available proxy layer, whose private LANs are joined by an **IPsec
site-to-site VPN (IKEv2, ESP, tunnel mode)** between two **OPNsense** firewalls.
Everything runs as virtual machines on KVM/libvirt and is built and tested with
**Ansible** — one repository, one command per phase.

![Network diagram](deliverables/network-diagram.svg)

| | |
|---|---|
| **Specification** | [INFRASTRUCTURE_IT_PROJECT.md](INFRASTRUCTURE_IT_PROJECT.md) (summary of the course PDF) |
| **Learning docs** (every phase explained simply) | [docs/](docs/README.md) |
| **Plan, decisions, progress log** | [PLAN.md](PLAN.md) |
| **Deliverables** (diagram, addressing plan, configs, acceptance reports) | [deliverables/](deliverables/README.md) |
| **Defense checklist and demo script** | [docs/07-acceptance-and-defense.md](docs/07-acceptance-and-defense.md) |

## What each site contains

| Machine | Site A | Site B | Role |
|---|---|---|---|
| OPNsense | `10.0.2.1` / WAN `192.168.100.11` | `10.15.15.1` / WAN `192.168.100.12` | router, firewall, NAT 80/443 → VIP, IPsec endpoint |
| VIP (Keepalived) | `10.0.2.100` | `10.15.15.100` | the address the public traffic goes to |
| HAProxy 1 — MASTER | `10.0.2.5` | `10.15.15.10` | reverse proxy, owns the VIP |
| HAProxy 2 — BACKUP | `10.0.2.6` | `10.15.15.11` | takes the VIP if the MASTER fails |
| Web | `10.0.2.7` | `10.15.15.7` | Nginx + PHP page reading MySQL |
| MySQL | `10.0.2.8` | `10.15.15.8` | database, only reachable by the web server |

Full plan: [deliverables/addressing-plan.md](deliverables/addressing-plan.md).

## Status

| Phase (spec stage) | How | Test | Status |
|---|---|---|---|
| 1. Networks and VMs | automatic | `make test-phase1` | ✅ A and B |
| 2. OPNsense | automatic VM + console, then **web UI** ([guide](docs/02-phase2-opnsense.md)) | `make test-phase2` | ✅ automatic part, A and B · ⏳ GUI steps |
| 3. Web + MySQL | automatic | `make test-phase3` | ✅ A and B |
| 4. Keepalived + HAProxy | automatic | `make test-phase4` (real failover) | ✅ A and B — VIP moves in ~1 s |
| 5. NAT + firewall | **web UI** ([guide](docs/05-phase5-nat-firewall.md)) | `make test-phase5` | ⏳ GUI steps |
| 6. IPsec tunnel | **web UI**, both students ([guide](docs/06-phase6-ipsec.md)) | `make test-phase6` | ⏳ GUI steps |
| Acceptance (6 tests) | — | `make acceptance` → report | 3 and 4 pass; 1, 2, 5, 6 wait for phases 5–6 |

*A and B* = tested with both sites on one computer (`MODE=lab`). The OPNsense
settings are done by hand in the GUI on purpose (to learn the interface), saved
with `make opnsense-backup` and checked by the automated tests.

## Quick start

Each student uses the **same repository** on their own computer:
Student 1 runs `SITE=a`, Student 2 runs `SITE=b`.

```bash
sudo ./scripts/bootstrap-host.sh    # once per computer: KVM/libvirt, groups, Docker coexistence
make setup                          # pinned Ansible in .venv + lab SSH key (no sudo)
make all SITE=a                     # phases 1-4: networks, VMs, OPNsense VM, web, MySQL, HAProxy, Keepalived
#   then the OPNsense web UI: docs/02 (wizard), docs/05 (NAT + rules), docs/06 (IPsec)
make opnsense-backup SITE=a         # save the firewall config (after enabling SSH in the GUI)
make acceptance SITE=a              # the six spec tests -> deliverables/site_a/acceptance-report.md
make deliverables SITE=a            # keepalived.conf, haproxy.cfg, redacted OPNsense XML
```

- Both sites on **one computer** (rehearsal / fallback demo): add `MODE=lab` to every Site B command.
- **Two computers**: Ethernet cable between them, then `sudo ./scripts/wan-link.sh <iface>` on both ([docs/06](docs/06-phase6-ipsec.md), step 0).
- Daily use: `make up SITE=a` after a reboot, **`make down SITE=a` before switching off** ([why](docs/08-troubleshooting.md)).
- All targets: `make help`. Extra Ansible options: `ARGS="-v"`.

Requirements per computer: x86-64 Linux with KVM (tested on Ubuntu 26.04), ≥ 8 GiB RAM
for one site (≈ 4.3 GiB used), ≥ 16 GiB for both sites, ≥ 25 GB disk, `sudo` once.

## Repository layout

```text
Makefile                     the buttons: make <target> SITE=a|b [MODE=lab]
ansible.cfg, requirements.txt pinned toolchain (Ansible 14.5.0 / core 2.21.5)
inventories/common/          shared by both sites: addressing plan, IPsec values, VM sizes, image pins
inventories/site_a|site_b/   the machines of each site
playbooks/                   one playbook per phase + power, deliverables, destroy
roles/                       hypervisor, libvirt_network, libvirt_vm, opnsense_vm,
                             base, mysql, webapp, haproxy, keepalived
tests/                       one test per phase + acceptance.yml (the six spec tests)
scripts/                     host bootstrap, OPNsense console bootstrap, WAN cable link, XML redaction
docs/                        learning docs, defense guide, report template
deliverables/                diagram, addressing plan, configs and reports per site
.secrets/ .cache/ .venv/     local only, never in git (keys, passwords, PSK, images)
```

## Security notes

- No secret is in git: SSH key, MySQL/VRRP passwords, IPsec PSK and TLS key are
  generated into `.secrets/` (git-ignored). The IPsec PSK is exchanged between the
  students out of band (USB stick / `scp`).
- Published configs are redacted (`REDACTED` in place of password hashes, private
  keys, PSK, VRRP password).
- The OPNsense GUI and SSH listen on the LAN only; from the WAN only TCP 80/443
  (to the VIP) and IPsec from the peer firewall are allowed.

## Limits (honest)

- High availability covers the **proxy layer** only (spec §10): one web server,
  one MySQL and one OPNsense per site.
- HTTPS uses a self-signed certificate; the "Internet" is a simulated private segment.
- The two-computer cable setup (`scripts/wan-link.sh`) is written but was only
  rehearsed with both sites on one computer so far.
