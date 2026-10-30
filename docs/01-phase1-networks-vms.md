# 01 — Phase 1: virtual networks and VMs

**Goal (from the spec):** create the WAN/LAN networks, create the site's VMs with
fixed IP addresses. **Test:** the LAN VMs can ping each other.

**Status:** ✅ done — Site A and Site B (lab mode) pass `make test-phase1`.

## The picture

```text
                 Internet (your Wi-Fi)
                        |
                 [ your computer ]  does NAT for the WAN network
                        |
  infra-wan  192.168.100.0/24      <- "fake Internet" where the OPNsense WANs will live
     host = 192.168.100.1             (no VM on it yet; OPNsense comes in Phase 2)

  infra-a-lan  10.0.2.0/24         <- Site A private network (isolated switch)
     |          |          |          |          |
  haproxy1   haproxy2     web         db       your computer (.254, only to manage)
  10.0.2.5   10.0.2.6   10.0.2.7   10.0.2.8
```

- **2 virtual networks** per site: `infra-wan` (NAT → Internet) and `infra-a-lan` (isolated).
- **4 VMs**, Ubuntu 24.04, each with **one network card on the LAN**.
- Each VM's **gateway is `10.0.2.1`** = OPNsense. It does not exist yet, so
  in Phase 1 the VMs **cannot reach the Internet** — that is normal.
- Your computer has `.254` on the LAN only so Ansible can SSH into the VMs.
  It does **not** route traffic for them.

## Run it

```bash
make phase1 SITE=a          # build (takes ~1 minute the first time)
make test-phase1 SITE=a     # check
```

Run `make phase1` again: the summary shows `changed=0` → nothing to do, because
everything already matches the code (**idempotent**).

---

## How the code works (follow the data)

### 1. The addressing plan — one shared file

[inventories/common/group_vars/all.yml](../inventories/common/group_vars/all.yml)
is the plan **both students agree on**. Same file on both computers:

```yaml
sites:
  a:
    lan_cidr: 10.0.2.0/24
    lan_gateway: 10.0.2.1        # OPNsense LAN
    lan_host_ip: 10.0.2.254      # your computer's management address
    vip: 10.0.2.100
    wan_ip: 192.168.100.11       # OPNsense WAN
  b:
    lan_cidr: 10.15.15.0/24
    ...
```

### 2. What is different per site — very small

[inventories/site_a/group_vars/all.yml](../inventories/site_a/group_vars/all.yml):

```yaml
site_id: a          # "I am site a"
peer_site_id: b     # "the other site is b"
```

[inventories/site_a/hosts.yml](../inventories/site_a/hosts.yml) — the machines:

```yaml
haproxy:
  hosts:
    a-haproxy1: {ansible_host: 10.0.2.5, keepalived_state: MASTER}
    a-haproxy2: {ansible_host: 10.0.2.6, keepalived_state: BACKUP}
web:
  hosts:
    a-web: {ansible_host: 10.0.2.7}
db:
  hosts:
    a-db: {ansible_host: 10.0.2.8}
```

The Makefile gives Ansible **both** folders: `-i inventories/common -i inventories/site_a`.
For Site B it is `site_b` instead. That's the whole trick of "shared code + site config".

### 3. The playbook — the "recipe"

[playbooks/phase1.yml](../playbooks/phase1.yml) says, in order:

1. prepare the hypervisor (role `hypervisor`): storage folder + Ubuntu image;
2. create the networks (role `libvirt_network`);
3. create each VM (role `libvirt_vm`, once per machine);
4. wait until each VM answers on SSH and cloud-init has finished.

```yaml
- name: WAN and LAN networks
  ansible.builtin.include_role:
    name: libvirt_network
  vars:
    libvirt_networks:
      - name: "{{ wan_network_name }}"     # infra-wan
        host_ip: "{{ site.wan_host_ip }}"  # 192.168.100.1
        forward: nat                        # = has an exit to the Internet
      - name: "{{ lan_network_name }}"     # infra-a-lan
        host_ip: "{{ site.lan_host_ip }}"  # 10.0.2.254
                                            # no "forward" = isolated
```

`{{ ... }}` is a **variable** (Jinja2 syntax). Ansible replaces it with the value
from the inventory. `site` means `sites[site_id]`, so for Site A it's `sites.a`.

### 4. A network = a small XML file

libvirt describes everything in XML. Template
[roles/libvirt_network/templates/network.xml.j2](../roles/libvirt_network/templates/network.xml.j2):

```xml
<network>
  <name>{{ net.name }}</name>
  <bridge name='{{ net.bridge }}' stp='off' delay='0'/>
{% if net.forward is defined %}
  <forward mode='{{ net.forward }}'/>     <!-- only for the WAN: NAT -->
{% endif %}
  <dns enable='no'/>                      <!-- no DHCP, no DNS: everything is static -->
  <ip address='{{ net.host_ip }}' prefix='{{ net.prefix }}'/>
</network>
```

