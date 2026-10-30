# 07 — Acceptance tests, deliverables and the final defense

This page is the **checklist for the last day**: the six mandatory tests (spec §7),
how to collect the deliverables (spec §8), and a script for the live demo.

## 1. Run all six tests automatically

```bash
make acceptance SITE=a                 # Student 1 (Student 2: SITE=b)
cat deliverables/site_a/acceptance-report.md
```

[tests/acceptance.yml](../tests/acceptance.yml) runs the six tests **in the
spec's order**, continues even if one fails, and writes a report with a
PASS / FAIL / MANUAL table, the evidence for each test, and the list of
screenshots to take. Example (Site A, after Phases 1–4, before the Phase 5/6 UI steps):

| # | Test | Result | Evidence |
|---|---|---|---|
| 1 | Public web access | FAIL | timed out (no destination NAT yet → docs/05) |
| 2 | High availability | FAIL | same: tested **through the WAN address** |
| 3 | Database | PASS | login OK as app@10.0.2.7 on a-db, 3 messages |
| 4 | Database isolation | PASS | 192.168.100.11:3306 does not answer |
| 5 | IPsec negotiation | MANUAL | no SSH to OPNsense: check the Status Overview |
| 6 | Inter-site connectivity | FAIL | no tunnel yet → docs/06 |

When everything is configured, all six say **PASS** (5 says PASS when SSH to
OPNsense is enabled — Phase 2 steps 4–5 — otherwise MANUAL: take the screenshot).

## 2. The six tests by hand (for screenshots and the live demo)

Site A values. Site B: replace `192.168.100.11 → .12`, `10.0.2.x → 10.15.15.x`,
`haproxy1 = 10.15.15.10`, `haproxy2 = 10.15.15.11`.

| # | Spec test | Command / action | What to show |
|---|---|---|---|
| 1 | Public web access | Browser: **http://192.168.100.11/** | The Site A page with the MySQL rows and "HAProxy node a-haproxy1" |
| 2 | High availability | `ssh -i .secrets/infra_ed25519 infra@10.0.2.5 'sudo systemctl stop keepalived'` then reload the page | The page now says **a-haproxy2**; `ssh ... infra@10.0.2.6 'ip -br addr show lan0'` shows `10.0.2.100`. Then `sudo systemctl start keepalived` on .5 |
| 3 | Database | `ssh -i .secrets/infra_ed25519 infra@10.0.2.7` then `mysql -h 10.0.2.8 -u app -p` (password: `cat .secrets/mysql-app-a`) | The `mysql>` prompt; `SELECT * FROM infra.messages;` |
| 4 | Database isolation | `nc -zv -w 5 192.168.100.11 3306` from your computer | `timed out` + the red *block* line in **Firewall → Log Files → Live View** |
| 5 | IPsec negotiation | GUI: **VPN → IPsec → Status Overview** | Phase 1 ESTABLISHED, Phase 2 INSTALLED `10.0.2.0/24 === 10.15.15.0/24` |
| 6 | Inter-site connectivity | On a-web: `ping -c 4 10.15.15.7` and `curl http://10.15.15.7/whoami` | Replies, and `whoami` prints **10.0.2.7** = no NAT |

## 3. Deliverables (spec §8)

```bash
make opnsense-backup SITE=a            # needs SSH enabled on OPNsense (docs/02 steps 4-5)
make deliverables SITE=a
```

| # | Deliverable | Where |
|---|---|---|
| 1 | Updated network diagram | [deliverables/network-diagram.svg](../deliverables/network-diagram.svg) |
| 2 | Final addressing plan | [deliverables/addressing-plan.md](../deliverables/addressing-plan.md) (generated from the inventory) |
| 3 | XML export of each OPNsense | `deliverables/site_a/a-opnsense-config.redacted.xml` (+ `site_b/`) |
| 4 | `keepalived.conf`, `haproxy.cfg` | `deliverables/site_a/a-haproxy1/`, `a-haproxy2/` (+ `site_b/`) |
| 5 | Report with screenshots of the six tests | your report, using `deliverables/site_*/acceptance-report.md` and [report-template.md](report-template.md) |

