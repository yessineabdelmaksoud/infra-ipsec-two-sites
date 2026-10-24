# Infrastructure IT — VPN & Site-to-Site Interconnection

**Source:** OliveSoft, *Infrastructure IT — VPN & interconnexion de sites: SSL/TLS · IPsec · OPNsense*, October 2026 (19-page course/project PDF).

## 1. Project objective

Build two independent, equivalent IT sites and securely interconnect their private LANs with an **IPsec site-to-site VPN**, using **IKEv2 / ESP tunnel mode** between two **OPNsense** firewalls. The project is carried out by two students: **Student 1 builds Site A**, **Student 2 builds Site B**, and both collaborate on the IPsec tunnel and cross-site tests.

Each site runs a public-facing web service backed by MySQL, with a **Keepalived virtual IP (VIP)** and **two HAProxy nodes (MASTER/BACKUP)** for proxy failover. Internet visitors reach the service through OPNsense WAN NAT/port forwarding to the VIP. The LANs communicate over IPsec **without NAT between the LANs**.

## 2. Architecture and traffic flows

```text
     External client                                      External client
           |                                                    |
      TCP 80/443                                           TCP 80/443
           |                                                    |
    [OPNsense A WAN] ===== IPsec IKEv2 / ESP ===== [OPNsense B WAN]
           |                 tunnel mode                       |
    [OPNsense A LAN]                                     [OPNsense B LAN]
           |                                                    |
    VIP 10.0.2.100                                    VIP 10.15.15.100
           |                                                    |
   +----------------+                                 +----------------+
   | HAProxy MASTER |                                 | HAProxy MASTER |
   | HAProxy BACKUP |                                 | HAProxy BACKUP |
   | + Keepalived   |                                 | + Keepalived   |
   +----------------+                                 +----------------+
           |                                                    |
      Web server                                           Web server
           |                                                    |
         MySQL                                                MySQL

Site A LAN: 10.0.2.0/24                       Site B LAN: 10.15.15.0/24
```

**Public web request:** Internet client → OPNsense WAN (port 80/443 forward) → LAN VIP → active HAProxy → Nginx/Apache2 → MySQL.

**Inter-site request:** Site A LAN → OPNsense A → IPsec tunnel → OPNsense B → Site B LAN (and conversely); no translation between the LANs.

## 3. Required machines and IP addresses

The per-site implementation checklist specifies **one OPNsense and four application VMs**: HAProxy 1, HAProxy 2, web server, MySQL server. When OPNsense is virtualized, that is **five VMs per site**. One slide calls this “five VMs and one OPNsense,” while a later slide explicitly says “OPNsense and four VMs”; the machine inventory below is the concrete reference.

| Component | Purpose | Site A | Site B |
|---|---|---|---|
| LAN subnet | Private network | `10.0.2.0/24` | `10.15.15.0/24` |
| OPNsense WAN | Internet connectivity, NAT, IPsec | `192.168.x.x/24` | `192.168.x.x/24` |
| OPNsense LAN | Default gateway for all site VMs | `10.0.2.1/24` | `10.15.15.1/24` |
| Virtual IP (VIP) | Managed by Keepalived, owned by MASTER | `10.0.2.100/24` | `10.15.15.100/24` |
| HAProxy 1 | Keepalived MASTER | `10.0.2.5/24` | `10.15.15.10/24` |
| HAProxy 2 | Keepalived BACKUP | `10.0.2.6/24` | `10.15.15.11/24` |
| Web server | Nginx or Apache2 | `10.0.2.7/24` | `10.15.15.7/24` |
| Database | MySQL | `10.0.2.8/24` | `10.15.15.8/24` |

Addressing rules from the document:
- Use `/24` on every LAN interface (including `.10` and `.11`).
- Each VM's default gateway is its local OPNsense LAN interface.
- The VIP is **not** statically assigned to a VM; Keepalived moves it between HAProxy nodes.
- The two LAN subnets must not overlap.
- The proposed OPNsense LAN `.1` addresses are **to be confirmed during the lab**.
- WAN `192.168.x.x` is a placeholder, not a specific allocated peer address.

## 4. Required services and behaviors

### OPNsense
- Install one firewall/router per site, with WAN and LAN interfaces.
- Provide Internet access for LAN VMs.
- Forward WAN TCP 80/443 to the local VIP.
- Configure minimal and logged firewall rules for web access and the IPsec peer.
- Route protected inter-site subnet traffic through the IPsec tunnel; do not NAT between the two LANs.

### Web server and MySQL
- Install **Nginx or Apache2** and **MySQL** on separate VMs per site.
- Create a database and a database user permitted from the web server.
- The web page must actually display data from the database.
- MySQL listens as needed on the private network; **WAN access to TCP 3306 must be refused**.
- Example of the specified Site A verification: `mysql -h 10.0.2.8 -u app -p`, executed on the web server.

### HAProxy and Keepalived
- Install HAProxy and Keepalived on both proxy nodes per site.
- Configure MASTER/BACKUP ownership of the VIP with Keepalived/VRRP, including priority, `virtual_router_id`, and authentication as appropriate.
- Configure HAProxy `frontend`, `backend`, and health checks to send requests to the web server.
- On failure/stopping Keepalived on MASTER, BACKUP must take over the VIP and web access must remain available.

## 5. IPsec requirements

**VPN type:** IPsec site-to-site, **IKEv2**, **ESP**, **tunnel mode**. Each OPNsense uses the other firewall's WAN IP as its remote peer.

### Phase 1 — IKE SA

