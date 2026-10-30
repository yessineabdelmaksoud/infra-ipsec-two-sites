# 02 — Phase 2: OPNsense (the router/firewall of each site)

**Goal (from the spec):** install OPNsense, assign WAN/LAN, configure routing and
LAN-side administration. **Test:** the site VMs reach the Internet through OPNsense.

**Status:** automated part ✅ (both sites pass `make test-phase2`).
Your part: the **web interface steps** below (Part B), then a backup.

## The picture

```text
          your computer 192.168.100.1  (does NAT to your Wi-Fi = "the Internet")
                     |
   infra-wan  ───────┴───────────────── 192.168.100.0/24  ("fake Internet")
                     |
             WAN 192.168.100.11  (vtnet1)
            ┌───────────────────┐
            │    a-opnsense     │  routes + NAT + firewall + DNS (Unbound)
            └───────────────────┘
             LAN 10.0.2.1        (vtnet0)
                     |
   infra-a-lan ──────┴────┬──────────┬──────────┬──────────── 10.0.2.0/24
                       haproxy1   haproxy2     web         db
                       gateway = 10.0.2.1 for everybody
```

A packet from `a-web` to the Internet: `a-web` → **OPNsense LAN** → OPNsense
replaces the source `10.0.2.7` with its WAN address `192.168.100.11` (**NAT**)
→ your computer → Wi-Fi → Internet. The answer comes back the same way.

## Values for both sites

| What | Site A | Site B |
|---|---|---|
| VM name | `a-opnsense` | `b-opnsense` |
| LAN interface / address | `vtnet0` = `10.0.2.1/24` | `vtnet0` = `10.15.15.1/24` |
| WAN interface / address | `vtnet1` = `192.168.100.11/24` | `vtnet1` = `192.168.100.12/24` |
| WAN gateway (upstream) | `192.168.100.1` | `192.168.100.1` (lab) / `192.168.100.2` (2 computers) |
| Web UI | https://10.0.2.1 | https://10.15.15.1 |
| Hostname / domain | `fw-a` / `site-a.lab` | `fw-b` / `site-b.lab` |
| Factory login | `root` / `opnsense` | `root` / `opnsense` |

---

## Part A — what `make phase2` does for you (automatic)

```bash
make phase2 SITE=a      # ~70 seconds for a brand new firewall
```

1. Downloads the official **OPNsense 26.7 "nano" image** (a disk already
   installed — no installer to click through) and checks its SHA-256.
2. Creates the VM `a-opnsense` with **2 network cards**. The order matters:
   card 1 → `infra-a-lan` (FreeBSD calls it `vtnet0`), card 2 → `infra-wan` (`vtnet1`).
3. Types the **console setup** for you (file
   [scripts/opnsense_console.py](../scripts/opnsense_console.py)).

### The console setup, explained (what you would type by hand)

Open the console yourself to see it: `virsh -c qemu:///system console a-opnsense`
(press Enter; exit with `Ctrl + ]`).

On first boot OPNsense **assigns the interfaces by itself**: `vtnet0` → LAN,
`vtnet1` → WAN (we placed the cards in that order for this reason). The LAN gets
the factory address `192.168.1.1`, which is wrong for us. So the script does:

```text
login: root
Password: opnsense

 0) Logout                              7) Ping host
 1) Assign interfaces                   8) Shell
 2) Set interface IP address            ...
Enter an option: 2                      <- "Set interface IP address"

1 - LAN (vtnet0 - static, idassoc6)
2 - WAN (vtnet1 - dhcp, dhcp6)
Enter the number of the interface to configure: 1
Configure IPv4 address LAN interface via DHCP? [y/N] n
Enter the new LAN IPv4 address. Press <ENTER> for none:
> 10.0.2.1
Enter the new LAN IPv4 subnet bit count (1 to 32):
> 24
For a WAN, enter the new LAN IPv4 upstream gateway address.
For a LAN, press <ENTER> for none:
>                                       <- LAN: no gateway (Enter)
Configure IPv6 address LAN interface via WAN tracking? [Y/n] n
Configure IPv6 address LAN interface via DHCP6? [y/N] n
Enter the new LAN IPv6 address. Press <ENTER> for none:
>                                       <- no IPv6
Do you want to enable the DHCP server on LAN? [y/N] n      <- our IPs are fixed
Do you want to change the web GUI protocol from HTTPS to HTTP? [y/N] n
Do you want to generate a new self-signed web GUI certificate? [y/N] n
Restore web GUI access defaults? [y/N] n
```

Then the same `2` again for the **WAN** (`2`), with `192.168.100.11`, `24`,
gateway **`192.168.100.1`**, and `n` to *"use the gateway as the IPv4 name server"*.

How the script "types": it waits for a known sentence, then sends the answer.

