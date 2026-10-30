# 06 — Phase 6: the IPsec tunnel between the two sites (both students)

**Goal (from the spec):** an IPsec **site-to-site** VPN, **IKEv2**, **ESP** in
**tunnel mode**, between the two OPNsense firewalls, with mirrored settings and
IPsec firewall rules. **Test:** `ping 10.15.15.7` from `10.0.2.7` succeeds over
the tunnel, **without NAT** between the LANs.

**Status:** guide + automated test ready. Both students configure their own
firewall with the **same** values (mirrored), then run `make test-phase6`.

## The picture

```text
 Site A LAN 10.0.2.0/24                                               Site B LAN 10.15.15.0/24
 a-web 10.0.2.7                                                        b-web 10.15.15.7
    │ src 10.0.2.7 dst 10.15.15.7                                          ▲ src 10.0.2.7 (unchanged!)
    ▼                                                                      │
 OPNsense A ── WAN 192.168.100.11 ═══ ESP (IP proto 50) ═══ WAN 192.168.100.12 ── OPNsense B
              outer packet: src 192.168.100.11 dst 192.168.100.12, inner packet encrypted
```

**What happens, in order:**

1. `a-web` sends a packet to `10.15.15.7`; its gateway is OPNsense A.
2. OPNsense A sees a **policy**: "`10.0.2.0/24` → `10.15.15.0/24` must be protected".
3. If no tunnel exists yet, **IKE** (UDP 500) negotiates one with `192.168.100.12`:
   - **Phase 1 — IKE SA**: the firewalls authenticate each other with the
     **pre-shared key** and agree on AES-256 / SHA-256 / DH group 14. This makes a
     secure *control channel*.
   - **Phase 2 — CHILD SA**: inside it, they agree on the **ESP** keys for the
     LAN traffic (AES-256-GCM, with a new DH 14 exchange = **PFS**).
4. The original packet is encrypted and wrapped in a new IP packet
   `192.168.100.11 → 192.168.100.12` (**tunnel mode**). The Internet only sees the two firewalls.
5. OPNsense B unwraps it, checks the IPsec firewall rules, and delivers it to
   `b-web` with the **original source `10.0.2.7`** — no NAT.

| Word | Simple meaning |
|---|---|
| **IKEv2** | The "negotiation" protocol (UDP 500, or 4500 when NAT is detected = NAT-T) |
| **ESP** | The protocol that carries the encrypted LAN packets (IP protocol 50) |
| **SA** (Security Association) | One agreed set of keys + algorithms. IKE SA = control; CHILD SA = data |
| **PSK** | Pre-shared key: the same secret typed on both firewalls |
| **PFS** | Perfect Forward Secrecy: each CHILD SA gets keys from a *new* DH exchange, so stealing one key does not open old traffic |
| **DPD** | Dead Peer Detection: "are you still there?" messages; if the peer is gone, the tunnel is torn down and rebuilt |
| **Mirrored** | A's *local* network is B's *remote* network and the other way round |

## Values (agree on them together — they are in the shared inventory)

| Setting | OPNsense A | OPNsense B |
|---|---|---|
| Local address (own WAN) | `192.168.100.11` | `192.168.100.12` |
| Remote address (peer WAN) | `192.168.100.12` | `192.168.100.11` |
| IKE version | IKEv2 | IKEv2 |
| Phase 1 proposal | `aes256-sha256-modp2048` (AES-256, SHA-256, DH 14) | same |
| Phase 1 lifetime (rekey time) | 28800 s | 28800 s |
| Authentication | pre-shared key, local id = own WAN, remote id = peer WAN | same, mirrored |
| Phase 2 mode | tunnel | tunnel |
| Local network | `10.0.2.0/24` | `10.15.15.0/24` |
| Remote network | `10.15.15.0/24` | `10.0.2.0/24` |
| ESP proposal | `aes256gcm16-modp2048` (AES-256-GCM, PFS DH 14) | same |
| Phase 2 lifetime (rekey time) | 3600 s | 3600 s |
| DPD | 10 s | 10 s |

## Step 0 — the WAN link and the shared key

**One computer (rehearsal, `MODE=lab`)**: both firewalls are already on the same
`infra-wan` switch. Check from OPNsense A: **Interfaces → Diagnostics → Ping**
`192.168.100.12` → replies.

