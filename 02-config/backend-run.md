# Backend Launch Instructions

The project uses two backend instances running on the Docker CN network.

Backend A:
IP: 172.30.0.12
Port: 3001
Environment:
BACKEND=A
PORT=3001

Backend B:
IP: 172.30.0.13
Port: 3002
Environment:
BACKEND=B
PORT=3002

The backends are started through Docker Compose.

Start the complete Phase 1 system:

docker compose up -d --build

Check services:

docker compose ps

The backend application is implemented in:

backend/backend.py

Nginx forwards HTTPS requests to the two backend instances.
