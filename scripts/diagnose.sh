#!/usr/bin/env bash
# 5-layer network diagnostic script for CN Phase 2 (Team Climber)
# Usage inside client container:
#   docker compose exec client bash /scripts/diagnose.sh
# Optional overrides for fault testing:
#   DIAG_DNS=172.30.0.99 DIAG_PORT=443 bash /scripts/diagnose.sh
set -uo pipefail

DOMAIN="${DIAG_DOMAIN:-app.team1.test}"
PORT="${DIAG_PORT:-443}"
DNS1="${DIAG_DNS:-172.30.0.10}"
DNS2="${DIAG_DNS:-172.30.0.15}"
CACERT="${DIAG_CACERT:-/certs/app.crt}"

# If executed on the macOS host, re-run inside cn-client automatically
if [ ! -f "/.dockerenv" ]; then
    export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
    exec docker compose exec -T client bash /scripts/diagnose.sh "$@"
fi

echo "============================================================"
echo " CN Phase 2 — 5-Layer Diagnostic Check for ${DOMAIN}:${PORT}"
echo "============================================================"

# ------------------------------------------------------------
# Layer 1: DNS
# ------------------------------------------------------------
echo ""
echo "[Layer 1] DNS Resolution (primary=${DNS1}, backup=${DNS2})"
DNS1_OUT=$(dig @"${DNS1}" "${DOMAIN}" +tries=1 +time=2 2>&1)
DNS1_ANS=$(printf '%s\n' "${DNS1_OUT}" | awk '/^;; ANSWER SECTION:/{flag=1; next} /^;;/{flag=0} flag && NF')
echo "  Primary (${DNS1}) answer: ${DNS1_ANS:-<none>}"

RESOLVED_IP=$(printf '%s\n' "${DNS1_ANS}" | awk '$4=="A"{print $5}' | tail -n1 | tr -d '\r')
USED_DNS="${DNS1}"

if [ -z "${RESOLVED_IP}" ] && [ "${DNS2}" != "${DNS1}" ]; then
    DNS2_OUT=$(dig @"${DNS2}" "${DOMAIN}" +tries=1 +time=2 2>&1)
    DNS2_ANS=$(printf '%s\n' "${DNS2_OUT}" | awk '/^;; ANSWER SECTION:/{flag=1; next} /^;;/{flag=0} flag && NF')
    echo "  Backup  (${DNS2}) answer: ${DNS2_ANS:-<none>}"
    RESOLVED_IP=$(printf '%s\n' "${DNS2_ANS}" | awk '$4=="A"{print $5}' | tail -n1 | tr -d '\r')
    USED_DNS="${DNS2}"
fi

if [ -z "${RESOLVED_IP}" ]; then
    echo "FAIL [Layer 1 - DNS]: Could not resolve ${DOMAIN} from ${DNS1} (or ${DNS2})."
    exit 1
fi
echo "  PASS: Resolved ${DOMAIN} -> ${RESOLVED_IP} via ${USED_DNS}"

# ------------------------------------------------------------
# Layer 2: IP Reachability
# ------------------------------------------------------------
echo ""
echo "[Layer 2] IP Reachability (ping -c 2 -W 2 ${RESOLVED_IP})"
if ! ping -c 2 -W 2 "${RESOLVED_IP}"; then
    echo "FAIL [Layer 2 - IP]: Host ${RESOLVED_IP} is unreachable via ICMP ping."
    exit 2
fi
echo "  PASS: ${RESOLVED_IP} is reachable"

# ------------------------------------------------------------
# Layer 3: TCP
# ------------------------------------------------------------
echo ""
echo "[Layer 3] TCP Port Check (nc -vz -w 2 ${RESOLVED_IP} ${PORT})"
if ! nc -vz -w 2 "${RESOLVED_IP}" "${PORT}" 2>&1; then
    echo "FAIL [Layer 3 - TCP]: TCP port ${PORT} is closed or timed out on ${RESOLVED_IP}."
    exit 3
fi
echo "  PASS: TCP ${RESOLVED_IP}:${PORT} is open"

# ------------------------------------------------------------
# Layer 4: TLS
# ------------------------------------------------------------
echo ""
echo "[Layer 4] TLS Handshake & Certificate (${RESOLVED_IP}:${PORT}, CA=${CACERT})"
TLS_OUT=$(echo | openssl s_client -connect "${RESOLVED_IP}:${PORT}" -servername "${DOMAIN}" -CAfile "${CACERT}" -verify_return_error 2>&1)
TLS_RC=$?
echo "${TLS_OUT}" | grep -E "(subject=|issuer=|Verify return code:|Protocol|Cipher)" || true
echo | openssl s_client -connect "${RESOLVED_IP}:${PORT}" -servername "${DOMAIN}" 2>/dev/null \
    | openssl x509 -noout -dates -ext subjectAltName 2>/dev/null || true

if [ "${TLS_RC}" -ne 0 ]; then
    echo "FAIL [Layer 4 - TLS]: TLS handshake or certificate verification failed (exit ${TLS_RC})."
    exit 4
fi
echo "  PASS: TLS handshake & certificate verified"

# ------------------------------------------------------------
# Layer 5: HTTP / Application
# ------------------------------------------------------------
echo ""
echo "[Layer 5] HTTP / Application (curl -v --cacert ${CACERT} https://${DOMAIN}/api/status)"
HTTP_RESP=$(curl -v --max-time 5 --cacert "${CACERT}" --resolve "${DOMAIN}:${PORT}:${RESOLVED_IP}" "https://${DOMAIN}/api/status" 2>&1)
CURL_RC=$?
echo "${HTTP_RESP}" | grep -E "(^< HTTP/|^< x-backend:|^< x-edge:|^\* |^\{)" || echo "${HTTP_RESP}"

if [ "${CURL_RC}" -ne 0 ]; then
    echo "FAIL [Layer 5 - HTTP]: curl failed (exit ${CURL_RC})."
    exit 5
fi

STATUS_CODE=$(printf '%s\n' "${HTTP_RESP}" | awk '/^< HTTP\//{print $3; exit}')
if [ -z "${STATUS_CODE}" ] || [ "${STATUS_CODE}" -ge 400 ]; then
    echo "FAIL [Layer 5 - HTTP]: Application returned HTTP ${STATUS_CODE:-unknown}."
    exit 5
fi

echo ""
echo "  PASS: HTTP ${STATUS_CODE} received cleanly"
echo "============================================================"
echo " ALL 5 LAYERS PASSED"
echo "============================================================"
exit 0
