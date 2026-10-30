# Report template — Infrastructure IT: VPN & site-to-site interconnection

Copy this file into your report tool (Word, Google Docs, LaTeX) and fill the
`[...]` parts. Screenshots go where 📷 is written.

---

**Students:** [Student 1 — Site A], [Student 2 — Site B]
**Date:** [...]
**Repository:** [link to the git repository]

## 1. Objective

Build two equivalent IT sites, each with a public web service backed by MySQL
and protected by a highly available proxy layer, and interconnect their private
LANs with an IPsec IKEv2 / ESP tunnel-mode VPN between two OPNsense firewalls.

## 2. Architecture

📷 / insert [deliverables/network-diagram.svg](../deliverables/network-diagram.svg)

- Per site: 1 OPNsense (WAN + LAN), 2 HAProxy + Keepalived nodes (MASTER/BACKUP, VIP), 1 Nginx + PHP web server, 1 MySQL server.
- Public flow: client → OPNsense WAN (destination NAT 80/443) → VIP → HAProxy → Nginx → MySQL.
- Inter-site flow: LAN → OPNsense → IPsec tunnel → peer OPNsense → peer LAN, without NAT.
- Everything except the OPNsense GUI settings is built by code (Ansible + libvirt/KVM): `make all SITE=a`.

## 3. Addressing plan

Insert [deliverables/addressing-plan.md](../deliverables/addressing-plan.md).

## 4. Implementation, stage by stage

For each stage: what we did (2–3 sentences), the stage test, one screenshot.

| Stage | Done by | Test | Result |
|---|---|---|---|
| 1. Networks and VMs | [...] | VMs ping each other (`make test-phase1`) | 📷 |
| 2. OPNsense | [...] | VMs reach the Internet through OPNsense (`make test-phase2`) | 📷 |
| 3. Web + MySQL | [...] | page shows MySQL data (`make test-phase3`) | 📷 |
| 4. Keepalived + HAProxy | [...] | VIP moves to BACKUP (`make test-phase4`) | 📷 |
| 5. NAT + firewall | [...] | page via WAN IP, 3306 blocked (`make test-phase5`) | 📷 |
| 6. IPsec | both | ping 10.0.2.7 → 10.15.15.7 (`make test-phase6`) | 📷 |

## 5. IPsec configuration

| Phase | Setting | Value |
|---|---|---|
| 1 | IKE version, authentication | IKEv2, pre-shared key |
| 1 | Encryption / integrity / DH | AES-256 / SHA-256 / group 14 |
| 1 | Lifetime | 28 800 s |
| 2 | Mode, protocol | tunnel, ESP |
| 2 | Encryption / PFS | AES-256-GCM / DH group 14 |
| 2 | Lifetime | 3 600 s |
| 2 | Networks | 10.0.2.0/24 ⇄ 10.15.15.0/24 |
| WAN rules | | UDP 500, UDP 4500, ESP from the peer WAN only |

📷 OPNsense A — VPN → IPsec → Connections (the connection and its child)
📷 OPNsense B — same page

## 6. Acceptance tests

Use `deliverables/site_a/acceptance-report.md` and `site_b/…` (from `make acceptance`).

| # | Test | Expected | Result | Screenshot |
|---|---|---|---|---|
| 1 | Public web access — `http://<WAN IP>` | page served | [PASS] | 📷 |
| 2 | HA — `systemctl stop keepalived` on MASTER | VIP on BACKUP, site up | [PASS] | 📷 📷 |
| 3 | Database — `mysql -h 10.0.2.8 -u app -p` | login OK | [PASS] | 📷 |
| 4 | Database isolation — TCP 3306 from WAN | blocked | [PASS] | 📷 |
| 5 | IPsec — Status Overview | phase 1 + 2 established | [PASS] | 📷 |
| 6 | Inter-site — `ping 10.15.15.7` from `10.0.2.7` | replies, no NAT | [PASS] | 📷 |

## 7. Problems met and solutions

Pick the ones you met (details in docs/01–08):

- AppArmor blocked libvirt hooks and pool volumes (Ubuntu 26.04) → helper path and file-based disks.
- Docker's FORWARD DROP policy broke VM forwarding → libvirt hook + systemd unit.
- Ubuntu automatic updates held the apt lock → role `base`.
- nginx kept its old config after a reload (`bind()` error) → `listen 80`.
- OPNsense nano image unbootable after a hard power-off → clean shutdowns, `make opnsense-rebuild`, config backups.
- On one computer, the hypervisor routed between the LANs outside the tunnel → libvirt network filter on the OPNsense WAN.
- [your own: e.g. `NO_PROPOSAL_CHOSEN` because ...]

## 8. Limits

- High availability covers the proxy layer only; the web server, MySQL and OPNsense are single per site.
- Self-signed certificate on HTTPS (lab).
- The WAN is a simulated Internet (`192.168.100.0/24`, private addresses).

## 9. Conclusion

[What works, what you learned, what you would add: a second web server, MySQL replication, OPNsense CARP, certificates instead of PSK.]

## Appendix — deliverables

- OPNsense XML exports (redacted): `deliverables/site_a/a-opnsense-config.redacted.xml`, `deliverables/site_b/b-opnsense-config.redacted.xml`
- `keepalived.conf` and `haproxy.cfg`: `deliverables/site_{a,b}/<node>/`
