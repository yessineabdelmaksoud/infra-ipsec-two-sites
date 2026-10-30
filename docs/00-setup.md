# 00 — Setup of the computer (once per computer)

**Goal:** install the tools that create and manage VMs, and the IaC tool (Ansible).
Both students do this on their own computer.

## Step 1 — the part that needs `sudo`

```bash
cd ~/I3/infra
sudo ./scripts/bootstrap-host.sh
```

What the script does (file [scripts/bootstrap-host.sh](../scripts/bootstrap-host.sh)):

```bash
apt-get install -y ... qemu-system-x86 libvirt-daemon-system virtinst python3-libvirt ...
usermod -aG libvirt,kvm "$TARGET_USER"
```

- installs **QEMU/KVM** (runs VMs) and **libvirt** (manages them);
- adds you to the `libvirt` group → you can manage VMs **without sudo** afterwards;
- installs a small "hook" so **Docker does not block the VM networks** (see below).
- tells libvirt to **shut the VMs down cleanly** when the computer shuts down
  (a killed OPNsense VM may not boot again — see [08-troubleshooting](08-troubleshooting.md)).
  *Bootstrapped before 2026-10-30? Run the script once more to get this.*

### Why the Docker hook?

Docker sets the Linux firewall rule *"by default, drop packets that are forwarded
between networks"*. Our VMs need their packets forwarded (to go to the Internet).
So the hook adds two "accept" rules for our bridges (all named `virbr-i...`):

```sh
iptables -I DOCKER-USER -i virbr-i+ -j ACCEPT   # packets coming from our bridges
iptables -I DOCKER-USER -o virbr-i+ -j ACCEPT   # packets going to our bridges
```

`virbr-i+` means "any interface whose name starts with `virbr-i`".

> **Problem we hit:** at first the helper was in `/usr/local/sbin/`. Ubuntu's
> security system **AppArmor** only allows libvirt hooks to run programs from
> `/etc/libvirt/hooks/` (and `/usr/sbin/`), so it failed with *Permission denied*.
> Fix: the helper now lives in `/etc/libvirt/hooks/lib/`. Lesson: when a root
> process gets *Permission denied* on Ubuntu, think **AppArmor**.

## Step 2 — the part without `sudo`

```bash
make setup
```

What it does ([Makefile](../Makefile)):

```make
setup:
	python3 -m venv --system-site-packages .venv          # private Python folder
	.venv/bin/pip install -r requirements.txt             # exact Ansible version
	ssh-keygen -t ed25519 -N '' -f .secrets/infra_ed25519 # key to log into the VMs
```

- **`.venv`** = a private Python install inside the project. Both computers get
  the **exact same Ansible version** from [requirements.txt](../requirements.txt):
  ```text
  ansible==14.5.0        # Ansible + its collections (libvirt, mysql, ...)
  ansible-core==2.21.5
  ```
- **`.secrets/`** holds the SSH key and generated passwords. It is in `.gitignore`
  → **never** pushed to git.

## Check that it worked

```bash
virsh -c qemu:///system uri           # → qemu:///system
.venv/bin/ansible --version           # → ansible [core 2.21.5]
ls .secrets/                          # → infra_ed25519  infra_ed25519.pub
```

## What is in the repository

```text
Makefile                  the buttons: make setup, make phase1, make test-phase1 ...
ansible.cfg               Ansible settings (SSH user "infra", key, ...)
inventories/common/       values shared by both sites (the addressing plan)
inventories/site_a/       only Site A's machines
inventories/site_b/       only Site B's machines
playbooks/                one playbook per phase (what to build)
roles/                    reusable building blocks (how to build)
tests/                    one test playbook per phase (how to check)
docs/                     these pages
.secrets/ .cache/ .venv/  local only, not in git
```