**Two computers (the defense)**: connect the two computers with an **Ethernet
cable** (or a switch), then on **both**:

```bash
sudo ./scripts/wan-link.sh enp3s0     # your Ethernet port name: ip -br link
ping -c 3 192.168.100.2               # from Site A's computer: Site B's computer answers
ping -c 3 192.168.100.12              # Site B's OPNsense WAN answers (after its Phase 2)
```

The script plugs the Ethernet port into the `virbr-iwan` virtual switch, so the
two WAN switches become **one** segment `192.168.100.0/24`. (Campus Wi-Fi usually
blocks traffic between clients — that is why we use a cable.)

**The pre-shared key** — Student 1 creates it, then gives the file to Student 2
(USB stick, `scp` over the cable — never by email, never in git):

```bash
make ipsec-psk            # creates .secrets/ipsec-psk (once)
cat .secrets/ipsec-psk    # the value to paste in the GUI
```

## Step 1 — the pre-shared key

Menu: **VPN → IPsec → Pre-Shared Keys** → **+**

| Field | Site A | Site B |
|---|---|---|
| Local Identifier | `192.168.100.11` | `192.168.100.12` |
| Remote Identifier | `192.168.100.12` | `192.168.100.11` |
| Pre-Shared Key | content of `.secrets/ipsec-psk` | **the same** |
| Type | PSK | PSK |

**Save** → **Apply**.

## Step 2 — the connection (Phase 1)

Menu: **VPN → IPsec → Connections** → **+**. *General settings* (click
*advanced mode* if some fields are hidden):

| Field | Site A | Site B | Why |
|---|---|---|---|
| Enabled | ☑ | ☑ | |
| Proposals | `aes256-sha256-modp2048 [DH14]` | same | Phase 1: AES-256 / SHA-256 / DH 14 |
| Version | **IKEv2** | IKEv2 | spec |
| Local addresses | `192.168.100.11` | `192.168.100.12` | our WAN |
| Remote addresses | `192.168.100.12` | `192.168.100.11` | peer WAN |
| DPD delay (s) | `10` | `10` | dead-peer detection |
| Rekey time (s) | `28800` | `28800` | IKE SA lifetime |
| Description | `Site A <-> Site B` | `Site B <-> Site A` | |

Click **Save** (the dialog stays open, now with the sections below).

**Local Authentication** → **+**: Round `0`, Authentication **Pre-Shared Key**,
Id **own WAN** (`192.168.100.11` on A) → Save.

**Remote Authentication** → **+**: Round `0`, Authentication **Pre-Shared Key**,
Id **peer WAN** (`192.168.100.12` on A) → Save.

## Step 3 — the child (Phase 2)

Still in the connection, **Children** → **+**:

| Field | Site A | Site B |
|---|---|---|
| Enabled | ☑ | ☑ |
| Mode | **Tunnel** | Tunnel |
| Policies | ☑ | ☑ |
| ESP proposals | `aes256gcm16-modp2048 [DH14]` | same |
| Start action | **Trap+start** (or *Start*) | same |
| Local | `10.0.2.0/24` | `10.15.15.0/24` |
| Remote | `10.15.15.0/24` | `10.0.2.0/24` |
| Rekey time (s) | `3600` | `3600` |
| Description | `LAN A <-> LAN B` | `LAN B <-> LAN A` |

**Save**, close the connection dialog with **Save**, then at the bottom of
the *Connections* page check **Enable IPsec** and click **Apply**.

> Field names follow OPNsense 26.7 (*Connections* = the modern swanctl
> interface). Older tutorials use *Tunnel Settings → Phase 1 / Phase 2*: same
> values, different pages.

## Step 4 — firewall rules

**WAN** — allow only the peer firewall to talk IPsec. Menu **Firewall → Rules → WAN** → **+**, three rules:

| Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|
| Pass | UDP | `192.168.100.12` (single host) | WAN address | 500 (ISAKMP) | IKE from Site B |
| Pass | UDP | `192.168.100.12` | WAN address | 4500 (IPsec NAT-T) | NAT-T from Site B |
| Pass | ESP | `192.168.100.12` | WAN address | — | ESP from Site B |

(Site B: source `192.168.100.11`.) ☑ Log on each → **Save** → **Apply**.
OPNsense may also add hidden automatic IPsec rules; ours make the policy explicit.

