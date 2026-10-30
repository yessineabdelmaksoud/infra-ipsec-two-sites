# Entry points. Usage: make <target> SITE=a|b [MODE=lab|distributed]
#   lab          both sites run on this computer and share one WAN bridge
#   distributed  one site per computer, WAN bridges joined by cable/overlay (default)
SITE ?= a
MODE ?= distributed

VENV      := .venv
ANSIBLE   := $(VENV)/bin/ansible-playbook
INVENTORY := -i inventories/common -i inventories/site_$(SITE)
EXTRA     := -e deployment_mode=$(MODE)
ARGS      ?=
# Group membership granted by the bootstrap only applies to new logins; sg makes
# it effective immediately for the libvirt socket.
RUN       := $(if $(shell id -nG | grep -qw libvirt && echo y),sh -c,sg libvirt -c)
PLAY       = $(RUN) "$(ANSIBLE) $(INVENTORY) $(EXTRA) $(ARGS) $(1)"

.PHONY: help setup phase1 test-phase1 phase2 test-phase2 opnsense-rebuild opnsense-backup phase3 test-phase3 \
        phase4 test-phase4 test-phase5 ipsec-psk test-phase6 acceptance deliverables all status up down destroy

help:
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

setup: ## Create the pinned Ansible toolchain and the lab SSH key (no sudo)
	python3 -m venv --system-site-packages $(VENV)
	$(VENV)/bin/pip install --quiet --upgrade pip
	$(VENV)/bin/pip install --quiet -r requirements.txt
	install -d -m 700 .secrets
	test -f .secrets/infra_ed25519 || ssh-keygen -q -t ed25519 -N '' -C infra-lab -f .secrets/infra_ed25519

phase1: ## Phase 1: WAN/LAN networks and the four application VMs
	$(call PLAY,playbooks/phase1.yml)

test-phase1: ## Validate Phase 1: addressing and LAN ping mesh
	$(call PLAY,tests/phase1.yml)

phase2: ## Phase 2: OPNsense VM + console bootstrap (then web UI: docs/02-phase2-opnsense.md)
	$(call PLAY,playbooks/phase2.yml)

test-phase2: ## Validate Phase 2: Internet and DNS through OPNsense, UI closed on WAN
	$(call PLAY,tests/phase2.yml)

opnsense-rebuild: ## Recreate the OPNsense disk from the image (if it no longer boots after a hard power-off)
	$(call PLAY,playbooks/phase2.yml -e opnsense_rebuild=true)

opnsense-backup: ## Copy OPNsense config.xml to .secrets/opnsense/ (needs SSH enabled in the UI)
	$(call PLAY,playbooks/opnsense-backup.yml)

phase3: ## Phase 3: MySQL + Nginx/PHP page reading the database
	$(call PLAY,playbooks/phase3.yml)

test-phase3: ## Validate Phase 3: page shows DB data, app user only from the web VM
	$(call PLAY,tests/phase3.yml)

phase4: ## Phase 4: HAProxy + Keepalived (VIP) on the two proxy nodes
	$(call PLAY,playbooks/phase4.yml)

test-phase4: ## Validate Phase 4: VIP failover (stops keepalived/haproxy on MASTER, then restores)
	$(call PLAY,tests/phase4.yml)

test-phase5: ## Validate Phase 5 (web UI steps: docs/05): web via WAN, 3306/22/stats blocked
	$(call PLAY,tests/phase5.yml)

ipsec-psk: ## Create the shared IPsec pre-shared key once (then copy it to the other student)
	@install -d -m 700 .secrets
	@test -f .secrets/ipsec-psk || (openssl rand -base64 32 | tr -d '\n' > .secrets/ipsec-psk && chmod 600 .secrets/ipsec-psk)
	@echo "PSK file: .secrets/ipsec-psk (give the same file to the other site, never commit it)"

test-phase6: ## Validate Phase 6 (web UI steps: docs/06): tunnel up, ping peer LAN, no NAT
	$(call PLAY,tests/phase6.yml)

acceptance: ## The six acceptance tests of the spec, with a report in deliverables/
	$(call PLAY,tests/acceptance.yml)

deliverables: ## Collect keepalived.conf, haproxy.cfg and the redacted OPNsense XML into deliverables/
	$(call PLAY,playbooks/deliverables.yml)

all: phase1 phase2 phase3 phase4 ## Build every automated part of SITE (phases 1-4)

status: ## One-screen health view: VMs, VIP holder, web via VIP and WAN, tunnel (read-only)
	$(call PLAY,playbooks/status.yml)

up: ## Start every VM of SITE (after a reboot of the computer, for example)
	$(call PLAY,playbooks/power.yml -e power=up)

down: ## Shut down every VM of SITE cleanly (frees the RAM, keeps the disks)
	$(call PLAY,playbooks/power.yml -e power=down)

destroy: ## Remove the VMs, disks and LAN network of SITE (keeps base image and WAN)
	$(call PLAY,playbooks/destroy.yml)
