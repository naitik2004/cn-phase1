# Extension D — Passive Health Checks & Remaining Single Point of Failure

## Passive vs. Active Health Checks in Open-Source Nginx
Open-source Nginx (`nginx:1.24`) only performs **passive** health checks:
- `max_fails=2 fail_timeout=10s`: Nginx marks a backend as temporarily unavailable for `10s` only **after** `2` failed live client requests within `10s`. It does **not** send proactive background health probes (active health checks require Nginx Plus or an external controller/LB).
- `proxy_connect_timeout 2s` + `proxy_next_upstream error timeout http_502 http_503 http_504` + `proxy_next_upstream_tries 2`: if a request hits a failed backend, Nginx retries on the next upstream server within the same client request so the client still receives `HTTP 200`.

## Remaining Single Point of Failure (SPOF)
Even with two backends (`backend-a` and `backend-b`) and two DNS resolvers (`dns` and `dns2`), the **Nginx edge (`cn-edge`, `172.30.0.11`)** is still a single point of failure: if `cn-edge` stops or crashes, all HTTPS traffic to `app.team1.test` fails.

### How to eliminate the edge SPOF
1. **Active/Standby Edge with VRRP (`keepalived`):** Two Nginx edges share a floating Virtual IP (VIP). If the primary edge fails, `keepalived` moves the VIP to the standby edge automatically.
2. **DNS Failover / Multi-A-Record / Anycast:** Publish multiple edge IPs in DNS or update the DNS record to a standby edge IP when the primary fails (demonstrated in **Extension E**).
3. **Managed Cloud Load Balancer:** Place a horizontally redundant cloud LB (e.g., AWS ALB/NLB, GCP Cloud Load Balancing) in front of multiple Nginx/application instances.
