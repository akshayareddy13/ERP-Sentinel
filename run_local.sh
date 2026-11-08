#!/usr/bin/env bash
# Run ERP Sentinel on localhost without Docker or PostgreSQL (uses a local SQLite file).
# Needs: Python 3.10+ and Node 18+.   Usage: ./run_local.sh      Stop with Ctrl+C.
set -e
cd "$(dirname "$0")"
ROOT="$PWD"

PY=""
for candidate in python3.11 python3.12 python3.10 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done
[ -n "$PY" ] || { echo "Python 3.10-3.13 is required"; exit 1; }
if ! "$PY" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info[:2] >= (3, 10) and sys.version_info[:2] < (3, 14) else 1)
PY
then
  echo "ERP Sentinel requires Python 3.10-3.13. Found: $($PY -V 2>&1)"
  exit 1
fi
command -v npm >/dev/null || { echo "Node.js (npm) is required"; exit 1; }

# ---- backend ----
cd "$ROOT/backend"
[ -d .venv ] || "$PY" -m venv .venv
# shellcheck disable=SC1091
. .venv/bin/activate
pip install -q -r requirements.txt
export DATABASE_URL="sqlite:///$ROOT/backend/erp_sentinel.db"
export JWT_SECRET="${JWT_SECRET:-local-dev-secret-$(python -c 'import secrets;print(secrets.token_hex(16))')}"
export CORS_ORIGINS="http://localhost:3000,http://127.0.0.1:3000"
if [ ! -f erp_sentinel.db ]; then echo "Creating demo data (about 11,000 logs)..."; python seed_database.py; fi
uvicorn app.main:app --host 127.0.0.1 --port 8000 &
API_PID=$!
trap 'kill $API_PID 2>/dev/null' EXIT INT TERM

# ---- frontend ----
cd "$ROOT/frontend"
[ -d node_modules ] || npm install
export NEXT_PUBLIC_API_URL="http://localhost:8000"
echo
echo "ERP Sentinel:  http://localhost:3000   (API docs: http://localhost:8000/docs)"
echo "Login:  admin / Admin@12345   (also analyst, manager, auditor, viewer - see list above)"
echo
npm run dev
