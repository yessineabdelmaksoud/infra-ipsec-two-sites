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

.PHONY: help setup phase1 test-phase1 destroy

help:
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

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

destroy: ## Remove the VMs, disks and LAN network of SITE (keeps base image and WAN)
	$(call PLAY,playbooks/destroy.yml)