```python
answer_until(child, {
    r'IPv4 address \w+ interface via DHCP' + YN: 'n',
    r'Enter the new \w+ IPv4 address\. Press <ENTER> for none:' + prompt: ip,
    r'Enter the new \w+ IPv4 subnet bit count \(1 to 32\):' + prompt: str(prefix),
    r'For a LAN, press <ENTER> for none:' + prompt: gateway,
    ...
}, MENU)   # stop when the main menu "Enter an option:" is back
```

`\w+` = "any word" (LAN or WAN), so the same table works for both interfaces.

> **What we learned while building this (the "spike"):**
> - During boot OPNsense shows *"Press any key to start the configuration importer"*.
>   Pressing a key there starts a tool that **imports a saved `config.xml` from a disk**.
>   So the script **never types during boot** — it just waits for `login:`.
>   (Later we can use this importer to restore a saved config automatically.)
> - If `a-opnsense` already answers on `https://10.0.2.1`, the console step is
>   skipped → running `make phase2` twice is safe (`changed=0`).

After Part A, the Internet **already works** for the VMs, because OPNsense's
factory rules are: *LAN may go anywhere*, *automatic NAT from LAN to WAN*,
*DNS resolver on*. Part B makes the configuration **correct and clean**.

---

## Part B — the web interface, step by step (you do this)

Use a browser **on this computer** (only it is plugged into the LAN, as `.254`).
Below: Site A values; for Site B use the right column of the table above.

### Step 0 — log in

1. Open **https://10.0.2.1**
2. Warning "connection not private" → **Advanced** → **Accept the risk / Continue**.
   (The certificate is self-signed: normal for a lab.)
3. Username `root`, password `opnsense`.

### Step 1 — the Setup Wizard

Menu: **System → Configuration → Wizard** (it may open by itself at first login).
Click **Next** on *Welcome*, then:

**General Information**

| Field | Value | Why |
|---|---|---|
| Hostname | `fw-a` | name of the firewall |
| Domain | `site-a.lab` | local domain of the site |
| Language | English | |
| Timezone | your timezone | correct times in the logs |
| DNS Servers | `1.1.1.1` and `9.9.9.9` | used by the firewall itself |
| Override DNS | ☐ unchecked | our WAN is static, nothing to override |
| Enable Resolver | ☑ checked | Unbound answers DNS for the LAN on `10.0.2.1` |
| Enable DNSSEC Support | ☐ (optional) | |

**Network [WAN]**

| Field | Value | Why |
|---|---|---|
| Type | **Static** | fixed address from our plan |
| IP Address | `192.168.100.11/24` | OPNsense A's WAN |
| Gateway | **`192.168.100.1`** | ⚠️ **type it**, do not leave empty: it is the exit to the Internet |
| Block RFC1918 Private Networks | ☐ **uncheck** | ⚠️ see below |
| Block bogon networks | ☐ **uncheck** | ⚠️ see below |

> ⚠️ **Why uncheck the two "Block" boxes?** On a real Internet line, packets from
> private addresses (`192.168.x.x`, `10.x.x.x`) are fake, so OPNsense drops them.
> But **our "Internet" is `192.168.100.0/24`** — a private range! Your computer
> (`.1`) and Site B's firewall (`.12`) live there. If the boxes stay checked,
> Phase 5 (open the web page from the WAN) and Phase 6 (IPsec from Site B) will
> silently fail.

**Network [LAN]**

| Field | Value | Why |
|---|---|---|
| IP Address | `10.0.2.1/24` | gateway of all Site A VMs |
| Configure DHCP server | ☐ **uncheck** | every VM has a fixed IP (spec rule) |

**Deployment type** — leave the defaults.

**Set initial password** — choose a new root password (Root Password + Confirmation).
Write it down in a file only you can read:

```bash
echo 'YOUR-NEW-PASSWORD' > .secrets/opnsense-a-root-password && chmod 600 .secrets/opnsense-a-root-password
```

**Finish** → **Apply**. Wait ~20 seconds, log in again with the new password.

### Step 2 — check the interfaces

Menu: **Interfaces → Overview**

- `LAN` (vtnet0) → `10.0.2.1/24`, status up
- `WAN` (vtnet1) → `192.168.100.11/24`, status up

### Step 3 — check the gateway

Menu: **System → Gateways → Configuration**

- One line `WAN_GW`, interface WAN, address `192.168.100.1`, marked as **default/upstream**.
- Status should be **green / Online** (OPNsense pings `192.168.100.1` to check it).

### Step 4 — LAN-side administration only (+ SSH for automation)

Menu: **System → Settings → Administration**

*Web GUI* section:

| Field | Value | Why |
|---|---|---|
| Protocol | HTTPS | encrypted |
| Listen Interfaces | **LAN** | the admin page must never be on the WAN |

*Secure Shell* section:

