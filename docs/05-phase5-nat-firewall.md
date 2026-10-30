# 05 — Phase 5: NAT + firewall (OPNsense web UI)

**Goal (from the spec):** forward WAN ports 80/443 to the VIP and restrict
unnecessary access. **Test:** open the web page from the OPNsense WAN IP, and
MySQL (3306) must be blocked from the WAN.

**Status:** guide + automated test ready. **You do the clicks below**, then
`make test-phase5 SITE=a` checks the result from the outside.

**Before you start:** Phases 1–4 pass, and the Phase 2 web UI steps are done
(wizard, WAN gateway, *Block private networks* **unchecked**). Site A values
below; for Site B see the table.

| What | Site A | Site B |
|---|---|---|
| GUI | https://10.0.2.1 | https://10.15.15.1 |
| WAN address (what the "Internet" sees) | `192.168.100.11` | `192.168.100.12` |
| VIP (where the web traffic must go) | `10.0.2.100` | `10.15.15.100` |

## The picture

```text
  Internet client (your computer 192.168.100.1)
        │  http://192.168.100.11/
        ▼
  ┌──────────── OPNsense A ─────────────────────────────────────────────┐
  │ WAN 192.168.100.11                                                  │
  │  1. Destination NAT: TCP 80/443 to "WAN address" → 10.0.2.100       │
  │  2. WAN rule: pass TCP 80/443 to 10.0.2.100  (logged)               │
  │  3. everything else from the WAN: blocked by the default deny (logged)
  │ LAN 10.0.2.1                                                        │
  └─────────────────────────────────────────────────────────────────────┘
        ▼
  VIP 10.0.2.100 → HAProxy → Nginx 10.0.2.7 → MySQL 10.0.2.8 (3306 never reachable from the WAN)
```

- **Destination NAT** (called *Port Forward* in older OPNsense) changes the
  **destination** of a packet: "to `192.168.100.11:80`" becomes "to `10.0.2.100:80`".
- A NAT rule only *rewrites*; a **firewall rule** must also *allow* the
  packet. OPNsense can create that rule for you ("associated filter rule").
- **Default deny**: on the WAN, anything not explicitly allowed is dropped.
  So MySQL 3306, SSH 22 and the GUI are blocked simply because **we never allow them**.

---

## Step 1 — Destination NAT for HTTP (port 80)

Menu: **Firewall → NAT → Destination NAT** → **+** (add)

| Field | Value | Why |
|---|---|---|
| Interface | **WAN** | the packets arrive on the WAN |
| TCP/IP Version | IPv4 | |
| Protocol | **TCP** | HTTP uses TCP |
| Source | any | anybody on the Internet |
| Destination | **WAN address** | the firewall's own public address |
| Destination port range | from **HTTP** to **HTTP** (80) | |
| Redirect target IP | **`10.0.2.100`** (type it, Single host) | the VIP, **never** the web server directly |
| Redirect target port | **HTTP** (80) | |
| Description | `WAN HTTP -> VIP` | |
| Filter rule association | **Add associated filter rule** | creates the WAN pass rule automatically |

**Save** → **Apply changes**.

> In OPNsense 26.7 the page may be laid out differently from older tutorials
> (the menu was renamed from *Port Forward*). The meaning of the fields is the
> same: *where the packet arrives* → *where it must go*.

## Step 2 — the same for HTTPS (port 443)

Click the **clone** icon of the rule from Step 1 (or **+** again) and change:
destination port **HTTPS** (443), redirect target port **HTTPS** (443),
description `WAN HTTPS -> VIP`. **Save** → **Apply**.

HTTPS is terminated by HAProxy with our self-signed certificate (Phase 4), so
the browser shows a warning — normal in a lab.

## Step 3 — log the allowed web traffic

Menu: **Firewall → Rules → WAN**. You now see the two associated rules
(*NAT WAN HTTP -> VIP*, *NAT WAN HTTPS -> VIP*). For each: ✏️ edit → check
**Log packets that are handled by this rule** → **Save**. Then **Apply changes**.

## Step 4 — make sure blocked traffic is logged

Menu: **Firewall → Settings → Advanced** (or *Firewall → Settings → Logging*,
depending on the version): **Log packets blocked by the default rule** ☑ checked
(it is the default). This is the *"logged"* part of *"minimal and logged rules"*.

Optional, makes the defense clearer: an **explicit** block rule for MySQL.
**Firewall → Rules → WAN → +**: Action **Block**, Interface WAN, Protocol TCP,
Destination **any**, Destination port **3306**, ☑ Log, Description
`Block MySQL from the Internet` → **Save** → move it to the **top** → **Apply**.

## Step 5 — check the LAN side stays minimal

Menu: **Firewall → Rules → LAN**: keep only the factory rules
(*anti-lockout* for the GUI and *Default allow LAN to any*). The VMs need the
Internet for packages; nothing else is needed.

Do **not** add any WAN rule for 22, 3306 or the GUI.

## Step 6 — test it

From this computer (it plays the "Internet client" on the WAN):

```bash
curl -s http://192.168.100.11/ | grep -o 'stored in MySQL on [^<]*'   # acceptance test 1
curl -sk https://192.168.100.11/ | grep -o 'id="proxy">[^<]*'          # HTTPS works too
nc -zv -w 5 192.168.100.11 3306                                        # acceptance test 4: must time out
make test-phase5 SITE=a
```

Open **http://192.168.100.11/** in the browser too: same page as through the
VIP, but this time **through the firewall's NAT** — this is the screenshot for
acceptance test 1.

Live proof in the GUI: **Firewall → Log Files → Live View**, then run the `nc`
command again → a red *block* line for `192.168.100.1 → 192.168.100.11:3306`.

Then save the configuration: `make opnsense-backup SITE=a`.

## The test, explained

[tests/phase5.yml](../tests/phase5.yml) runs on your computer, i.e. **from the WAN**:

| Check | Expected |
|---|---|
| `http://` and `https://192.168.100.11/` | 200, the database page — **not** the OPNsense login page (proves the GUI is not on the WAN) |
| TCP 3306, 22, 8404 on `192.168.100.11` | no answer (blocked) |
| stop keepalived on haproxy1, reload `http://192.168.100.11/` | still works, served by haproxy2 — the NAT points to the **VIP**, so failover is invisible from the Internet |

## If something goes wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| `curl http://192.168.100.11/` hangs | no pass rule on WAN (association not created) | add it in Firewall → Rules → WAN: pass TCP to `10.0.2.100` port 80 |
| It hangs, and the Live View shows *Block private networks* | the Phase 2 wizard box was left checked | **Interfaces → [WAN]** → uncheck *Block private networks* and *Block bogon networks* → Save → Apply |
| You get the OPNsense login page on the WAN | GUI listens on all interfaces and wins over the NAT | **System → Settings → Administration → Listen Interfaces = LAN** (Phase 2, step 4) |
| HTTP works, HTTPS does not | no NAT/rule for 443, or HAProxy has no certificate | Step 2; `make test-phase4 SITE=a` |
| 3306 test says OPEN | someone added a forward/rule for 3306 | delete it; the WAN must only allow 80/443 |
