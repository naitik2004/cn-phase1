# CN Phase 2 Report — Team Climber

## 1. What Changed from Phase 1

Phase 2 extends the Phase 1 Docker Compose stack on the same macOS host without rebuilding from scratch:

| Component | Phase 1 | Phase 2 Extension |
| :--- | :--- | :--- |
| DNS | Single `cn-dns` (`172.30.0.10`, `local-ttl=60`) | Added backup `cn-dns2` (`172.30.0.15`), caching forwarder `cn-dns-cache` (`172.30.0.16`), and dual-resolver `cn-client` (`172.30.0.20`) |
| Network | Single bridge `cnnet` (`172.30.0.0/24`) | Added internal `backend-net` (`172.31.0.0/24`, `internal: true`); backends isolated from `cnnet` |
| Edge / LB | Single `cn-edge` (`172.30.0.11`) | Added passive health checks (`max_fails=2 fail_timeout=10s`, `proxy_next_upstream`), `X-Edge: edge1`, and standby `cn-edge2` (`172.30.0.14`, `X-Edge: edge2`) |
| Diagnostics | Manual `dig` / `curl` checks | Added 5-layer `scripts/diagnose.sh` and [TROUBLESHOOTING.md](file:///Users/sahilchand/cn-phase1/TROUBLESHOOTING.md) |

---

## 2. Extensions A–F: Implementation, Results & Learning Summaries

### Extension A — Backup DNS Resolver
- **Built:** Added [dns/dnsmasq-backup.conf](file:///Users/sahilchand/cn-phase1/dns/dnsmasq-backup.conf) (`cn-dns2` at `172.30.0.15`) with the same `app.team1.test -> 172.30.0.11` record, plus `cn-client` (`172.30.0.20`) with [client/resolv.conf](file:///Users/sahilchand/cn-phase1/client/resolv.conf) listing `172.30.0.10` then `172.30.0.15` (`options timeout:1 attempts:1`).
- **Test Results:** In [backup-dns-failover.txt](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-A/backup-dns-failover.txt), `dig app.team1.test` normally answered from `172.30.0.10#53`. After `docker compose stop dns`, `dig` timed out on `172.30.0.10` and immediately resolved `172.30.0.11` from `172.30.0.15#53`, and `curl --cacert /certs/app.crt https://app.team1.test/api/status` returned `HTTP/2 200`. Restarting `dns` restored primary resolution.
- **Learning Summary:** Redundant DNS separates name-resolution availability from application availability: if all DNS servers fail, clients cannot even discover the edge IP even when the web tier is healthy, whereas an application outage leaves DNS resolution intact and surfaces as an HTTP/proxy error. Adding a secondary resolver with short client timeouts eliminates DNS as a single point of failure.

### Extension B — DNS TTL and Controlled Record Change
- **Built:** Added [dns/dnsmasq-cache.conf](file:///Users/sahilchand/cn-phase1/dns/dnsmasq-cache.conf) (`cn-dns-cache` at `172.30.0.16`, `cache-size=1000`) forwarding to `172.30.0.10` and `172.30.0.15`, and tested with `local-ttl=30`.
- **Test Results:** In [ttl-and-cache-demo.txt](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-B/ttl-and-cache-demo.txt), after changing authoritative `dns`/`dns2` to `172.30.0.99`, `cn-dns-cache` continued serving `172.30.0.11` while the TTL counted down (`30 -> 21 -> 13 -> 4`), then switched to `172.30.0.99` after TTL expiry. Restoring `172.30.0.11` on `dns`/`dns2` left `172.30.0.99` cached until `docker compose restart dns-cache` flushed the cache and immediately returned `172.30.0.11`. Original record (`172.30.0.11`) and `local-ttl=60` were restored afterwards.
- **Learning Summary:** DNS TTL governs how long recursive resolvers cache an answer and therefore bounds how fast a DNS-based IP change propagates. In production, operators lower TTLs well ahead of a migration because they cannot flush third-party ISP caches, and keep both old and new endpoints running until the old TTL window drains.

### Extension C — Service Isolation
- **Built:** Saved pre-isolation rollback copies in [04-evidence/05-phase2/ext-C/rollback/](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-C/rollback/), added `backend-net` (`172.31.0.0/24`, `internal: true`), moved `backend-a` (`172.31.0.12:3001`) and `backend-b` (`172.31.0.13:3002`) exclusively onto `backend-net`, and dual-homed `cn-edge` on `cnnet` and `backend-net`.
- **Test Results:** In [isolation-test.txt](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-C/isolation-test.txt), `cn-edge` reached both backends directly (`{"backend": "A", "status": "ok"}`, `{"backend": "B", "status": "ok"}`), `cn-client` timed out on `172.31.0.12:3001` (`3007 ms`) and `172.31.0.13:3002` (`3008 ms`), and `https://app.team1.test/api/status` still alternated `A`/`B` with `HTTP/2 200`. Rollback and re-isolation were verified in [rollback-and-restore.txt](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-C/rollback-and-restore.txt).
- **Learning Summary:** Placing application backends on an internal network ensures all client traffic must traverse the TLS-terminating reverse proxy rather than bypassing security controls or hitting unencrypted HTTP ports directly. Testing both allowed (`edge -> backend`) and denied (`client -> backend`) paths plus rollback guarantees the policy works without breaking end-user access.

### Extension D — HA Failover Behavior
- **Built:** Saved [nginx.pre-ext-D.conf](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-D/nginx.pre-ext-D.conf) and updated [edge/nginx.conf](file:///Users/sahilchand/cn-phase1/edge/nginx.conf) with `max_fails=2 fail_timeout=10s`, `proxy_connect_timeout 2s`, `proxy_next_upstream error timeout http_502 http_503 http_504`, and `proxy_next_upstream_tries 2`.
- **Test Results:** In [ha-failover-test.txt](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-D/ha-failover-test.txt), stopping `backend-a` kept all 10 requests returning `HTTP 200` from `B` (requests 1 and 3 took `2.028s` while `proxy_connect_timeout 2s` tripped `max_fails=2`; requests 4–10 completed in `~0.004s`). After restarting `backend-a` and waiting `11s`, round-robin resumed. Stopping both backends produced `HTTP/2 502` after the TLSv1.3 handshake completed. Remaining edge SPOF notes are in [spof-and-health-check-notes.md](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-D/spof-and-health-check-notes.md).
- **Learning Summary:** Passive health checks (`max_fails` + `fail_timeout` + `proxy_next_upstream`) let open-source Nginx mask single-backend failures transparently at the cost of a bounded connect-timeout penalty on the failing probes. However, a single Nginx edge remains a single point of failure unless paired with VRRP/`keepalived`, DNS failover, or a cloud load balancer.

### Extension E — Controlled Edge Migration (DNS Cutover)
- **Built:** Added standby `cn-edge2` (`172.30.0.14` on `cnnet`, `172.31.0.14` on `backend-net`) using [edge/nginx-edge2.conf](file:///Users/sahilchand/cn-phase1/edge/nginx-edge2.conf) (`X-Edge: edge2`) and added `X-Edge: edge1` to [edge/nginx.conf](file:///Users/sahilchand/cn-phase1/edge/nginx.conf), sharing `/certs/app.crt` (`SAN=DNS:app.team1.test`). Rollback copies saved in [04-evidence/05-phase2/ext-E/rollback/](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-E/rollback/).
- **Test Results:** In [edge-migration-cutover.txt](file:///Users/sahilchand/cn-phase1/04-evidence/05-phase2/ext-E/edge-migration-cutover.txt), cutting DNS from `172.30.0.11` to `172.30.0.14` with `local-ttl=30` kept cached clients on `edge1` (`TTL 18`, `TTL 8`) until expiry at `~32s`, when traffic shifted to `edge2`. Flushing `dns-cache` caused an immediate cutover, and stopping `edge1` after cutover left the service operational via `edge2` (`HTTP/2 200`). Rolled back to `172.30.0.11`, `TTL=60`, `edge1` primary and `edge2` standby.
- **Learning Summary:** DNS cutover enables zero-downtime edge replacement or failover when both edges share the same TLS certificate SAN and backend network, but it is **not** instantaneous failover because cached clients follow the old IP until TTL expiration.

### Extension F — Troubleshooting Challenge Prep
- **Built:** Created 5-layer [scripts/diagnose.sh](file:///Users/sahilchand/cn-phase1/scripts/diagnose.sh) (`DNS -> IP -> TCP -> TLS -> HTTP`) and [TROUBLESHOOTING.md](file:///Users/sahilchand/cn-phase1/TROUBLESHOOTING.md).
- **Test Results:** Rehearsed 7 faults in `04-evidence/05-phase2/ext-F/` (`00-baseline-pass.txt` through `08-final-clean-pass.txt`): wrong DNS server failed Layer 1, wrong record IP failed Layer 2, one backend down passed via `B`, both backends down failed Layer 5 (`HTTP 502`), wrong port failed Layer 3, edge stopped failed Layer 2/3, and broken `nginx.conf` failed `nginx -t` on container start.
- **Learning Summary:** Testing strictly from bottom to top (DNS -> IP -> TCP -> TLS -> HTTP) prevents misdiagnosing symptoms—for instance, distinguishing a DNS resolution failure from an IP routing failure or an upstream `502` after a successful TLS handshake.

---

## 3. Honest Limitations

1. **Single macOS host with Docker containers:** All 8 logical roles (`client`, `dns`, `dns2`, `dns-cache`, `edge`, `edge2`, `backend-a`, `backend-b`) run as Docker containers on a single macOS host rather than separate physical Macs.
2. **Docker network segmentation instead of macOS `pf`:** Backend isolation is enforced with Docker's `internal: true` bridge network (`backend-net`), not macOS `pf` firewall rules, because all container-to-container traffic stays inside Docker's virtual networks.
3. **Caching resolver container, not OS DNS cache:** The Ubuntu `cn-client` container has no local OS DNS cache, so Extension B and E demonstrate caching using a dedicated `dnsmasq` caching forwarder container (`cn-dns-cache`, `172.30.0.16`).
4. **Regenerated TLS certificate:** `certs/app.key` was excluded from Git in Phase 1, so `certs/app.crt` and `certs/app.key` (`CN=app.team1.test`, `SAN=DNS:app.team1.test`) were regenerated on `2026-11-25` (documented in [02-config/tls-setup-notes.md](file:///Users/sahilchand/cn-phase1/02-config/tls-setup-notes.md)). Earlier Phase 1 evidence in `04-evidence/` was captured with the original certificate.
5. **Container stop vs. process stop:** Stopping a container (`docker compose stop edge`) removes its network interface from the bridge, causing `diagnose.sh` to fail at **Layer 2 (`ping` 100% packet loss)**, whereas stopping only the `nginx` process on a real host would leave Layer 2 `ping` working and fail at **Layer 3 (`TCP Connection refused`)**.