See the result: `virsh -c qemu:///system net-dumpxml infra-a-lan`.

### 5. A VM = disk + "first boot instructions" + XML

The role [roles/libvirt_vm](../roles/libvirt_vm/tasks/main.yml) does 3 things per VM.

**a) The disk — an overlay.** All VMs share one Ubuntu image (600 MB). Each VM
gets a small file that only stores *its own changes*:

```bash
virsh vol-create-as infra a-web.qcow2 10G --format qcow2 \
      --backing-vol ubuntu-24.04-20261017-base.qcow2 --backing-vol-format qcow2
```

**b) The first-boot instructions — cloud-init.** We put 3 small files on a fake
CD (`seed.iso`). At first boot Ubuntu reads them. The network part
([network-config.j2](../roles/libvirt_vm/templates/network-config.j2)) rendered for `a-web`:

```yaml
version: 2
ethernets:
  lan0:
    match:
      macaddress: "52:54:00:00:02:07"   # find the card by its MAC address
    set-name: lan0                      # call it lan0
    addresses: ["10.0.2.7/24"]          # fixed IP, /24
    routes:
      - to: default
        via: 10.0.2.1                   # gateway = OPNsense
    nameservers:
      addresses: [10.0.2.1]             # DNS = OPNsense
```

> **Trick:** the MAC address is built from the IP (`10.0.2.7` → `...:00:02:07`).
> So it is always the same and never collides between sites.

The user part ([user-data.j2](../roles/libvirt_vm/templates/user-data.j2)) creates
the user `infra` with our SSH key and passwordless `sudo` (needed by Ansible).

**c) The VM description — domain XML** ([domain.xml.j2](../roles/libvirt_vm/templates/domain.xml.j2)):

```xml
<domain type='kvm'>
  <name>{{ vm.name }}</name>
  <memory unit='MiB'>{{ vm.memory_mb }}</memory>        <!-- 512, 768 or 1024 -->
  <disk type='file' device='disk'>
    <source file='/var/lib/libvirt/images/infra/{{ vm.name }}.qcow2'/>
  </disk>
  <interface type='network'>
    <source network='infra-a-lan'/>                      <!-- plug into the LAN switch -->
    <mac address='52:54:00:00:02:07'/>
  </interface>
  <console type='pty'/>                                  <!-- for virsh console -->
</domain>
```

> **Problem we hit:** first we wrote `<disk type='volume'>` (point to a libvirt
> volume by name). AppArmor builds a list of files each VM may open, but its
> helper doesn't understand "volume" → the base image was not in the list →
> *Permission denied*. Fix: point to the **file path** (`type='file'`).

### 6. The test

[tests/phase1.yml](../tests/phase1.yml) logs into each VM and checks:

```yaml
- name: Address is exactly the planned /24, gateway is OPNsense LAN, VIP absent
  ansible.builtin.assert:
    that:
      - addrs[0].local == ansible_host          # IP is the planned one
      - addrs[0].prefixlen == 24                # mask is /24
      - routes[0].gateway == site.lan_gateway   # gateway is 10.0.2.1
      - site.vip not in addrs | map(attribute='local')   # VIP not fixed on a VM

- name: Ping every other LAN VM
  ansible.builtin.command: ping -c 2 -W 2 {{ hostvars[item].ansible_host }}
  loop: "{{ groups['linux_vms'] | difference([inventory_hostname]) }}"
```

`loop` = repeat for each item. `difference([me])` = everybody except me.
4 VMs × 3 others = 12 pings.

---

## Check by hand (good for the report)

```bash
virsh -c qemu:///system list --all
#  Id   Name         State
#  1    a-haproxy1   running
#  ...

ssh -i .secrets/infra_ed25519 infra@10.0.2.7     # log into a-web
ip -br addr          # lan0  UP  10.0.2.7/24
ip route             # default via 10.0.2.1 dev lan0
ping -c 3 10.0.2.8   # a-db answers
ping -c 3 1.1.1.1    # fails for now: OPNsense (10.0.2.1) does not exist yet
exit
```

Extra checks we did:

| Check | Result | Why it matters |
|---|---|---|
| From `a-web`, `ping 10.15.15.7` (Site B) | fails ✅ | In Phase 6, a successful ping can **only** come from the IPsec tunnel |
| From `a-web`, `ping 1.1.1.1` | fails ✅ | Internet must go through OPNsense (Phase 2) |
| `make phase1 SITE=b` (without `MODE=lab`) on this computer | refused ✅ | Protects the shared WAN network from a wrong config |

## Useful commands if something breaks

```bash
virsh -c qemu:///system console a-web     # see the boot messages; exit with Ctrl + ]
                                          # login: infra / password in .secrets/vm_console_password
make destroy SITE=a && make phase1 SITE=a # rebuild the site from zero
make phase1 SITE=a ARGS="-v"              # more details from Ansible
```
