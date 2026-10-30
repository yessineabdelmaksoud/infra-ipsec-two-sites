# 04 — Phase 4: HAProxy + Keepalived (the VIP)

**Goal (from the spec):** two proxy nodes, MASTER and BACKUP; Keepalived (VRRP)
moves a **virtual IP** between them; HAProxy sends requests to the web server
with health checks. **Test:** stop Keepalived on the MASTER → the BACKUP takes the
VIP and the site stays available.

**Status:** ✅ done — Site A and Site B (lab mode) pass `make test-phase4`
(VIP moves in ~1 s when keepalived stops, ~4 s when haproxy stops).

## The picture

```text
                        VIP 10.0.2.100   ← the only address clients (and OPNsense) use
                     ┌────────┴────────┐
             owns it now           takes it if the MASTER fails
        a-haproxy1 10.0.2.5      a-haproxy2 10.0.2.6
        Keepalived MASTER 150    Keepalived BACKUP 100
        HAProxy                  HAProxy
             └──── VRRP "I am alive" every 1 s (unicast) ────┘
                     │                 │
                     └──── HTTP ───────┘──▶ a-web 10.0.2.7  (health check GET /health every 2 s)
```

| Word | Simple meaning |
|---|---|
| **VIP** | An IP address that belongs to no machine in particular: whoever is MASTER adds it to its network card |
| **VRRP** | The protocol Keepalived speaks. The MASTER says "I'm alive, priority 150" every second. If the BACKUP hears nothing for ~3 s, it becomes MASTER and adds the VIP |
| **Priority / preemption** | Highest priority wins. When haproxy1 comes back (150 > 100), it takes the VIP back |
| **HAProxy** | A reverse proxy / load balancer: receives HTTP on the VIP and forwards it to the web server(s) that pass the health check |
| **Health check** | HAProxy asks `GET /health` every 2 s. 3 failures → server DOWN (not used), 2 successes → UP again |
| **track_script** | Keepalived also checks that *haproxy* runs. If haproxy dies, the node gives the VIP away even though Keepalived itself is fine |

> Honest limit (spec §10): this protects the **proxy layer only**. There is a
> single web server, a single MySQL and a single OPNsense per site.

## Run it

```bash
make phase4 SITE=a
make test-phase4 SITE=a     # really stops keepalived, then haproxy, on the MASTER — and restores them
```

---

## How the code works

[playbooks/phase4.yml](../playbooks/phase4.yml):

1. On your computer: makes a **self-signed certificate** for HTTPS once
   (`.secrets/tls/site-a.pem`, valid for the WAN address `192.168.100.11` and the VIP).
2. On both proxy nodes: roles [haproxy](../roles/haproxy/tasks/main.yml) then
   [keepalived](../roles/keepalived/tasks/main.yml).

Who is MASTER comes from the inventory ([inventories/site_a/hosts.yml](../inventories/site_a/hosts.yml)):

```yaml
a-haproxy1: {ansible_host: 10.0.2.5, keepalived_state: MASTER}
a-haproxy2: {ansible_host: 10.0.2.6, keepalived_state: BACKUP}
```

### keepalived.conf (as generated on a-haproxy1)

Template: [keepalived.conf.j2](../roles/keepalived/templates/keepalived.conf.j2)

```text
vrrp_script chk_haproxy {
    script "/usr/bin/systemctl is-active --quiet haproxy"   # is haproxy running?
    interval 2
    fall 2
    rise 2
}

vrrp_instance VI_SITE_A {
    state MASTER
    interface lan0
    virtual_router_id 51        # Site A = 51, Site B = 52 (must differ per group)
    priority 150                # BACKUP has 100
    advert_int 1                # advertisement every second
    unicast_src_ip 10.0.2.5
    unicast_peer {
        10.0.2.6
    }
    authentication {
        auth_type PASS
        auth_pass ********      # random, in .secrets/vrrp-a (only 8 characters count)
    }
    virtual_ipaddress {
        10.0.2.100/24 dev lan0  # /24 like every LAN address
    }
    track_script {
        chk_haproxy
    }
}
```

Why **unicast**? By default VRRP uses multicast. Unicast (the two nodes talk
directly) is simpler to see in `tcpdump` and does not depend on multicast working
on the virtual switch.

### haproxy.cfg