| Setting | Both peers |
|---|---|
| IKE version | IKEv2 |
| Authentication | Same pre-shared key (PSK) |
| Encryption/integrity | AES-256 / SHA-256 |
| Diffie–Hellman group | 14 (2048-bit) |
| Lifetime | 28,800 seconds |
| Remote peer | Other site's OPNsense WAN IP |

### Phase 2 — CHILD SA / ESP

| Setting | Site A | Site B |
|---|---|---|
| Local protected LAN | `10.0.2.0/24` | `10.15.15.0/24` |
| Remote protected LAN | `10.15.15.0/24` | `10.0.2.0/24` |
| ESP encryption | AES-256-GCM | AES-256-GCM |
| PFS | DH group 14 | DH group 14 |
| Lifetime | 3,600 seconds | 3,600 seconds |

**WAN protocols to allow:** UDP 500 (IKE), UDP 4500 (NAT traversal), and ESP (IP protocol 50 when no NAT is involved). Match both peers' crypto settings and PSK exactly; mirror local/remote networks. The document cites `NO_PROPOSAL_CHOSEN` as a typical mismatch error. IKE establishes the protected control association and the IPsec child associations; monitor status and dead-peer detection (DPD).

## 6. Six implementation stages (validate each before the next)

1. **Virtual networks and VMs.** Create WAN/LAN virtual networking, deploy the site's VMs and configure fixed addresses. **Test:** LAN VMs can ping one another.
2. **OPNsense.** Install and assign WAN/LAN interfaces, configure routing and LAN-side administration. **Test:** site VMs can access the Internet through OPNsense.
3. **Web and MySQL.** Install Nginx/Apache2, MySQL, application database and database user. **Test:** the web page displays data loaded from MySQL.
4. **Keepalived and HAProxy.** Configure active VIP failover and the proxy backend with health checks. **Test:** stop Keepalived on MASTER, then confirm VIP takeover by BACKUP.
5. **NAT and firewall.** Forward WAN ports 80/443 to the VIP and restrict unnecessary access. **Test:** access the web page from the OPNsense WAN IP.
6. **IPsec tunnel.** Collaboratively configure mirrored phase 1/phase 2 on the two firewalls and IPsec-interface firewall rules. **Test:** ping from `10.0.2.7` to `10.15.15.7` succeeds over IPsec.

Each student completes stages 1–5 for their own site. Both students agree on the addressing plan and IPsec settings and perform stage 6 together.

## 7. Six mandatory acceptance tests

| Test | Action | Expected result |
|---|---|---|
| Public web access | Open `http://IP_WAN_OPNsense` | Page served by web server |
| High availability | On current MASTER: `systemctl stop keepalived` | VIP moves to BACKUP; site stays accessible |
| Database | From Site A web VM: `mysql -h 10.0.2.8 -u app -p` | Database login succeeds |
| Database isolation | Attempt TCP 3306 from WAN | Connection refused/blocked |
| IPsec negotiation | OPNsense **VPN → IPsec → Status Overview** | Phase 1 and Phase 2 established |
| Inter-site connectivity | From `10.0.2.7`: `ping 10.15.15.7` | Replies received without NAT between LANs |

## 8. Required deliverables and presentation

1. Updated network diagram.
2. Final addressing plan.
3. XML configuration export from **each OPNsense**.
4. `keepalived.conf` and `haproxy.cfg` configuration files.
5. Report containing screenshots of all six acceptance tests.

**Final defense:** Both students demonstrate all six tests live across the two sites.

## 9. Course background included in the original PDF

This is explanatory material; the lab itself requires **IPsec**, not a separate SSL/OpenVPN deployment.

- **VPN fundamentals:** encryption over an untrusted network; confidentiality, integrity, peer authentication, replay prevention; encapsulation of private packets.
- **Site-to-site vs remote access:** site-to-site connects LANs through gateways; remote-access users commonly use a client VPN.
- **Cryptographic building blocks:** symmetric ciphers (AES-256, ChaCha20), public-key cryptography (RSA, ECDSA), Diffie–Hellman/ECDH key agreement, hashes/HMAC (SHA-256/SHA-384), X.509 certificates/CA/PKI, PFS, security associations (SAs), PSK.
- **TLS:** simplified TLS 1.2 ECDHE handshake (ClientHello, ServerHello/certificate, key agreement, Finished, protected traffic); TLS 1.3; certificate-chain checks (signatures, dates, server name, revocation); SSL/TLS for remote access, web portal vs OpenVPN client tunnel, TUN vs TAP, UDP 1194 or TCP 443.
- **IPsec:** AH (IP protocol 51, integrity/authentication without encryption) vs ESP (IP protocol 50, encryption/authentication/replay protection); transport vs tunnel mode; IKE/CHILD SAs, NAT-T and DPD.
- **Open-source firewalls:** OPNsense and pfSense are introduced in the course outline; the implementation specifically specifies OPNsense.

## 10. Unspecified matters / decisions for implementation

The source document does **not** mandate an OS for the application VMs, hypervisor, resource allocations, application framework or UI, service versions, or a mechanism for connecting two separate physical hosts' WAN networks. These are engineering choices, not source requirements. The document provides placeholder WAN addresses and says OPNsense LAN `.1` addresses require confirmation. Decide how the two WAN peers become reachable before attempting IPsec; document any environment-specific changes.

The documented failover protects the **HAProxy/Keepalived nodes**, not the single web server, MySQL server, or OPNsense per site. Do not claim full-stack high availability.
