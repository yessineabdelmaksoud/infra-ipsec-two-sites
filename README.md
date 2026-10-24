# Infrastructure IT — two sites + IPsec, as code

Spec: [INFRASTRUCTURE_IT_PROJECT.md](INFRASTRUCTURE_IT_PROJECT.md) · Plan and status: [PLAN.md](PLAN.md)

Same repository on both computers. Student 1 deploys `SITE=a`, Student 2 deploys `SITE=b`.
The shared addressing plan is in `inventories/common/group_vars/all.yml` — keep it identical on both sides.

## Quick start (per computer)

```bash
sudo ./scripts/bootstrap-host.sh      # once: KVM/libvirt, groups, Docker coexistence
make setup                            # pinned Ansible in .venv + lab SSH key (no sudo)
make phase1 SITE=a                    # networks + 4 application VMs
make test-phase1 SITE=a               # validation
```

Both sites on one computer (rehearsal): add `MODE=lab` to every Site B command.

Other targets: `make help`. Extra Ansible options: `ARGS="-e foo=bar -v"`.
Remove a site: `make destroy SITE=a` (`ARGS="-e destroy_wan=true"` also drops the WAN network).

Debug a VM: `virsh -c qemu:///system console a-web` (user `infra`, password in
`.secrets/vm_console_password`), or `ssh -i .secrets/infra_ed25519 infra@10.0.2.7`.