Template: [haproxy.cfg.j2](../roles/haproxy/templates/haproxy.cfg.j2)

```text
frontend fe_web
    bind 10.0.2.100:80                                  # listen on the VIP
    bind 10.0.2.100:443 ssl crt /etc/haproxy/certs/site.pem
    http-request  set-header X-Proxy-Node a-haproxy1    # tell the page who forwarded
    http-response set-header X-Proxy-Node a-haproxy1
    default_backend be_web

backend be_web
    option httpchk
    http-check send meth GET uri /health
    http-check expect status 200
    server a-web 10.0.2.7:80 check inter 2s fall 3 rise 2

listen stats
    bind 10.0.2.5:8404                                   # http://10.0.2.5:8404/stats (LAN only)
    stats enable
    stats uri /stats
```

**The trick:** both nodes `bind 10.0.2.100`, but only the MASTER has that
address. Normally Linux refuses to bind an address the machine doesn't own; the
role sets `net.ipv4.ip_nonlocal_bind = 1` so HAProxy runs **all the time on
both nodes**. At failover, Keepalived only moves the address — HAProxy needs no restart.

`option forwardfor` adds the `X-Forwarded-For` header, so the web page can show
the **real client address** and not the proxy's.

### Same file on both nodes?

Yes, except the node name in `X-Proxy-Node` and the stats address. HAProxy and
the certificate must be identical so the BACKUP serves exactly the same site.

---

## The test, explained

[tests/phase4.yml](../tests/phase4.yml) + [tests/tasks/failover.yml](../tests/tasks/failover.yml):

1. VIP is on a-haproxy1 **only** (`ip -4 addr show dev lan0` on both).
2. `http://10.0.2.100/` and `https://10.0.2.100/` return the database page, header `X-Proxy-Node: a-haproxy1`.
3. HAProxy's stats CSV shows `be_web,a-web,...,UP`.
4. **Scenario keepalived** (= acceptance test 2): `systemctl stop keepalived` on
   haproxy1 → wait until haproxy2 has the VIP → the page now says
   `a-haproxy2` → `systemctl start keepalived` → VIP back on haproxy1.
5. **Scenario haproxy**: same, but stopping `haproxy` (the `track_script` must
   notice it in ~4 s).

The services are restarted in an `always:` block, so the site is left healthy
even if a check fails in the middle.

## Check by hand — the demo you will do at the defense

Terminal 1 — watch the page, one request per second:

```bash
while true; do curl -s -m 2 http://10.0.2.100/ | grep -o 'id="proxy">[^<]*'; sleep 1; done
# id="proxy">a-haproxy1
# id="proxy">a-haproxy1 ...
```

Terminal 2 — break the MASTER:

```bash
ssh -i .secrets/infra_ed25519 infra@10.0.2.5 'sudo systemctl stop keepalived'
#   terminal 1 switches to:  id="proxy">a-haproxy2   (0 or 1 lost request)
ssh -i .secrets/infra_ed25519 infra@10.0.2.6 'ip -br addr show lan0'
#   lan0  UP  10.0.2.6/24 10.0.2.100/24        ← the VIP is on the BACKUP
ssh -i .secrets/infra_ed25519 infra@10.0.2.5 'sudo systemctl start keepalived'
#   terminal 1 switches back to a-haproxy1
```

See the VRRP adverts: `ssh ... infra@10.0.2.6 'sudo tcpdump -ni lan0 vrrp'`
and the logs: `sudo journalctl -u keepalived -f` (lines *Entering MASTER STATE* / *Entering BACKUP STATE*).

## If something goes wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| VIP on **both** nodes | the nodes don't hear each other (firewall, wrong `unicast_peer`, different `auth_pass`) | `sudo tcpdump -ni lan0 vrrp` on both; re-run `make phase4` |
| VIP on **no** node | haproxy is down on both (`track_script` → FAULT) | `systemctl status haproxy`; `haproxy -c -f /etc/haproxy/haproxy.cfg` |
| HAProxy returns 503 | web server DOWN in the health check | `curl http://10.0.2.7/health`; stats page `http://10.0.2.5:8404/stats` |
| Site B nodes steal Site A's VIP | same `virtual_router_id` in the same LAN | ids are 51 and 52 in `inventories/common/group_vars/all.yml` |
