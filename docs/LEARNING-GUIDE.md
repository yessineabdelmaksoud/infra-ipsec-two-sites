# Learning guide — understand the whole project (not just run it)

The phase pages (docs/00–08) explain each piece. This guide gives you the
**big picture**, shows **how the code turns into machines**, explains **why**
each choice was made, tells **how it was built and debugged**, and ends with
**exercises** — because you only really understand a system after you have
broken it and fixed it yourself.

**Reading plan (about 3 hours, spread over days):**

| Step | Read / do | Time |
|---|---|---|
| 1 | Sections 1–3 of this guide | 30 min |
| 2 | [docs/README](README.md) mini dictionary, then docs 00 → 04 in order, with the VMs running, trying every "Check by hand" command | 1 h 30 |
| 3 | Sections 4–6 of this guide | 30 min |
| 4 | Exercises (section 7), at least levels 1 and 2 | 1 h + |
| 5 | Docs 05 and 06 *while* you do the GUI steps | with the work |
| 6 | Self-check (section 8): answer out loud without notes | 15 min |

---

## 1. The system in layers

Read it from the bottom (your laptop) to the top (the tunnel):

```text
 6  IPsec tunnel        OPNsense A ═══ ESP ═══ OPNsense B        joins the two LANs (Phase 6)
 5  Firewall / NAT      OPNsense: WAN rules, destination NAT     what may enter a site (Phase 5)
 4  High availability   Keepalived moves the VIP, HAProxy proxies (Phase 4)
 3  Application         Nginx + PHP page  →  MySQL                (Phase 3)
 2  Router              OPNsense = gateway .1 of every VM        (Phase 2)
 1  Virtual hardware    VMs + virtual switches (bridges)          (Phase 1)
 0  Your laptop         Linux + KVM + libvirt, driven by Ansible  (setup)
```

Each layer only works if the one below works. That is why the project is
built **phase by phase, with a test at the end of each**: when something
breaks in Phase 5, you already *know* layers 1–4 are fine.

## 2. Follow the packets (the most useful exercise for the defense)

### Journey 1 — a visitor opens `http://192.168.100.11/`

