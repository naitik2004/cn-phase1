# Troubleshooting Guide — CN Phase 2 (Team Climber)

> **Environment note:** All service roles run as Docker containers on a single macOS host (`172.30.0.0/24` for `cnnet` and `172.31.0.0/24` for internal `backend-net`).

## 5-Layer Diagnostic Flow (`scripts/diagnose.sh`)

Always diagnose **bottom-up** so you pinpoint the exact failing layer instead of guessing:

1. **Layer 1 — DNS (`dig @172.30.0.10` / `@172.30.0.15 app.team1.test`)**
   - Checks whether primary and backup `dnsmasq` resolvers answer, what IP they return, and the TTL.
   - **Failure meaning:** No answer or timeout -> DNS container stopped, wrong `listen-address`, or client pointing at the wrong nameserver. Wrong IP -> stale or misconfigured `address=/app.team1.test/...` record (or stale cache in `dns-cache`).
2. **Layer 2 — IP Reachability (`ping <resolved_ip>`)**
   - Checks L3 routing/reachability to the resolved edge IP (`172.30.0.11` or `172.30.0.14`).
   - **Failure meaning:** Packet loss / unreachable -> target container is stopped, on the wrong Docker network, or DNS returned a non-existent IP.
3. **Layer 3 — TCP (`nc -vz <resolved_ip> 443`)**
   - Checks L4 TCP three-way handshake on port `443`.
   - **Failure meaning:** Connection refused -> Nginx is not listening on `443` (process crashed or wrong port). Timeout -> firewall/network isolation blocking traffic.
4. **Layer 4 — TLS (`openssl s_client -connect <ip>:443 -servername app.team1.test -CAfile /certs/app.crt -verify_return_error`)**
   - Checks TLS handshake, certificate `Subject`/`SAN`, validity dates, and CA trust.
   - **Failure meaning:** `Verify return code != 0` -> expired cert, SAN mismatch (cert doesn't cover `app.team1.test`), or wrong `--cacert`/`-CAfile`.
5. **Layer 5 — HTTP / Application (`curl -i --cacert /certs/app.crt https://app.team1.test/api/status`)**
   - Checks HTTP status code, `X-Edge` (`edge1`/`edge2`), `X-Backend` (`A`/`B`), and JSON body.
   - **Failure meaning:** `502 Bad Gateway` / `504 Gateway Time-out` -> Nginx edge is healthy, but upstream backends are down or unreachable.

---

## Symptom -> Layer -> Likely Cause -> Fix

| Symptom | Layer | Likely Cause | Fix |
| :--- | :--- | :--- | :--- |
| `dig` times out or `curl: (6) Could not resolve host` | **Layer 1 (DNS)** | Wrong DNS server in `/etc/resolv.conf`, or both `dns` and `dns2` containers are stopped | Check `/etc/resolv.conf` (`172.30.0.10`, `172.30.0.15`); `docker compose start dns dns2` |
| `dig` succeeds, but `ping` / `nc` / `curl` hangs on a bogus IP (e.g., `172.30.0.99`) | **Layer 1 (DNS) -> Layer 2 (IP)** | Wrong IP in `dns/dnsmasq.conf` or `dns/dnsmasq-backup.conf`, or stale entry in `dns-cache` | Fix `address=/app.team1.test/172.30.0.11` in dnsmasq configs, restart `dns dns2 dns-cache` |
| One backend stopped (`backend-a` down) | **Layer 5 (Upstream)** | Single backend container crashed/stopped; Nginx passive health check routes around it | Traffic stays `200` via `backend-b`; restart with `docker compose start backend-a` and wait `fail_timeout` (`10s`) |
| `HTTP/2 502 Bad Gateway` (or `504` on first hit) after TLS succeeds | **Layer 5 (HTTP)** | **Both** `backend-a` and `backend-b` are stopped, or Nginx upstream IPs don't match `backend-net` | Check `docker compose ps`, start `backend-a backend-b`, verify `edge/nginx.conf` upstream IPs (`172.31.0.12:3001`, `172.31.0.13:3002`) |
| `Connection refused` on port check (`nc -vz 172.30.0.11 8443`) | **Layer 3 (TCP)** | Wrong port queried or Nginx `listen` directive misconfigured | Verify `listen 443 ssl http2;` in `edge/nginx.conf` and query port `443` |
| `ping 172.30.0.11` fails (100% packet loss) or `nc -vz 172.30.0.11 443` times out | **Layer 2 (IP) / Layer 3 (TCP)** | **Edge down** (`cn-edge` container stopped or crashed) | Run `docker compose ps`, restart with `docker compose start edge` (or cut over DNS to `edge2`) |
| `SSL certificate problem` / `Verify return code != 0` | **Layer 4 (TLS)** | Expired cert, SAN mismatch (missing `DNS:app.team1.test`), or missing `--cacert /certs/app.crt` | Inspect cert with `openssl x509 -in certs/app.crt -noout -text`; regenerate cert with `SAN=DNS:app.team1.test` and pass `--cacert /certs/app.crt` |
| `cn-edge` exits immediately (`Exited (1)`) | **Layer 3/4 (Nginx)** | Syntax error in `edge/nginx.conf` or missing `/certs/app.key` | Run `docker compose logs edge` and `docker compose exec edge nginx -t`; fix config/key and recreate `edge` |
| `curl http://172.31.0.12:3001` times out from `cn-client` | **Layer 2/3 (Isolation)** | Expected behavior: `backend-net` is `internal: true` so clients cannot bypass the edge | Route client traffic through `https://app.team1.test/` (via `cn-edge` / `cn-edge2`) |
