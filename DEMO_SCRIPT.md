# CN Phase 2 Live Demo Script & Viva Cheat Sheet (Team Climber)

> All commands assume you are in the `cn-phase1/` directory with the Docker Compose stack running (`docker compose up -d`).

---

## Course Demo Step 8 — Backend Failure & Recovery (HA Failover)

1. **Show baseline load balancing across Backend A and Backend B:**
   ```bash
   for i in 1 2 3 4 5 6; do
     docker compose exec client curl --cacert /certs/app.crt -s -D - -o /dev/null -w "status=%{http_code}\n" https://app.team1.test/api/status | grep -i -E "^(x-backend:|status=)" | tr '\r\n' ' '; echo ""
   done
   ```
   *Expected output:* Alternating `x-backend: A` and `x-backend: B`, all `status=200`.

2. **Stop Backend A and verify uninterrupted service via Backend B:**
   ```bash
   docker compose stop backend-a
   for i in 1 2 3 4 5 6; do
     docker compose exec client curl --cacert /certs/app.crt -s -D - -o /dev/null -w "status=%{http_code} time=%{time_total}s\n" https://app.team1.test/api/status | grep -i -E "^(x-backend:|status=)" | tr '\r\n' ' '; echo ""
   done
   ```
   *Expected output:* Every request returns `x-backend: B status=200`. The first 1–2 probes hitting A take `~2.02s` (`proxy_connect_timeout 2s` + `max_fails=2`) before `proxy_next_upstream` retries on B; subsequent requests take `~0.004s`.

3. **Restart Backend A and show round-robin recovery after `fail_timeout=10s`:**
   ```bash
   docker compose start backend-a && sleep 11
   for i in 1 2 3 4 5 6; do
     docker compose exec client curl --cacert /certs/app.crt -s -D - -o /dev/null -w "status=%{http_code}\n" https://app.team1.test/api/status | grep -i -E "^(x-backend:|status=)" | tr '\r\n' ' '; echo ""
   done
   ```
   *Expected output:* Alternates `A` and `B` again, all `status=200`.

4. **(Optional) Both backends down -> TLS succeeds, Nginx returns `502 Bad Gateway`:**
   ```bash
   docker compose stop backend-a backend-b
   docker compose exec client curl -v --cacert /certs/app.crt https://app.team1.test/api/status
   docker compose start backend-a backend-b && sleep 11
   ```
   *Expected output:* TLSv1.3 handshake completes (`SSL certificate verify ok`), followed by `HTTP/2 502` (or `504` on the very first timeout).

---

## Course Demo Step 9 — Phase 2 Resilience (Backup DNS, Isolation, TTL & Edge Cutover)

1. **Backup DNS failover (`dns` -> `dns2`):**
   ```bash
   docker compose exec client dig app.team1.test +noall +answer +stats | grep -E "app\.team1\.test|SERVER:"
   docker compose stop dns
   docker compose exec client dig app.team1.test
   docker compose start dns
   ```
   *Expected output:* Normally `SERVER: 172.30.0.10#53`. When `dns` is stopped, `172.30.0.10` times out and `dig` resolves `172.30.0.11` from `SERVER: 172.30.0.15#53`.

2. **Backend isolation (`backend-net` `internal: true`):**
   ```bash
   docker compose exec edge curl -s http://172.31.0.12:3001/api/status
   docker compose exec client curl -v --connect-timeout 3 http://172.31.0.12:3001/api/status
   docker compose exec client curl --cacert /certs/app.crt -s https://app.team1.test/api/status
   ```
   *Expected output:* `edge` succeeds (`{"backend": "A", "status": "ok"}`), `client` times out after `3000ms` (`curl: (28)`), while HTTPS through `edge` succeeds.