> **Secrets.** The OPNsense XML in `deliverables/` is **redacted** by
> [scripts/redact_opnsense_xml.py](../scripts/redact_opnsense_xml.py): password
> hashes, private keys and the IPsec PSK become `REDACTED`. The VRRP password in
> `keepalived.conf` too. The real files stay in `.secrets/` (never in git). If the
> teacher wants the raw XML, give it on a USB stick, not in the repository.

Student 2 runs the same two commands with `SITE=b`. Commit both `site_a/` and
`site_b/` folders to the shared repository.

## 4. The live defense — a 15-minute script

**Before the defense (the evening before):**

- [ ] Both computers: `make up SITE=a` / `make up SITE=b`, then `make acceptance` → all PASS (5 may be MANUAL).
- [ ] Ethernet cable tested: `sudo ./scripts/wan-link.sh <iface>` on both, tunnel comes up.
- [ ] Backup plan: the whole project also runs **on one computer** (`MODE=lab` for Site B). Rehearse it once.
- [ ] Browser tabs ready: `https://10.0.2.1` (OPNsense GUI), `http://192.168.100.11/`, `http://10.0.2.5:8404/stats`.
- [ ] Shut down with `make down` — never pull the plug with VMs running (see [08-troubleshooting](08-troubleshooting.md)).

**At the defense:**

| Min | Who | What to show | Say |
|---|---|---|---|
| 0–2 | both | [network diagram](../deliverables/network-diagram.svg), addressing plan | "Two equivalent sites, two private LANs, one IPsec tunnel between two OPNsense firewalls." |
| 2–4 | Student 1 | `git` repo, `make help`, `inventories/common/group_vars/all.yml` | "Everything is code: same repository on both computers, only `SITE=a/b` changes." |
| 4–5 | Student 1 | **Test 1**: browser on `http://192.168.100.11/` | "Client → WAN NAT → VIP → HAProxy → Nginx → MySQL. The counter is a live UPDATE in MySQL." |
| 5–7 | Student 1 | **Test 2**: curl loop + `systemctl stop keepalived` (docs/04 "the demo") | "The VIP moved in about a second; the visitor does not notice." |
| 7–8 | Student 2 | **Test 3**: `mysql -h 10.15.15.8 -u app -p` on b-web | "The `app` user only exists for the web server's address." |
| 8–9 | Student 2 | **Test 4**: `nc -zv 192.168.100.12 3306` + Live View | "Default deny on the WAN: only 80/443 are forwarded, only to the VIP." |
| 9–11 | both | **Test 5**: Status Overview on both GUIs | "IKEv2, AES-256/SHA-256/DH14 for phase 1; ESP AES-256-GCM with PFS for phase 2 — identical, mirrored." |
| 11–13 | both | **Test 6**: ping both ways + `curl .../whoami`; `tcpdump -ni virbr-iwan esp` | "The peer sees our real address: no NAT. On the wire, only ESP between the two WAN addresses." |
| 13–15 | both | questions | Be ready: why tunnel mode? why PFS? what is NAT-T? what is *not* highly available? (web, MySQL, OPNsense) |

## 5. Questions you may be asked (short answers)

| Question | Answer |
|---|---|
| Transport vs tunnel mode? | Transport protects only the payload between two hosts; **tunnel** wraps the whole original IP packet in a new one — needed between gateways protecting networks |
| AH vs ESP? | AH (proto 51) = integrity only, breaks with NAT; **ESP** (proto 50) = encryption + integrity + anti-replay |
| Why UDP 4500? | **NAT-T**: if a NAT is detected between the peers, ESP is put inside UDP 4500 so NAT boxes can handle it |
| What is PFS? | Each CHILD SA uses keys from a fresh Diffie–Hellman exchange: a stolen key cannot decrypt past traffic |
| Why DH group 14? | 2048-bit MODP group: the minimum considered safe today; groups 1/2/5 are too weak |
| Why AES-256-GCM in phase 2? | AEAD: encryption and integrity in one step, fast; no separate HMAC needed |
| What does `NO_PROPOSAL_CHOSEN` mean? | The two peers have no common algorithm set — the proposals are not identical |
| Why a VIP and not DNS round-robin? | The VIP moves in ~1 s; DNS answers are cached for minutes |
| What happens if the web server dies? | HAProxy marks it DOWN and returns 503 — there is only **one** web server (spec: HA only on the proxy layer) |
| Why no NAT between the LANs? | Each site must see the real address of the other site's machines (logging, ACLs, MySQL grants by address). We prove it with `/whoami` |
