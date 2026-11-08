<<<<<<< HEAD
# ERP Sentinel

**ERP Log Analytics & Security Monitoring Engine** - turns raw ERP / workflow / system logs into
operational, workflow, performance and security insights.

> **Status: all 11 phases complete.** Ingestion + generator, dashboard + Log Explorer, workflow analytics, security rule engine,
> anomaly detection, alert management, user / performance / error / IP analytics, reports + audit log, AI analyst, tests,
> Docker and documentation. Nothing in the UI is hardcoded: every number comes from the database.

**Documentation:** [Architecture](docs/ARCHITECTURE.md) - [Security notes](docs/SECURITY.md) - [Insider, DLP, audit and guest controls](docs/INSIDER_DLP_GUEST_SECURITY.md) - [Presentation kit (slides, demo script, viva Q&A)](docs/PRESENTATION.md)

## Architecture

```
ERP / SYSTEM LOGS -> Ingestion -> Parser -> Normalization -> PostgreSQL
                                                   |
                       Workflow / Security / Performance analytics
                                                   |
                                  Anomaly detection -> Alert engine
                                                   |
                                     FastAPI  ->  Next.js dashboard
```

Backend layout (`backend/app`): `api/` routes, `core/` config-db-security-deps, `models/` SQLAlchemy tables,
`schemas/` Pydantic, `services/` reusable pipeline stages, `analytics/`, `security/`, `workflows/` engines
(added in later phases, kept independent so an LLM layer can be added later).

## Phase 1 - what exists and works

- 17 PostgreSQL tables with PKs, FKs, CHECK constraints and indexes on timestamp, user_id, event_type,
  level, service, workflow_id, transaction_id, ip_address
  (`users, roles, permissions, role_permissions, logs, log_sources, workflows, workflow_steps,
  workflow_events, security_events, alerts, alert_history, alert_rules, user_activity, audit_logs,
  system_metrics, error_events, configurations`)
- bcrypt password hashing, JWT auth, login rate limiting, no account enumeration
- Backend-enforced RBAC (`require_permission`), 5 roles, denied access is audited
- Public registration always creates a least-privilege VIEWER; only ADMIN can change roles
  (with last-admin lock-out protection)
- Audit log for login/logout/failed login/user create/role change/access denied
- Default detection rules + thresholds stored in the database (editable by the Admin UI in a later phase)
- Next.js login, session restore, permission-aware sidebar, empty-state dashboard

## Phase 5 - security rule engine

- Seven rules live in `alert_rules` (thresholds in `params`), editable by ADMIN on the **Security** page; every edit is audited with before/after values.
- A threshold is *exceeded* when count > threshold; sliding windows are merged into one episode per attack.
- `POST /api/security/run` (also run automatically after every import) is idempotent: alerts are keyed by `dedupe_key`.
- Verified against the generator's ground truth: all injected attacks are detected, with no false positives.

## Phase 6 - anomaly detection

- Per-user baselines (new login IP, off-hours login), robust z-scores (error spikes per service, slow endpoints) and a scikit-learn Isolation Forest over per-user-hour behaviour, reported only when a single feature is also a clear outlier.
- Every anomaly stores a plain-language reason with the numbers behind it; settings are editable by ADMIN and stored in `configurations`.
- Deterministic and idempotent; MEDIUM+ anomalies also raise alerts. Verified against the generator's ground truth (`tests/test_anomaly.py`).

## Phase 7 - alerts and investigation

- Alerts from the rule engine and the anomaly detectors are triaged on `/alerts`: filter, sort by severity, search, bulk acknowledge/resolve.
- Each alert has an enforced lifecycle (NEW -> ACKNOWLEDGED -> INVESTIGATING -> RESOLVED / FALSE_POSITIVE, re-open allowed). Closing needs a resolution note.
- Assignment is limited to active users who can work alerts. Every status change, assignment and note is kept in the alert history and the audit log.
- The detail page shows the evidence, the logs behind it, other activity by the same subject within 15 minutes, 24-hour activity facts and related alerts.
- AUDITOR can read alerts; only ADMIN and SECURITY_ANALYST can change them.

## Phase 8 - user, performance, error and IP analytics

- **Users** (`/users`): per-user events, logins, failed logins, deletes, errors, distinct IPs, alerts; drill-down per user with an activity timeline and the IPs used.
- **Performance** (`/performance`): average, median, p95, p99, failure rate and slow-request share from every log row that has a response time; slowest endpoints, distribution, per-service averages, sortable endpoint table. The slow threshold is the `slow_api_threshold_ms` setting.
- **Errors** (`/errors`): ERROR/CRITICAL volume over time, error rate per service, top error codes, codes first seen in the selected range, searchable error signatures.
- **IP monitor** (`/ips`): internal vs external addresses, failed logins by IP, users per IP and IPs per user. "Suspicious" is a stated fact, not a guess: at least `failed_login_threshold` failed logins, or an alert or anomaly on the address.
- Every number is recomputed from raw rows in `tests/test_monitoring.py`.

## Phase 9 - reports and audit log

