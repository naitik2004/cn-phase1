# CN Phase 1 — Private DNS, HTTPS, Reverse Proxy & Load Balancing

Computer Networks Phase 1 project implementing private DNS, HTTPS/TLS, Nginx reverse proxy and load balancing between two backend servers.

## Run

Requirements: Docker Desktop and Docker Compose.

```bash
docker compose up -d --build
docker compose ps
```

## Architecture

Client → DNS (172.30.0.10) → Nginx Edge (172.30.0.11:443) → Backend A (172.30.0.12:3001) / Backend B (172.30.0.13:3002)

## DNS

```bash
docker compose exec dns dig @172.30.0.10 app.team1.test
```

## HTTPS

The project uses a self-signed TLS certificate for app.team1.test. The private key is excluded from Git using .gitignore.

## Load Balancing

Nginx distributes requests between Backend A and Backend B. The X-Backend response header shows which backend handled each request.

## Caching

The /api/static endpoint demonstrates Cache-Control, ETag and HTTP 304 Not Modified responses.

## Failure Handling

Stopping Backend A demonstrates that requests can continue through Backend B.

## Evidence

The 04-evidence directory contains LAN, DNS, backend, load-balancing, TLS, caching, failure and packet-capture evidence.

## Project Structure

01-architecture/ — Architecture documentation
02-config/ — DNS, Nginx and TLS configuration
03-code/ — Backend source code
04-evidence/ — Phase 1 evidence
backend/ — Backend service
dns/ — dnsmasq container
edge/ — Nginx reverse proxy
certs/ — Public TLS certificate
docker-compose.yml — Container topology
