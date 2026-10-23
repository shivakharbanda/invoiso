#!/usr/bin/env bash
# Smoke-test a running server: ./tool/smoke.sh <base-url> <admin-password>
set -u
B=${1:-http://localhost:8080}
PW=${2:?admin password}
c() { curl -s -m 15 "$@"; echo; }
json() { python -I -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

for _ in $(seq 1 60); do curl -s -m 2 "$B/health" >/dev/null && break; sleep 1; done
echo "--- health";    c "$B/health"
echo "--- companies"; c "$B/companies"
CID=$(curl -s -m 15 "$B/companies" | json "d[0]['id']")
login() { curl -s -m 15 -X POST "$B/auth/login" -d "{\"companyId\":\"$CID\",\"username\":\"admin\",\"password\":\"$1\"}"; }
echo "--- wrong password (expect 401)"; login wrong; echo
TOK=$(login "$PW" | json "d['token']")
[ -n "$TOK" ] || { echo "LOGIN FAILED"; exit 1; }
rpc() { c -X POST "$B/rpc/$1" -H "Authorization: Bearer $TOK" -d "{\"args\":${2:-{\}}}"; }
echo "--- settings.getCurrency";  rpc settings.getCurrency
echo "--- auth.getAllUsers (hash must be blank)"; rpc auth.getAllUsers
echo "--- auth.getUser (expect 403)"; rpc auth.getUser '{"username":"admin","password":"x"}'
echo "--- report.getRevenueSummary"; rpc report.getRevenueSummary '{"from":"2026-01-01T00:00:00.000","to":"2026-12-31T00:00:00.000","currencyCode":null}'
echo "--- no token (expect 401)"; c -X POST "$B/rpc/invoice.getInvoiceCount" -d '{"args":{}}'
echo "--- unknown method (expect 404)"; rpc nope.x
