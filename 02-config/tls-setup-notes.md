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

The private key is kept locally and is not included in the submission bundle.

For command-line verification, the client trusts the certificate using:
--cacert /certs/app.crt

HTTPS endpoint:
https://app.team1.test/