| Field | Value | Why |
|---|---|---|
| Secure Shell Server | ☑ **Enable Secure Shell** | lets `make opnsense-backup` copy the config |
| Root Login | ☑ Permit root user login | the automation logs in as root (with a key) |
| Authentication Method | ☐ Permit password login **unchecked** | keys only = safer |
| Listen Interfaces | **LAN** | SSH never on the WAN |

Click **Save** at the bottom.

### Step 5 — give root our SSH key

1. In a terminal, print the public key:
   ```bash
   cat .secrets/infra_ed25519.pub
   # ssh-ed25519 AAAA...  infra-lab
   ```
2. Menu: **System → Access → Users** → click the ✏️ (edit) of **root**.
3. Field **Authorized Keys**: paste the whole line → **Save**.

A *public* key is like a padlock you give to OPNsense; only the *private* key
(`.secrets/infra_ed25519`, never shared) can open it.

### Step 6 — look, don't change (understand the defaults)

| Menu | What you see | Meaning |
|---|---|---|
| **Services → Unbound DNS → General** | Enable ☑, port 53 | the DNS server the VMs use (`10.0.2.1`) |
| **Firewall → NAT → Source NAT** | automatic rule: source `LAN net` → WAN address | this is the "share one address" NAT. *(In older OPNsense it was called "Outbound NAT".)* |
| **Firewall → Rules → LAN** | *Default allow LAN to any rule* | LAN VMs may go out |
| **Firewall → Rules → WAN** | no pass rule | everything coming from the WAN is **blocked** by default |

### Step 7 — test from the interface

- **Interfaces → Diagnostics → Ping**: host `1.1.1.1` → replies.
- **Interfaces → Diagnostics → DNS Lookup**: `archive.ubuntu.com` → addresses.

### Step 8 — save the configuration

In the terminal:

```bash
make opnsense-backup SITE=a
# -> .secrets/opnsense/a-opnsense-config.xml
```

(Same as **System → Configuration → Backups → Download configuration**.)
This XML file **is** the firewall's whole configuration: it is one of the
project deliverables, and it lets us rebuild the firewall identically later.

> **Make a backup after every GUI session** (here, after Phase 5 and after
> Phase 6). If the firewall is ever killed instead of shut down cleanly, it may
> not boot again: `make opnsense-rebuild SITE=a`, then **System → Configuration →
> Backups → Restore** with this file. Details: [08-troubleshooting](08-troubleshooting.md).

### Step 9 — run the test

```bash
make test-phase2 SITE=a
```

---

## The test, explained

[tests/phase2.yml](../tests/phase2.yml) checks from **two places**:

From your computer (the "outside"):

```yaml
- name: Web UI answers on the LAN address          # https://10.0.2.1 → 200 OK
- name: Web UI and SSH are closed on the WAN address
  ansible.builtin.wait_for:
    host: "{{ site.wan_ip }}"      # 192.168.100.11
    port: "{{ item }}"
    timeout: 5
  loop: [443, 80, 22]
  failed_when: wan_ports is succeeded   # if a port OPENS, the test FAILS
```

From each VM (the "inside"):

```yaml
- name: First hop towards the Internet is OPNsense
  ansible.builtin.command: tracepath -n -m 1 1.1.1.1    # 1st router must be 10.0.2.1
- name: Ping a public address                          # ping 1.1.1.1
- name: Resolve a name with OPNsense as DNS server      # dig @10.0.2.1 archive.ubuntu.com
- name: Package index download works                   # apt-get update
```

## Check by hand

```bash
ssh -i .secrets/infra_ed25519 infra@10.0.2.7
tracepath -n 1.1.1.1 | head -3     # 1: 10.0.2.1  ← OPNsense first
ping -c 3 1.1.1.1                  # replies
dig @10.0.2.1 archive.ubuntu.com   # answer from Unbound
ping -c 2 10.15.15.7               # still FAILS: no tunnel yet (Phase 6)
```

## If something goes wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| Browser can't open https://10.0.2.1 | browser not on this computer, or VM off | `virsh -c qemu:///system list`; use this computer's browser |
| VMs lost Internet after the wizard | WAN **Gateway** left empty | Wizard again, type `192.168.100.1`; check **System → Gateways** |
| Locked out of the web UI | Listen Interfaces set to WAN only | console → option `2` → LAN → answer **y** to *Restore web GUI access defaults* |
| `make opnsense-backup` asks for a password / fails | SSH not enabled or key not pasted | redo Steps 4 and 5 |
| `https://10.0.2.1` unreachable, VM *running*, console shows nothing | firewall disk broken by a hard power-off | `make opnsense-rebuild SITE=a`, then restore the backup ([08](08-troubleshooting.md)) |
| Want to start over | | `make destroy SITE=a && make phase1 SITE=a && make phase2 SITE=a` |
