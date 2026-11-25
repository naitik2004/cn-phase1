# TLS Setup Notes

Hostname:
app.team1.test

Certificate:
certs/app.crt

Private key:
certs/app.key

Certificate type:
Self-signed X.509 certificate

Subject:
CN=app.team1.test

Subject Alternative Name:
DNS:app.team1.test

TLS protocols configured:
TLS 1.2 and TLS 1.3

Nginx certificate configuration:
ssl_certificate /certs/app.crt;
ssl_certificate_key /certs/app.key;

The private key is kept locally (`certs/app.key` is in `.gitignore`) and is not included in the Git repository.

> **Note (2026-11-25):** The self-signed certificate (`certs/app.crt`) and private key (`certs/app.key`) were regenerated on 2026-11-25 with `CN=app.team1.test` and `SAN=DNS:app.team1.test` because `certs/app.key` was excluded from Git. Earlier Phase 1 evidence files in `04-evidence/` were captured with the original certificate.

For command-line verification, the client trusts the certificate using:
--cacert /certs/app.crt

HTTPS endpoint:
https://app.team1.test/
