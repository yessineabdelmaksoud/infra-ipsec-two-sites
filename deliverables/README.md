# Deliverables (spec §8)

| # | Deliverable | File | Produced by |
|---|---|---|---|
| 1 | Updated network diagram | [network-diagram.svg](network-diagram.svg) · [png](network-diagram.png) | drawn by hand (re-export PNG: `rsvg-convert -w 2240 network-diagram.svg -o network-diagram.png`) |
| 2 | Final addressing plan | [addressing-plan.md](addressing-plan.md) | `make deliverables` (from the shared inventory) |
| 3 | OPNsense XML export, each site | `site_a/a-opnsense-config.redacted.xml`, `site_b/b-opnsense-config.redacted.xml` | `make opnsense-backup` + `make deliverables` |
| 4 | `keepalived.conf` and `haproxy.cfg` | `site_a/a-haproxy1/`, `site_a/a-haproxy2/`, `site_b/...` | `make deliverables` (fetched from the VMs) |
| 5 | Report with screenshots of the six tests | `site_a/acceptance-report.md`, `site_b/...` + the written report ([template](../docs/report-template.md)) | `make acceptance` + screenshots |

Run on each computer:

```bash
make opnsense-backup SITE=a     # Student 2: SITE=b
make deliverables SITE=a
make acceptance SITE=a
```

Secrets are replaced by `REDACTED` in every file here (password hashes, private
keys, IPsec PSK, VRRP password). The unredacted originals stay in `.secrets/`.