| # | Where | What happens |
|---|---|---|
| 1 | Client `192.168.100.1` | sends TCP to `192.168.100.11:80` (OPNsense A's WAN) |
| 2 | OPNsense WAN | **destination NAT**: destination becomes `10.0.2.100:80` (the VIP) |
| 3 | OPNsense WAN rule | the associated **pass** rule allows it (otherwise default deny drops it) |
| 4 | LAN switch | ARP "who has `10.0.2.100`?" → **a-haproxy1** answers (Keepalived MASTER added the VIP to its card) |
| 5 | HAProxy on haproxy1 | frontend on VIP:80 → backend `be_web` → forwards to `10.0.2.7:80`, adds `X-Forwarded-For` and `X-Proxy-Node` |
| 6 | Nginx on a-web | `index.php` → PHP-FPM |
| 7 | PHP → MySQL `10.0.2.8:3306` | as `app@10.0.2.7`: `UPDATE page_views`, `SELECT messages` |
| 8 | Back | web → HAProxy → OPNsense (reverse NAT: source becomes `192.168.100.11` again) → client |

### Journey 2 — the MASTER proxy dies

haproxy1 stops sending VRRP "I'm alive" messages (or announces priority 0
when keepalived stops cleanly). After ~1–3 s haproxy2 becomes MASTER, adds
`10.0.2.100` to its card and sends a **gratuitous ARP** ("`10.0.2.100` is now
at *my* MAC address"). OPNsense's NAT still sends to `10.0.2.100` — it never
knew anything changed. HAProxy on haproxy2 was already running and already
bound to the VIP (`ip_nonlocal_bind`), so it answers immediately.

### Journey 3 — `a-web` pings `b-web` through the tunnel

`10.0.2.7 → 10.15.15.7` goes to the gateway OPNsense A. Its IPsec **policy**
says "10.0.2.0/24 → 10.15.15.0/24 must be encrypted". IKE (UDP 500) builds the
tunnel if needed, then the packet is encrypted inside ESP:
`192.168.100.11 → 192.168.100.12`. OPNsense B decrypts it, and its IPsec rule
allows ICMP **from A's LAN `10.0.2.0/24`** (careful: on B, the *source* of
incoming tunnel traffic is the other site's LAN). b-web receives a packet whose source is still
`10.0.2.7`: **no NAT**. `/whoami` proves it.

> Exercise: draw these three journeys on paper from memory. If you can, you can
> answer most defense questions.

## 3. How a `make` command becomes machines

Take `make phase3 SITE=a`:

```text
make phase3 SITE=a
 └─ Makefile:   .venv/bin/ansible-playbook -i inventories/common -i inventories/site_a
                -e deployment_mode=distributed playbooks/phase3.yml
     └─ Ansible loads the inventory (machines + variables):
          inventories/common/hosts.yml         groups: haproxy, web, db, opnsense, hypervisor
          inventories/common/group_vars/*.yml  the shared plan (sites.a, sites.b, passwords lookups...)
          inventories/site_a/hosts.yml         a-web = 10.0.2.7, a-db = 10.0.2.8, ...
          inventories/site_a/group_vars/all.yml   site_id: a  → site = sites['a']
     └─ playbooks/phase3.yml says:  db hosts → role mysql;  web hosts → role webapp
         └─ roles/mysql/tasks/main.yml: a list of tasks (install package, write file, run SQL)
             └─ templates/*.j2: files with {{ variables }} filled per machine
         └─ Ansible connects with SSH (user infra, key .secrets/infra_ed25519) to 10.0.2.8 ...
```

**The one trick that makes "same code, two sites" work** is in
[inventories/common/group_vars/all.yml](../inventories/common/group_vars/all.yml):

```yaml
sites:
  a: {lan_cidr: 10.0.2.0/24, vip: 10.0.2.100, web_ip: 10.0.2.7, ...}
  b: {lan_cidr: 10.15.15.0/24, vip: 10.15.15.100, web_ip: 10.15.15.7, ...}
site: "{{ sites[site_id] }}"     # site_id comes from inventories/site_a or site_b
peer: "{{ sites[peer_site_id] }}"
```

Every role writes `site.vip`, `site.web_ip`, `peer.lan_cidr`... never a raw
address. Change `SITE=a` to `SITE=b` and every value follows.

**Where to look for what:**

| Question | File |
|---|---|
| Which addresses? | `inventories/common/group_vars/all.yml` |
| Which machines, MASTER/BACKUP? | `inventories/site_*/hosts.yml` |
| What does phase N do? | `playbooks/phaseN.yml` → the roles it lists |
| How is service X configured? | `roles/X/tasks/main.yml` + `roles/X/templates/` |
| How is phase N checked? | `tests/phaseN.yml` |
| Where do passwords come from? | `lookup('ansible.builtin.password', ...)` in group_vars → files in `.secrets/` |

**Reading an Ansible task** — every task has the same shape:

```yaml
- name: Listen on the LAN address only          # what a human reads in the output
  ansible.builtin.template:                     # the module = the action
    src: zz-infra.cnf.j2                        # module options
    dest: /etc/mysql/mysql.conf.d/zz-infra.cnf
  notify: Restart MySQL                         # if the file changed, run this handler at the end
```

In the output, `ok` = already correct, `changed` = Ansible fixed something,
`failed` = stop. Running a playbook twice and getting `changed=0` is the proof
the code is **idempotent** (describes a state, not a list of clicks).

## 4. Why it is built this way (decisions)

| Decision | Alternatives | Why this one |
|---|---|---|
| KVM + libvirt VMs | VirtualBox, Docker | OPNsense is FreeBSD → needs a real VM; KVM is native on Linux, libvirt describes networks/VMs as XML that code can generate |
| Ansible | shell scripts, Terraform | one tool for creating VMs *and* configuring Linux *and* testing; readable YAML; idempotent modules |
| Ubuntu cloud image + cloud-init | installing Ubuntu by hand | a VM boots configured (IP, user, SSH key) in ~30 s, the same every time |
| qcow2 overlays | full disk copies | 8 VMs share one 600 MB base image; each VM stores only its changes |
| Static IPs, MAC derived from IP | DHCP | the spec fixes every address; same MAC every rebuild, no collisions between sites |
| OPNsense configured **by hand** in the GUI | its REST API | you wanted to learn the GUI; the result is saved as XML and checked by tests anyway |
| VIP + Keepalived **unicast** | multicast VRRP | the two nodes talk directly, easy to see with `tcpdump`, no dependency on multicast |
| HAProxy binds the VIP on both nodes (`ip_nonlocal_bind`) | start HAProxy only on the MASTER | failover = only the address moves, no service restart |
| `track_script` on haproxy | Keepalived alone | if HAProxy dies but Keepalived lives, the VIP must still move |
| MySQL user `app@10.0.2.7`, minimal grants | `app@'%'` with all privileges | the spec wants the user permitted *from the web server*; least privilege |
| `/whoami` endpoint | `tcpdump` on the peer | a test can prove "no NAT" automatically, from one side |
| Secrets generated into `.secrets/`, redacted deliverables | passwords in the YAML | the repository can be shared/published safely |
| Lab mode (both sites on one laptop) | only two computers | everything can be developed and rehearsed with one computer; fallback for the defense |

## 5. How it was built — the method

The same loop for every phase:

1. **Read the spec** for that stage and write down the test that proves it (PLAN.md).
2. **Spike** the unknown parts by hand first (e.g. the OPNsense console prompts were
   recorded manually before `scripts/opnsense_console.py` was written).
3. **Write the code**: inventory values → role → playbook.
4. **Write the test** (`tests/phaseN.yml`) — it checks the *requirement*, not the code.
5. **Run, read the error, fix, run again** until the test passes.
6. **Run it twice**: the second run must report `changed=0`.
7. **Run it for the other site** (Site B, lab mode): proves nothing is Site-A-specific.
8. **Document** what was done, why, and the problems met (the docs you are reading).

### The real problems, and how they were found

These are the most valuable part to learn from: each one is a debugging method.

**a) The firewalls did not boot (Phase 2, found 2026-10-30).**
Symptom: `https://10.0.2.1` → *No route to host*. Investigation, step by step:

| Question | Command | Answer |
|---|---|---|
| Is the VM running? | `virsh domstate a-opnsense` | running |
| Is it doing something? | `virsh dominfo` twice, compare *CPU time* | yes, 100 % of a CPU |
| What does it print? | `virsh console` for 2 minutes after a restart | **nothing at all** |
| Where is the CPU? | `virsh qemu-monitor-command --hmp 'info registers'` | real mode, address `0x93xx` = the very first boot stage |
| Is the image bad, or this disk? | new VM with a **fresh** overlay of the same image | boots fine → this disk is broken |
| What breaks a disk? | fresh VM: boot → clean shutdown → boot, then boot → `virsh destroy` → boot | clean OK, **hard power-off breaks it** |

Method: *compare a broken thing with a fresh one, then reproduce the cause on
purpose*. Fix: never hard-kill (`make down`, clean shutdown at host poweroff),
`make opnsense-rebuild`, and backups.

**b) apt was locked (Phase 3).** Message: *Could not get lock ... held by
unattended-upgr*. Reading the error carefully was enough: Ubuntu's automatic
updates started as soon as the VMs got Internet. Fix: role `base`.

