# Learning docs — how this project is built, phase by phase

These pages explain **what we built, why, and how**, in simple words.
Each page has: the goal, a picture, the commands to run, pieces of the real code
with explanations, how to check by hand, and the problems we hit.

| Page | What you learn | Who does what |
|---|---|---|
| [00 — Setup of the computer](00-setup.md) | Install the tools once (KVM, libvirt, Ansible) | automatic (`sudo` once) |
| [01 — Phase 1: networks and VMs](01-phase1-networks-vms.md) | Virtual networks, virtual machines, cloud-init, Ansible basics | automatic |
| [02 — Phase 2: OPNsense](02-phase2-opnsense.md) | The firewall/router: console setup + **web interface step by step** | automatic + **you, in the GUI** |
| [03 — Phase 3: web + MySQL](03-phase3-web-mysql.md) | Nginx, PHP, MySQL users bound to an address, least privilege | automatic |
| [04 — Phase 4: Keepalived + HAProxy](04-phase4-haproxy-keepalived.md) | VIP, VRRP, health checks, failover demo | automatic |
| [05 — Phase 5: NAT + firewall](05-phase5-nat-firewall.md) | Destination NAT, WAN rules, default deny, logging | **you, in the GUI** + automatic test |
| [06 — Phase 6: IPsec](06-phase6-ipsec.md) | IKEv2, ESP, tunnel mode, PSK, PFS, mirrored settings | **both students, in the GUI** + automatic test |
| [07 — Acceptance tests and the defense](07-acceptance-and-defense.md) | The six tests, deliverables, 15-minute demo script, likely questions | automatic report + live demo |
| [08 — Troubleshooting and daily use](08-troubleshooting.md) | `make up/down`, OPNsense recovery, known pitfalls | |
| [Report template](report-template.md) | Skeleton of the written report | |

The plan, the decisions and the progress log are in [../PLAN.md](../PLAN.md).

---

## The big idea: "Infrastructure as Code" (IaC)

Instead of clicking around to create machines, we **write files that describe
the machines**, and a tool creates them. Advantages:

- **Repeatable**: Student 2 runs the same command on their computer and gets the same site.
- **Reviewable**: the setup is in git; you can see what changed and when.
- **Rebuildable**: break something? `make destroy` then `make all` and it's back.
- **Testable**: every phase has a test playbook that checks the spec's requirement.

One rule we follow: **the shared code is the same for both sites**; only a small
file per site is different (`inventories/site_a` vs `inventories/site_b`).

The one exception is the **OPNsense configuration** (Phases 2, 5, 6): we chose to
do it **in the web interface**, to learn it, and to save the result as
`config.xml` (`make opnsense-backup`). The tests still check it automatically.

## Mini dictionary

| Word | Simple meaning |
|---|---|
| **VM** (virtual machine) | A fake computer running inside your real computer |
| **Hypervisor** | The software that runs VMs. Here: **KVM** (in the Linux kernel) + **QEMU** (emulates the hardware) |
| **libvirt** / `virsh` | A manager on top of KVM/QEMU. `virsh` is its command line: `virsh list`, `virsh start`, ... |
| **Virtual network / bridge** | A fake network switch inside your computer. VMs plug their virtual cable into it |
| **NAT** | Rewriting addresses: many private addresses share one public one (*source NAT*), or a public port is sent to a private machine (*destination NAT*) |
| **Isolated network** | A virtual switch with no exit: machines on it only talk to each other |
| **Subnet `/24`** | `10.0.2.0/24` means addresses `10.0.2.0` → `10.0.2.255`; the first 3 numbers are the network |
| **Gateway** | The machine you send packets to when the destination is not on your subnet (here: OPNsense `.1`) |
| **cloud-init** | A program inside the VM image that configures it at first boot (name, IP, user, SSH key) |
| **qcow2 / overlay** | Disk file format. An *overlay* stores only the differences from a shared base image → saves disk space |
| **Ansible** | The IaC tool: reads *playbooks* (YAML lists of tasks) and applies them to machines |
| **Inventory** | Ansible's list of machines and their variables |
| **Role** | A reusable folder of Ansible tasks (like a function) |
| **Idempotent** | Running it twice gives the same result; the 2nd run changes nothing (`changed=0`) |
| **OPNsense** | Open-source firewall/router (FreeBSD). One per site: Internet access, NAT, VPN |
| **VIP** (virtual IP) | An IP address that moves between two machines (Phase 4) |
| **VRRP / Keepalived** | The protocol / program that decides which node holds the VIP |
| **HAProxy** | Reverse proxy: receives the web requests on the VIP and forwards them to the web server |
| **IPsec** | Encrypted tunnel between the two sites' firewalls (Phase 6) |
| **IKE / ESP / SA** | IPsec's negotiation protocol / its encrypted-data protocol / one agreed set of keys |

## Command cheat sheet

```bash
make help                          # list all targets
make all SITE=a                    # build phases 1-4 of Site A (automatic parts)
make test-phase3 SITE=a            # check one phase
make acceptance SITE=a             # the six spec tests + report
make up SITE=a / make down SITE=a  # start / cleanly stop the site's VMs
make phase1 SITE=b MODE=lab        # Site B on the same computer (rehearsal)

virsh -c qemu:///system list --all          # which VMs exist / run
virsh -c qemu:///system net-list --all      # which virtual networks exist
virsh -c qemu:///system console a-web       # "plug a screen" into a VM (exit: Ctrl + ])
ssh -i .secrets/infra_ed25519 infra@10.0.2.7    # log into a VM
```

> If `virsh` says *permission denied* in a terminal opened before the bootstrap,
> log out/in once, or prefix commands with `sg libvirt -c "..."`.