3. **Controlled edge migration (`edge1` -> `edge2`) & cache flush:**
   ```bash
   # Verify standby edge2 directly
   docker compose exec client curl --cacert /certs/app.crt --resolve app.team1.test:443:172.30.0.14 -s -i https://app.team1.test/api/status | grep -i -E "^(HTTP/|x-edge:|x-backend:)"

   # Prime cache (172.30.0.16), cut over authoritative DNS to 172.30.0.14, then flush cache
   docker compose exec client dig @172.30.0.16 app.team1.test +noall +answer
   sed -i '' 's|address=/app.team1.test/172.30.0.11|address=/app.team1.test/172.30.0.14|' dns/dnsmasq.conf dns/dnsmasq-backup.conf
   docker compose restart dns dns2
   docker compose exec client dig @172.30.0.16 app.team1.test +noall +answer   # still cached 172.30.0.11
   docker compose restart dns-cache                                          # manual flush
   IP=$(docker compose exec -T client dig @172.30.0.16 +short app.team1.test | tr -d '\r')
   docker compose exec client curl --cacert /certs/app.crt --resolve "app.team1.test:443:${IP}" -s -i https://app.team1.test/api/status | grep -i -E "^(HTTP/|x-edge:|x-backend:)"

   # Roll back to edge1 (172.30.0.11)
   sed -i '' 's|address=/app.team1.test/172.30.0.14|address=/app.team1.test/172.30.0.11|' dns/dnsmasq.conf dns/dnsmasq-backup.conf
   docker compose restart dns dns2 dns-cache
   ```
   *Expected output:* Before flush, `dns-cache` still returns `172.30.0.11`; after `restart dns-cache`, it returns `172.30.0.14` and `curl` shows `x-edge: edge2`. Rollback restores `x-edge: edge1`.

---

## Course Demo Step 10 — Live Fault Diagnosis (`scripts/diagnose.sh`)

1. **Run baseline 5-layer check:**
   ```bash
   docker compose exec client bash /scripts/diagnose.sh
   ```
   *Expected output:* `ALL 5 LAYERS PASSED` (`Layer 1`–`Layer 5` green, `HTTP 200`).

2. **Inject a fault (example: both backends down) and run `diagnose.sh`:**
   ```bash
   docker compose stop backend-a backend-b
   docker compose exec client bash /scripts/diagnose.sh
   ```
   *Expected output:* Layers 1–4 pass (`DNS`, `IP`, `TCP`, `TLS`), and **Layer 5** fails (`HTTP 504`/`502`), pinpointing an upstream/application issue rather than DNS or TLS.

3. **Restore and re-verify:**
   ```bash
   docker compose start backend-a backend-b && sleep 11
   docker compose exec client bash /scripts/diagnose.sh
   ```
   *Expected output:* `ALL 5 LAYERS PASSED`.

---

## 1-Page Viva Cheat Sheet (End-to-End)

- **Environment:** 8 Docker containers on one macOS host (`cnnet` `172.30.0.0/24` + internal `backend-net` `172.31.0.0/24`), simulating separate hosts.
- **DNS (`dnsmasq`, UDP/53):** Translates `app.team1.test` -> `172.30.0.11` (`edge1`). `dns2` (`172.30.0.15`) provides resolver redundancy if `dns` (`172.30.0.10`) fails.
- **DNS TTL & Caching (`dns-cache`, UDP/53):** `local-ttl` tells recursive caches (`172.30.0.16`) how long (`30s`–`60s`) to reuse an `A` record. Lowering TTL before a cutover reduces stale traffic; flushing cache forces immediate re-query.
- **TCP (TCP/443):** Client completes a 3-way handshake (`SYN`, `SYN-ACK`, `ACK`) with `cn-edge:443` before any TLS or HTTP bytes flow.
- **TLS (TLSv1.2 / TLSv1.3):** `cn-edge` terminates HTTPS using `/certs/app.crt` (`CN=app.team1.test`, `SAN=DNS:app.team1.test`) and `/certs/app.key`. Clients verify trust with `--cacert /certs/app.crt` (never `-k`).
- **Load Balancing & Passive Failover:** Nginx distributes HTTP/1.1 requests round-robin across `172.31.0.12:3001` (`backend-a`) and `172.31.0.13:3002` (`backend-b`). With `max_fails=2 fail_timeout=10s` and `proxy_next_upstream`, a dead backend is bypassed for `10s` after 2 failed probes, keeping `HTTP 200` via the surviving backend.
- **Service Isolation:** `backend-net` has `internal: true`, so `cn-client` has no route to `3001`/`3002`. Only `cn-edge` and `cn-edge2` are dual-homed on both `cnnet` and `backend-net`.
- **Edge Cutover / SPOF:** A single Nginx edge is a SPOF; `cn-edge2` (`172.30.0.14`, `X-Edge: edge2`) demonstrates DNS-based cutover (bounded by TTL), whereas production instant failover uses VRRP/`keepalived` or a cloud LB.
- **HTTP Caching:** `/api/static` returns `ETag` + `Cache-Control: max-age=60`. Both backends compute identical ETags, so `If-None-Match` revalidation returns `304 Not Modified` regardless of which backend handles the request.
