# Phase 2 End-to-End Request Flow (Team Climber)

1. **DNS (`UDP/53`):**
   - `cn-client` (`172.30.0.20`) queries its primary resolver `cn-dns` (`172.30.0.10:53/UDP`) for `app.team1.test`.
   - If `cn-dns` is unreachable, the client resolver times out and fails over to `cn-dns2` (`172.30.0.15:53/UDP`).
   - When testing TTL caching/cutover, `cn-client` queries `cn-dns-cache` (`172.30.0.16:53/UDP`), which caches the `A` record (`172.30.0.11` normally, or `172.30.0.14` during cutover) for the configured TTL (`60s` default, `30s` during cutover tests).
2. **TCP (`TCP/443`):**
   - `cn-client` performs a TCP three-way handshake (`SYN`, `SYN-ACK`, `ACK`) to the resolved edge IP (`172.30.0.11:443/TCP` for `edge1`, or `172.30.0.14:443/TCP` for `edge2`).
3. **TLS (`TLSv1.2 / TLSv1.3`):**
   - `cn-client` and Nginx complete the TLS handshake with `SNI: app.team1.test`.
   - `cn-client` verifies the self-signed certificate (`/certs/app.crt`, `SAN=DNS:app.team1.test`) using `--cacert /certs/app.crt` (never `-k`).
4. **HTTP Reverse Proxy & Load Balancing (`backend-net`, `TCP/3001` & `TCP/3002`):**
   - Nginx terminates TLS and forwards plain HTTP/1.1 over the isolated `backend-net` (`172.31.0.0/24`) to `172.31.0.12:3001` (`backend-a`) and `172.31.0.13:3002` (`backend-b`) in round-robin.
   - Passive health handling (`max_fails=2 fail_timeout=10s`, `proxy_connect_timeout 2s`, `proxy_next_upstream error timeout http_502 http_503 http_504`) retries failed backends transparently on the healthy peer.
   - `cn-edge` adds `X-Edge: edge1` (`cn-edge2` adds `X-Edge: edge2`) alongside the backend's `X-Backend: A|B` header and returns the HTTPS response to `cn-client`.

```text
cn-client (172.30.0.20)
  |--[UDP/53]---> cn-dns (172.30.0.10) / cn-dns2 (172.30.0.15) / cn-dns-cache (172.30.0.16)
  |                 returns app.team1.test -> 172.30.0.11 (or 172.30.0.14 on cutover)
  v
  |--[TCP/443 + TLS 1.3]---> cn-edge (172.30.0.11 / 172.31.0.11)  [standby: cn-edge2 .0.14]
                                |
                                | (isolated internal backend-net 172.31.0.0/24)
                                +--> [TCP/3001 HTTP] cn-backend-a (172.31.0.12)
                                +--> [TCP/3002 HTTP] cn-backend-b (172.31.0.13)
```