**IPsec** — what may come *out of* the tunnel. Menu **Firewall → Rules → IPsec**
(the tab appears once IPsec is enabled) → **+**, two rules:

| Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|
| Pass | ICMP | `10.15.15.0/24` | `10.0.2.0/24` | — | ping from LAN B |
| Pass | TCP | `10.15.15.0/24` | `10.0.2.0/24` | 80 (HTTP) | web from LAN B |

(Site B: source `10.0.2.0/24`, destination `10.15.15.0/24`.) ☑ Log → **Save** → **Apply**.

Traffic *into* the tunnel from our own LAN is already allowed by *Default allow LAN to any*.

## Step 5 — check the status

Menu: **VPN → IPsec → Status Overview**:

- the connection shows **ESTABLISHED** (Phase 1, IKE SA) — expand it:
- the child shows **INSTALLED** (Phase 2, CHILD SA) with `10.0.2.0/24 === 10.15.15.0/24`,
  and the byte counters go up when you ping.

This page is the screenshot for **acceptance test 5**. If it stays down, start it
with the ▶ button, or just send traffic (Step 6): *Trap* starts the tunnel on demand.

## Step 6 — test (acceptance test 6)

```bash
ssh -i .secrets/infra_ed25519 infra@10.0.2.7
ping -c 4 10.15.15.7                 # replies = through the tunnel
curl -s http://10.15.15.7/whoami     # prints 10.0.2.7  ← B sees A's real address: no NAT
tracepath -n 10.15.15.7              # 1: 10.0.2.1 (OPNsense A), then directly 10.15.15.7
exit
make test-phase6 SITE=a
```

On the other side, Student 2 runs the same with `10.15.15.7 → 10.0.2.7` and `make test-phase6 SITE=b`.

**See the encryption with your own eyes** (one computer, lab mode): on the host,
`sudo tcpdump -ni virbr-iwan esp` while pinging → only `192.168.100.11 > 192.168.100.12: ESP(spi=...)`
lines, never `10.0.2.7`. On the LAN, `sudo tcpdump -ni virbr-ib icmp` → clear
`10.0.2.7 > 10.15.15.7: ICMP echo request`.

Then save both configurations: `make opnsense-backup SITE=a` (and `SITE=b`).

## The test, explained

[tests/phase6.yml](../tests/phase6.yml):

| Check | How |
|---|---|
| Phase 1 ESTABLISHED + Phase 2 INSTALLED for the two LANs | `ssh root@10.0.2.1 swanctl --list-sas` (needs SSH enabled in Phase 2, steps 4–5; otherwise look at the Status Overview) |
| Ping the peer web server | `ping -c 4 10.15.15.7` from a-web |
| No NAT between the LANs | `curl http://10.15.15.7/whoami` from a-web must print `10.0.2.7` |

Before Phase 6 this ping **fails** (checked in Phases 1 and 2): the only path
between the LANs is the tunnel.

## If something goes wrong

Look first at **VPN → IPsec → Log File**.

| Symptom / log line | Cause | Fix |
|---|---|---|
| `NO_PROPOSAL_CHOSEN` | Phase 1 or Phase 2 algorithms differ between A and B | compare proposals, DH group, ESP proposal on both sides |
| `AUTHENTICATION_FAILED` / *no shared key found* | PSK differs, or local/remote **identifiers** don't match the other side | same PSK file; ids = WAN addresses, mirrored |
| `TS_UNACCEPTABLE` | Phase 2 networks are not mirrored | A local `10.0.2.0/24` = B remote, and vice versa |
| No log line at all, peer never answers | UDP 500/ESP blocked, or no WAN link | WAN rules (Step 4); `ping 192.168.100.12` from Interfaces → Diagnostics; *Block private networks* unchecked on WAN |
| Tunnel up, ping fails | missing **IPsec** rule on the *receiving* side | Firewall → Rules → IPsec on the peer |
| `whoami` shows `192.168.100.11` instead of `10.0.2.7` | traffic left by the WAN with NAT instead of the tunnel (the policy did not match) | check the child's networks; **Firewall → NAT → Source NAT**: switch to *Hybrid* and add a **Do not NAT** rule, interface WAN, source `10.0.2.0/24`, destination `10.15.15.0/24` |
| Works, then stops after an hour | rekey problem (lifetimes/PFS differ) | same rekey times and ESP proposal (with DH 14) on both sides |
