# Phase 1 Request Flow

1. Client requests `app.team1.test`.

2. DNS query is sent to DNS server `172.30.0.10:53`.

3. DNS resolves `app.team1.test` to Nginx Edge `172.30.0.11`.

4. Client establishes a TCP connection to `172.30.0.11:443`.

5. TLS/HTTPS is established with the Nginx Edge.

6. Nginx terminates TLS and acts as the reverse proxy.

7. Nginx forwards the request to either:

   - Backend A: `172.30.0.12:3001`
   - Backend B: `172.30.0.13:3002`

8. Nginx distributes requests between the two backends.

9. If Backend A becomes unavailable, Nginx can continue serving requests through Backend B.

10. The backend response is returned through Nginx to the client over HTTPS.

## Request Flow

Client
  |
  | DNS query
  v
DNS — 172.30.0.10:53
  |
  | app.team1.test → 172.30.0.11
  v
Nginx Edge — 172.30.0.11:443
  |
  +----> Backend A — 172.30.0.12:3001
  |
  +----> Backend B — 172.30.0.13:3002