**c) nginx kept showing its default page (Phase 3).** The config on disk was
right (`nginx -T`), the reload said *success*, the page was wrong. The answer
was in `/var/log/nginx/error.log`: `bind() to 10.0.2.7:80 failed`. Lesson:
*"success" from a reload is not proof — check the logs and the real behaviour*.

**d) The two LANs could talk without a tunnel (Phase 6 test).** The acceptance
test's `/whoami` returned `10.15.15.254` instead of `10.0.2.7`: someone was
translating. Following the packet (section 2): OPNsense A → its WAN gateway =
the laptop → the laptop has an address on LAN B → it forwarded and
masqueraded. Lesson: *a test that checks the exact expected value (not just
"ping works") finds problems you did not imagine*. Fix: a libvirt network filter
on the OPNsense WAN cards.

## 6. Commands to explore by yourself

```bash
# Layer 1 — virtual hardware
virsh -c qemu:///system list --all
virsh -c qemu:///system net-dumpxml infra-a-lan
virsh -c qemu:///system dumpxml a-web | less
ip -br addr show | grep virbr-i              # the bridges on your laptop

# Layer 3 — application (on a-web: ssh -i .secrets/infra_ed25519 infra@10.0.2.7)
sudo nginx -T | less
cat /etc/infra-app/config.php                # (sudo) where the DB password is
mysql -h 10.0.2.8 -u app -p                  # password: cat .secrets/mysql-app-a on the laptop

# Layer 4 — HA (on a-haproxy1 / a-haproxy2)
ip -br addr show lan0                        # who has 10.0.2.100?
sudo journalctl -u keepalived -n 30
sudo tcpdump -ni lan0 vrrp                   # the "I'm alive" messages
curl -s http://10.0.2.5:8404/stats\;csv | cut -d, -f1,2,18

# Ansible itself
.venv/bin/ansible-inventory -i inventories/common -i inventories/site_a --host a-web   # all variables of a-web
.venv/bin/ansible -i inventories/common -i inventories/site_a web -m ping
make phase3 SITE=a ARGS="--check --diff"     # what WOULD change, without changing it
```

