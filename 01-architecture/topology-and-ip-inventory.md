# Phase 1 Architecture

## Network Topology

The Phase 1 system is implemented as a Docker-based private network
using subnet 172.30.0.0/24.

```text
                         app.team1.test
                               |
                               v
                    +---------------------+
                    | DNS / dnsmasq       |
                    | 172.30.0.10 : 53   |
                    +----------+----------+
                               |
                         resolves to
                         172.30.0.11
                               |
                               v
                    +---------------------+
                    | Nginx Edge           |
                    | 172.30.0.11 : 443   |
                    | HTTPS / Load Balance |
                    +----------+----------+
                               |
                    +----------+----------+
                    |                     |
                    v                     v
          +-------------------+   +-------------------+
          | Backend A         |   | Backend B         |
          | 172.30.0.12:3001 |   | 172.30.0.13:3002 |
          +-------------------+   +-------------------+

Docker network:
172.30.0.0/24
Gateway:
172.30.0.1

### 2. Create the request-flow document

Run:

```bash
cat > 01-architecture/request-flow.md <<'EOF'
# Phase 1 Request Flow

1. The client requests `app.team1.test`.

2. The client sends a DNS query to the DNS server at
   `172.30.0.10:53`.

3. dnsmasq resolves `app.team1.test` to the Nginx Edge address:
   `172.30.0.11`.

4. The client establishes a TCP connection to
   `172.30.0.11:443`.

5. HTTPS/TLS is established between the client and the Nginx Edge.

6. Nginx terminates TLS and acts as the reverse proxy.

7. Nginx forwards the HTTP request to one of the application backends:
   - Backend A: `172.30.0.12:3001`
   - Backend B: `172.30.0.13:3002`

8. Requests are distributed between the two backends.

9. If Backend A is unavailable, Nginx can continue serving requests
   through Backend B.

10. The backend response is returned through Nginx to the client over
    the established HTTPS connection.

## Simplified Flow

Client
  |
  | DNS query
  v
DNS 172.30.0.10
  |
  | 172.30.0.11
  v
Nginx Edge 172.30.0.11:443
  |
  +----> Backend A 172.30.0.12:3001
  |
  +----> Backend B 172.30.0.13:3002