- **Reports** (`/reports`): executive summary, operations, security, user activity, alert log and audit trail. Built on demand with the same analytics code the dashboards use, so a report number always equals the number on its page. Each report carries a SHA-256 fingerprint of its content: the same window over unchanged data gives the same fingerprint. Export to PDF, XLSX, CSV or JSON, or print.
- Each report type is limited by role (for example the audit trail needs `audit:read`); generating or exporting a report is audited, and a refused attempt is recorded as ACCESS_DENIED.
- Exports neutralise spreadsheet formula injection (cells starting with `=`, `+`, `-`, `@` get a leading apostrophe).
- **Audit logs** (`/audit`): filter by period, action, user, result and free text; summary charts; entry details; CSV export (audited, capped at 50,000 rows).

## Phase 10 - AI analyst

- **AI Analyst** (`/ai`): ask in plain English - "What should I investigate first?", "Why was alert #1 raised?", "Tell me about user X", "What do we know about 10.0.0.5?", "Which endpoints are slowest?".
- Answers are **built from the same analytics code as the dashboards** (ten skills), with the facts, links to the pages behind them and the time window shown. Unknown questions get an honest list of what can be asked. Generic advice is labelled "General guidance", never mixed with findings.
- Each skill needs its own permission, so the analyst cannot reveal more than the user's role allows. Every question is audited (`AI_QUERY`) and rate-limited per user.
- Optional LLM wording: set `ANTHROPIC_API_KEY` (and optionally `AI_MODEL`). The model only re-words the computed answer, has no tools, receives log text as delimited data, and its reply is discarded if it contains any number that is not in the facts. Without a key everything works from built-in templates.

## Phase 11 - quality, Docker and documentation

- 154 tests, run on SQLite by default and on PostgreSQL 16 with `TEST_DATABASE_URL`. An RBAC matrix test checks every API route: public by design or permission-guarded, 401 without a token, 403 for each role lacking the permission.
- Hardening found by that check: public self-registration is now off by default (`ALLOW_SELF_REGISTRATION`), and production start-up refuses a placeholder or short `JWT_SECRET`.
- Docker: multi-stage frontend (Next.js standalone), non-root containers, health checks, DB bound to localhost, read-only data mount.
- Docs and presentation material in `docs/`.

## Roles

| Role | Access |
|---|---|
| ADMIN | everything |
| SECURITY_ANALYST | security, alerts (read/write), logs, users, IPs, errors, performance, workflows, reports (all but audit trail) |
| MANAGER | dashboard, workflows, reports, performance, errors |
| AUDITOR | dashboard, logs, audit logs, reports, alerts (read) |
| VIEWER | dashboard, performance (read-only) |

The AI analyst follows these rows: it only answers about topics the role can already open.

## Run on your computer (no Docker, no PostgreSQL)

Needs Python 3.10+ and Node.js 18+.

- Mac / Linux: `./run_local.sh`
- Windows: double-click `run_local.bat` (or run it in a terminal)

The first run installs dependencies and creates demo data (about 11,000 logs) in a local SQLite file, then starts the API on
http://localhost:8000 and the app on **http://localhost:3000**. Log in as `admin / Admin@12345`
(also `analyst / Analyst@12345`, `manager / Manager@12345`, `auditor / Auditor@12345`, `viewer / Viewer@12345`). Stop with Ctrl+C.
To start again with fresh demo data, delete `backend/erp_sentinel.db`.

## Quick start (Docker)

```bash
cp .env.example .env        # set a long random JWT_SECRET
docker compose up --build
docker compose exec backend python seed_database.py
```

Frontend http://localhost:3000, API docs http://localhost:8000/docs.
Demo logins (from the seed script): `admin / Admin@12345`, `analyst`, `manager`, `auditor`, `viewer`
(passwords are printed by the script). **Change these outside a demo.**

## Quick start (manual)

```bash
# backend
cd backend && pip install -r requirements.txt
export DATABASE_URL=postgresql+psycopg2://sentinel:sentinel_pw@localhost:5432/erp_sentinel
python seed_database.py && uvicorn app.main:app --reload

# frontend
cd frontend && npm install && npm run dev
```

## Tests

```bash
cd backend && python -m pytest -q     # 154 tests; uses a temporary SQLite DB, no Postgres needed
# same suite on PostgreSQL (drops and recreates the schema - use a scratch database):
TEST_DATABASE_URL=postgresql+psycopg2://user:pass@localhost:5432/scratch python -m pytest -q
```

## Environment variables

See `.env.example` (including `ALLOW_SELF_REGISTRATION`, `ANTHROPIC_API_KEY`, `AI_MODEL`, `AI_RATE_LIMIT_PER_MINUTE`). In production set `ENVIRONMENT=production` and a random `JWT_SECRET` of 32+ characters. Only `NEXT_PUBLIC_*` values reach the browser; `JWT_SECRET` never does.

## Build history

1 architecture/DB/auth - 2 ingestion/parsing/normalization + 10k-log generator - 3 dashboard + log explorer - 4 workflow analytics -
5 security rule engine - 6 anomaly detection - 7 alerts + investigation - 8 users/performance/errors - 9 reports + audit UI -
10 AI analyst - 11 tests, Docker, documentation. See `docs/SECURITY.md` and `docs/ARCHITECTURE.md` for known limitations.
=======
# ERP-Sentinel
ERP Sentinel - ERP Log Monitoring and Anomaly Detection System
>>>>>>> 09b6f136232c713b9e4d0089c86a41529b046a06