## 7. Exercises — break it, predict, fix

Always: **predict** what will happen *before* you run it, then check. Write
your prediction down; being wrong is where you learn.

**Level 1 — observe**

1. Open `http://10.0.2.100/` and refresh 5 times. Which number changes? Which
   SQL statement changes it? (find it in `index.php`)
2. Find the three places the value `10.0.2.100` comes from in the code. (hint: `grep -rn vip`)
3. With `ansible-inventory --host a-haproxy2`, find its `keepalived_state` and
   compute its priority from `vrrp_priority`.
4. Run `make phase4 SITE=a` twice. Why is the second run `changed=0`?

**Level 2 — break and watch**

5. Run the curl loop from [docs/04](04-phase4-haproxy-keepalived.md) ("the demo"), then
   `sudo systemctl stop haproxy` on haproxy1. Predict: how many seconds until
   haproxy2 answers? Why longer than when you stop keepalived? (look at `chk_haproxy`)
6. On a-web: `sudo systemctl stop nginx`. Predict what `http://10.0.2.100/`
   returns, and what the stats page shows after ~6 s. Start nginx again.
7. On a-db: `sudo systemctl stop mysql`. What does the page show, and which
   HTTP code? (find the `catch` in `index.php`)
8. From a-haproxy1: `nc -v 10.0.2.8 3306`. Why is it refused although the
   network works? Which SQL line decides that?

**Level 3 — change the code (then `make phaseN` + `make test-phaseN`)**

9. Add a 4th message to [app.sql.j2](../roles/mysql/templates/app.sql.j2). Run
   `make phase3 SITE=a`. Why is the SQL re-applied this time and not the time before?
10. Make haproxy2 the MASTER by changing only the inventory. Run phase 4 and the
    test. What did you have to change, and why does the test still pass?
11. Change the health check to `GET /does-not-exist`. Predict, run `make phase4`,
    observe the stats page, then revert. Would `make test-phase4` catch it?
12. Break idempotence on purpose: add a task `ansible.builtin.command: date` to a
    role. What does the second run report? How do you fix it (`changed_when`)?

**Level 4 — the network (after Phase 6)**

13. While pinging `10.15.15.7` from a-web, run on the laptop
    `sudo tcpdump -ni virbr-iwan` and then `sudo tcpdump -ni virbr-ib icmp`.
    Explain the difference between the two outputs.
14. On OPNsense B, disable the IPsec ICMP rule. Predict: does the tunnel stay
    ESTABLISHED? Does the ping work? Re-enable it.
15. Change the Phase 2 ESP proposal on **one** side only. Which error appears in
    VPN → IPsec → Log File? Put it back.

## 8. Self-check — can you explain without notes?

- [ ] What is in each of the 5 VMs of a site, and its address?
- [ ] Journey 1, 2 and 3 of section 2.
- [ ] Why the VIP is not written in any VM's network config.
- [ ] What `make phase3 SITE=a` does, from the Makefile to the SSH connection.
- [ ] Where the MySQL password is created, stored, and used.
- [ ] Why 3306 is unreachable from the WAN (two independent reasons: OPNsense default deny, and MySQL's user is bound to the web IP).
- [ ] IKE vs ESP; Phase 1 vs Phase 2; tunnel vs transport mode; what PFS adds.
- [ ] Why we can prove "no NAT" with `/whoami`.
- [ ] One problem met during the project, how it was diagnosed, and the fix.
- [ ] What is **not** highly available in this design, and what you would add.

If you can tick all of them, you understand the project — you did not just run it.
