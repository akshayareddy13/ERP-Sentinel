# ERP Sentinel - architecture

## 1. What problem it solves
ERP systems write millions of log lines (logins, workflow steps, API calls, errors). Nobody reads them until something breaks.
ERP Sentinel ingests those logs, normalises them into one schema, and turns them into: operational dashboards, workflow
analytics, security alerts, anomaly findings and reports - every number computed from the database.

## 2. Data flow
```
 CSV / JSON / text logs, generator          (api/logs.py: ingest, generate)
          |
  Parsers (services/parsers.py)  ->  Normalizer  ->  Pipeline (services/pipeline.py)
          |                                   bulk insert, de-duplication, workflow reconstruction
          v
 PostgreSQL:  logs, log_sources, workflows (+steps/events), security_events, anomalies,
              alerts (+history), alert_rules, user_activity, error_events, system_metrics,
              audit_logs, users/roles/permissions, configurations
          |
  +-------+-----------------------------+----------------------------+
  | analytics/*  (dashboard, users,     | security/ rule engine      | anomaly/ detectors         |
  |  performance, errors, ips)          | 7 rules, sliding windows   | baseline, robust-z, IForest|
  | workflows/analytics                 |                            |                            |
  +-------+-----------------------------+--------------+-------------+
          |                                            v
          |                          alerts (dedupe_key, lifecycle, history)
          v                                            |
 reports/ (builders + exporters)      ai/ (skills -> facts -> optional LLM wording)
          |                                            |
          +------------------- FastAPI (RBAC on every route) -------------------+
                                           |
                                   Next.js 14 frontend (20 pages)
```

## 3. Backend layout (`backend/app`)
| Package | Responsibility |
|---|---|
| `core/` | settings, DB session, JWT/bcrypt, RBAC permission catalogue, rate limiter, `require_permission` dependency |
| `models/` | SQLAlchemy tables |
| `services/` | parsers, normalisation, ingestion pipeline, log generator, audit + alert services, bootstrap |
| `analytics/` | shared `LogFilter` and the dashboard / users / performance / errors / IP calculations |
| `workflows/` | workflow reconstruction and analytics (success rate, bottleneck step, stuck/delayed) |
| `security/` | rule evaluators, engine, security analytics |
| `anomaly/` | detectors, engine, analytics |
| `reports/` | report builders and PDF / XLSX / CSV / JSON exporters |
| `ai/` | analyst skills, orchestrator, optional LLM narrator |
| `api/` | thin FastAPI routers (59 operations) |

Design rule: **one calculation, one place.** A dashboard card, a report section and an AI answer call the same function, so they
cannot disagree. Tests recompute the numbers independently from raw rows to prove it.

## 4. Detection
**Rules** (`security/rules.py`) - each rule is a function over a time window; thresholds are stored in `alert_rules.params`
(edits are audited, bounds are validated):

| Rule | Fires when |
|---|---|
| FAILED_LOGIN_BRUTE_FORCE | more than N failed logins for one user within M minutes |
| MULTI_IP_LOGIN | one user logs in from more than N distinct IPs within M minutes |
| NON_ADMIN_PERMISSION_CHANGE | a non-admin role changes permissions |
| HIGH_DELETE_ACTIVITY | more than N deletes by one user within M minutes |
| API_RATE_EXCEEDED | more than N API calls from one IP within M minutes |
| WORKFLOW_REPEATED_FAILURE | the same workflow fails more than N times |
| SLOW_RESPONSE | an endpoint's p95 exceeds the threshold |

A sliding-window "episodes" algorithm turns many overlapping windows into one alert, and a `dedupe_key` makes re-runs idempotent.

**Anomalies** (`anomaly/detectors.py`):
1. *Baseline* - unusual IP (first time this user is seen on an IP after an established history) and unusual login hour.
2. *Statistical* - modified z-score 0.6745·(x−median)/MAD on error counts and response times; robust so one spike does not hide itself.
3. *Isolation Forest* - per user-hour behaviour vector (events, failures, deletes, distinct IPs, distinct endpoints, response time).
   A result is reported only when at least one individual feature is also an outlier, so every finding comes with a human reason.

Medium-and-above anomalies raise alerts (`ANOMALY_<kind>`).

## 5. Alert lifecycle
`NEW -> ACKNOWLEDGED / INVESTIGATING -> RESOLVED / FALSE_POSITIVE`. Closing needs a resolution note, re-opening is allowed,
and every change writes an `alert_history` row and an audit entry. Evidence (the exact log rows), context (+-15 min) and related
alerts are shown on the alert page.

## 6. AI analyst
Rule-based intent detection selects a *skill* (summary, triage, explain alert #N, user, IP, failed logins, errors, performance,
workflows, anomalies). The skill calls the analytics code and returns facts; the answer text is built from those facts. If
`ANTHROPIC_API_KEY` is set, the model may only *reword* the answer, and the reply is rejected if it contains any number that is
not in the facts. Details in `SECURITY.md`.

## 7. Frontend
Next.js 14 (App Router), TypeScript, Tailwind, Recharts, Lucide. A `useApi` hook gives every page loading / error / retry states and
aborts stale requests. Tables are paginated by the database. Charts can be switched to tables. Severity is always icon + text,
never colour alone. Light / dark theme. Pages: dashboard, logs (+detail), import, workflows (+detail), security, anomalies,
alerts (+detail), users (+detail), performance, errors, IP monitor, reports, audit, AI analyst.

## 8. Scale and known limits
- Tested with ~11.5k generated logs on PostgreSQL 16 (seed + rules + anomaly detection ≈ 8 s).
- Detection re-scans all logs on each run; for millions of rows it should become incremental (per-hour watermark).
- Percentiles are computed in Python (numpy) after a DB fetch; for very large windows use `percentile_cont` or pre-aggregation.
- The rate limiter is in-memory (per process); use Redis for several workers.
- Raising a threshold can in theory shift an episode start and produce a second alert for the same burst.
