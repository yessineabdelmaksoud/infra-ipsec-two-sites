# Next steps — what is still to do (handoff for both students)

State on 2026-10-30: everything that can be automated is built and tested,
with both sites on **one** computer (Student 1's). What is left: the OPNsense
web-interface steps, the two-computer setup, the final tests and the report.

- **Student 1** = Site A = `SITE=a` (the computer where this was built)
- **Student 2** = Site B = `SITE=b` (the friend's computer)

Tick the boxes as you go. Every step links to the page that explains it.
**Before you start**, read [docs/LEARNING-GUIDE.md](docs/LEARNING-GUIDE.md) (30–45 min)
so you understand what each command does.

---

## Part 1 — Student 1 (Site A), on your computer

- [ ] **Re-run the bootstrap once** (adds the "shut VMs down cleanly" setting):
  `sudo ./scripts/bootstrap-host.sh`
- [ ] **Give the repository to Student 2.** There is no GitHub remote yet. Either
  - create a **private** GitHub repository, then `git remote add origin <url>` and `git push -u origin master`, or
  - make one file and send it (USB/cable): `git bundle create infra.bundle --all`
    → Student 2 runs `git clone infra.bundle infra`.

  Secrets are **not** in git (`.secrets/` is ignored): Student 2 generates their own.
- [ ] **Start your site** (if the VMs are off): `make up SITE=a`
- [ ] **Phase 2, web UI** — [docs/02](docs/02-phase2-opnsense.md) Part B, steps 0–7 on `https://10.0.2.1`
  (factory login `root` / `opnsense`). Don't forget:
  - WAN gateway **192.168.100.1** typed in
  - **uncheck** *Block private networks* and *Block bogon networks*
  - GUI + SSH listen on **LAN** only, root key = `cat .secrets/infra_ed25519.pub`
- [ ] `make opnsense-backup SITE=a` then `make test-phase2 SITE=a`
- [ ] **Phase 5, web UI** — [docs/05](docs/05-phase5-nat-firewall.md): Destination NAT 80 and 443 → `10.0.2.100`, logged rules
- [ ] `make test-phase5 SITE=a` then `make opnsense-backup SITE=a`
- [ ] **IPsec key**: `make ipsec-psk` → give the file `.secrets/ipsec-psk` to Student 2
  (USB stick, or `scp` over the cable — **never** email, chat or git)

## Part 2 — Student 2 (Site B), on the friend's computer

Needs: x86-64 Linux with KVM (Ubuntu recommended), ≥ 8 GiB RAM, ≥ 25 GB free disk, `sudo`.
Check KVM: `ls /dev/kvm` must exist (enable VT-x/AMD-V in the BIOS otherwise).

- [ ] Get the repository (Part 1) and `cd` into it
- [ ] **Read** [docs/00-setup.md](docs/00-setup.md) and [docs/01](docs/01-phase1-networks-vms.md), then:
  ```bash
  sudo ./scripts/bootstrap-host.sh      # once; then log out and in again
  make setup                            # Ansible + SSH key, no sudo
  make all SITE=b                       # phases 1-4 (~15 min, downloads ~1 GB)
  make test-phase1 SITE=b
  make test-phase3 SITE=b
  make test-phase4 SITE=b
  ```
  **No `MODE=lab` here**: on your own computer the default mode is right (your WAN gateway is `192.168.100.2`).
- [ ] **Phase 2, web UI** — [docs/02](docs/02-phase2-opnsense.md) Part B on `https://10.15.15.1`, with the **Site B column**:
  hostname `fw-b`, domain `site-b.lab`, WAN `192.168.100.12/24`, **gateway `192.168.100.2`**, LAN `10.15.15.1/24`
- [ ] `make opnsense-backup SITE=b` then `make test-phase2 SITE=b`
- [ ] **Phase 5, web UI** — [docs/05](docs/05-phase5-nat-firewall.md) with VIP `10.15.15.100`
- [ ] `make test-phase5 SITE=b` then `make opnsense-backup SITE=b`
- [ ] Put the PSK file from Student 1 at `.secrets/ipsec-psk` (`chmod 600 .secrets/ipsec-psk`)

## Part 3 — together: the cable and the tunnel

- [ ] Connect the two computers with an **Ethernet cable** (campus Wi-Fi blocks traffic between laptops)
- [ ] On **both** computers (find your port with `ip -br link`, e.g. `enp3s0`):
  ```bash
  sudo ./scripts/wan-link.sh enp3s0
  ```
- [ ] Check the WAN link: from Site A's computer `ping 192.168.100.2` and `ping 192.168.100.12`;
  from Site B's `ping 192.168.100.1` and `ping 192.168.100.11`
- [ ] **Phase 6, web UI, both** — [docs/06](docs/06-phase6-ipsec.md): pre-shared key → connection → child →
  WAN rules (UDP 500, UDP 4500, ESP from the **peer's** WAN only) → IPsec rules. Same values, **mirrored**.
- [ ] Status Overview shows Phase 1 ESTABLISHED + Phase 2 INSTALLED on both
- [ ] `make test-phase6 SITE=a` (Student 1) and `make test-phase6 SITE=b` (Student 2)
- [ ] `make opnsense-backup` on both

> ⚠️ This cable setup is the **only part not tested yet**. If it fails, the fallback
> for the defense is both sites on Student 1's computer (`MODE=lab` for Site B),
> where the tunnel works the same way. See [docs/08](docs/08-troubleshooting.md).

## Part 4 — both: final tests, deliverables, report

- [ ] `make acceptance SITE=a` / `SITE=b` → all six **PASS** in `deliverables/site_<x>/acceptance-report.md`
  (test 5 says PASS when SSH to OPNsense works, otherwise MANUAL = screenshot)
- [ ] `make deliverables SITE=a` / `SITE=b` → configs + redacted OPNsense XML
- [ ] Take the six screenshots listed at the bottom of each acceptance report
- [ ] Commit `deliverables/` (Student 2 sends their `deliverables/site_b/` to Student 1, or pushes it)
- [ ] Write the report from [docs/report-template.md](docs/report-template.md)
- [ ] Rehearse the 15-minute demo: [docs/07](docs/07-acceptance-and-defense.md) section 4, and the questions in section 5

## Rules that save you hours

- **`make down SITE=x` before switching the computer off.** A killed OPNsense VM may never boot again
  ([why](docs/08-troubleshooting.md)). If it happens: `make opnsense-rebuild SITE=x` + restore the backup.
- **`make opnsense-backup` after every GUI session.**
- When a test fails, read its message, then the "If something goes wrong" table at the end of the phase's doc.
- Never commit `.secrets/` and never paste passwords or the PSK in chats.
