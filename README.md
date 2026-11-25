# CN Phase 1 & Phase 2 — Computer Networks Project (Team Climber)

> **Implementation note:** All network roles are implemented as separate Docker containers on a **single macOS host** (representing separate logical machines, not physical hardware).

---

## Phase 2 Quick Start

1. **Ensure TLS key/cert exist** (`certs/app.crt` is in Git; `certs/app.key` is gitignored—if missing, generate with `openssl req -x509 -newkey rsa:2048 -nodes -keyout certs/app.key -out certs/app.crt -days 365 -subj "/CN=app.team1.test" -addext "subjectAltName=DNS:app.team1.test"`).
2. **Start the full Phase 2 stack:**
   ```bash
   docker compose up -d --build
   docker compose ps
   ```
3. **Run the 5-layer end-to-end diagnostic check:**
   ```bash
   docker compose exec client bash /scripts/diagnose.sh
   ```
4. **Follow [DEMO_SCRIPT.md](file:///Users/sahilchand/cn-phase1/DEMO_SCRIPT.md)** for live demo steps 8–10 and the viva cheat sheet, or **[TROUBLESHOOTING.md](file:///Users/sahilchand/cn-phase1/TROUBLESHOOTING.md)** for layer-by-layer fault diagnosis.

---

## Architecture Summary (Phase 2)

- **`cnnet` (`172.30.0.0/24`):**
  - `cn-client` (`172.30.0.20`): test client (`dig`, `curl`, `nc`, `openssl`, `/scripts/diagnose.sh`)
  - `cn-dns` (`172.30.0.10:53/UDP`): primary `dnsmasq` (`app.team1.test -> 172.30.0.11`)
  - `cn-dns2` (`172.30.0.15:53/UDP`): backup `dnsmasq`
  - `cn-dns-cache` (`172.30.0.16:53/UDP`): caching `dnsmasq` forwarder for TTL/cutover demos
  - `cn-edge` (`172.30.0.11:443/TCP`, `X-Edge: edge1`): primary Nginx TLS terminator + load balancer
  - `cn-edge2` (`172.30.0.14:443/TCP`, `X-Edge: edge2`): standby Nginx edge for DNS cutover
- **`backend-net` (`172.31.0.0/24`, `internal: true`):**
  - `cn-backend-a` (`172.31.0.12:3001/TCP`): Python HTTP server A (`X-Backend: A`)
  - `cn-backend-b` (`172.31.0.13:3002/TCP`): Python HTTP server B (`X-Backend: B`)
  - Only `cn-edge` and `cn-edge2` are attached to `backend-net`; `cn-client` cannot reach ports `3001`/`3002` directly.

---

## Repository Folder Map

```text
cn-phase1/
├── 01-architecture/          # Topology, IP inventory, request flow, Mermaid diagram
├── 02-config/                # Phase 1 + Phase 2 config bundle & TLS setup notes
├── 03-code/                  # Phase 1 backend reference copy
├── 04-evidence/
│   ├── A-lan/ ... G-capture/ # Phase 1 evidence & pcaps
│   ├── failures/             # Phase 1 failure recovery evidence
│   └── 05-phase2/            # Phase 2 raw outputs (ext-A through ext-F + final-state.txt)
├── backend/                  # Live Python HTTP backend (backend.py)
├── certs/                    # app.crt (app.key is local-only / gitignored)
├── client/                   # Client container Dockerfile & resolv.conf
├── dns/                      # Primary, backup, and caching dnsmasq configs + Dockerfile
├── edge/                     # Primary (nginx.conf) & standby (nginx-edge2.conf) configs
├── scripts/                  # 5-layer diagnostic script (diagnose.sh)
├── DEMO_SCRIPT.md            # Ordered live demo steps 8-10 + viva cheat sheet
├── PHASE2_REPORT.md          # Phase 2 implementation, results, and honest limitations
├── TROUBLESHOOTING.md        # Layer-by-layer debug guide & symptom/fix table
└── docker-compose.yml        # Full Phase 2 orchestration
```
