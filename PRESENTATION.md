# ERP Sentinel - college presentation kit

Contents: (1) 12-slide outline with speaker notes, (2) 8-minute live demo script, (3) results to quote, (4) viva questions and answers, (5) honest limitations.

---
## 1. Slide outline (about 12 minutes + demo)

**Slide 1 - Title.** *ERP Sentinel: Log Analytics & Security Monitoring for ERP systems.* Name, guide, date.

**Slide 2 - The problem.** ERP logs are huge, unstructured and read only after an incident. Three questions nobody can answer quickly: *Is the business running? Is anyone attacking it? What should I look at first?*

**Slide 3 - Objectives.** Normalise logs from many sources - operational + workflow + security insight - detect threats with explainable rules and ML - manage alerts to closure - report and audit - answer questions in plain English. Every number comes from the database; nothing is hard-coded.

**Slide 4 - Architecture.** Use the diagram in `ARCHITECTURE.md` section 2. Say: *one calculation lives in one place; dashboards, reports and the AI analyst reuse it, so they cannot disagree.*

**Slide 5 - Tech stack and why.** FastAPI (typed, fast, auto API docs) - PostgreSQL (indexes, windowing, reliable) - SQLAlchemy - pandas / scikit-learn (anomaly detection) - Next.js + TypeScript + Tailwind + Recharts (dashboards) - Docker (one-command setup).

**Slide 6 - Ingestion pipeline.** CSV / JSON / text -> parser -> normaliser -> one schema (timestamp, level, service, event type, user, role, IP, endpoint, status, response time, error code, ...). Bad rows are reported, not silently dropped. A generator produces ~10k realistic logs with *injected attacks and a ground-truth manifest*.

**Slide 7 - Analytics.** Dashboard KPIs, workflow analytics (success rate, bottleneck step, stuck/delayed workflows), user activity, performance (avg / p95 / p99), errors, IP monitor.

**Slide 8 - Security: rules.** Table of the 7 rules (see `ARCHITECTURE.md` section 4). Thresholds are editable by an admin, validated, and every edit is audited. Sliding windows merge a burst into one alert; re-running creates no duplicates.

**Slide 9 - Security: anomaly detection.** Baseline (new IP / odd hour), robust z-score (median + MAD), Isolation Forest on per user-hour behaviour. *Only reported if a single feature is also an outlier, so every finding has a human-readable reason.*

**Slide 10 - Alerts, investigation, reports, audit.** Lifecycle NEW -> INVESTIGATING -> RESOLVED / FALSE_POSITIVE with notes and history. Alert page shows the evidence logs and +-15 min context. Reports (6 types) with a SHA-256 fingerprint -> PDF / XLSX / CSV. Audit log of every sensitive action.

**Slide 11 - AI analyst, safely.** Ask "What should I investigate first?" Answers are built from analytics results; an optional LLM may only re-word them; any number not in the facts rejects the reply; log text is treated as untrusted; each topic follows the user's role.

**Slide 12 - Results, limits, future work.** Results table (section 3). Limits (section 5). Future: streaming ingestion (Kafka / syslog), incremental detection, SIEM export, MFA, multi-tenant.

---
## 2. Live demo script (8 minutes)

Setup (before the class): `docker compose up --build`, `docker compose exec backend python seed_database.py`, open http://localhost:3000. The seed is deterministic in *shape*; exact counts shift a little with the date.

| Min | Do | Say |
|---|---|---|
| 0:00 | Log in as **analyst**. Open **Dashboard**. Change range 24h -> 7d -> 30d. | "All of this is one SQL-backed API; switch any chart to a table with the toggle." |
| 1:00 | **Log Explorer**: filter level = ERROR, search a user, open one row. | "Paginated in the database, so it stays fast with millions of rows." |
| 2:00 | **Workflows**: show success rate, bottleneck step, stuck list, open one workflow timeline. | "Workflows are rebuilt from log events; stuck means no progress for longer than the limit." |
| 3:00 | **Security**: show rules and events. Then **Alerts**: open a CRITICAL brute-force alert. | "15 failed logins in 10 minutes, then a success - exactly the evidence rows below." |
| 4:00 | On that alert: Acknowledge -> Investigating -> try Resolve with no note (refused) -> add note -> Resolve. Show history. | "Closing needs a note; every step is in history and the audit log." |
| 5:00 | **Anomalies**: open an Isolation Forest finding and read its reason. **IP monitor**: open an external IP. | "ML never says 'trust me'; it says which feature was abnormal." |
| 6:00 | **AI Analyst**: click "What should I investigate first?", then "Why was alert #1 raised?". Click a source link. | "Same numbers as the pages; guidance is labelled as general advice, not a finding." |
| 7:00 | Log out, log in as **viewer**. Show the menu is short; ask the analyst about alerts -> "your role does not have access". Show that the same call is refused by the API itself: `curl -H "Authorization: Bearer <viewer token>" localhost:8000/api/alerts` -> 403. | "RBAC is enforced by the backend, not by hiding buttons." |
| 7:45 | **Reports** -> Executive summary -> download PDF. **Audit** (as admin): show the ACCESS_DENIED row from the viewer attempt. | "Even refused attempts are recorded." |

Backup plan if something fails: screenshots of each page (take them beforehand) and `docs/ARCHITECTURE.md` open in a tab.

---
## 3. Results you can quote
(Run `cd backend && python -m pytest -q` to reproduce.)

| Measure | Value |
|---|---|
| Automated tests | **154 passing** on SQLite and on PostgreSQL 16 |
| Code size | ~6.4k lines backend, ~2k lines frontend, ~1.3k lines tests |
| API | 59 operations, all RBAC-checked by an automated route matrix |
| Pages | 20 |
| Demo data | ~11.5k logs, ~80 users, ~100 workflows; seed + detection about 8 s |
| Detection vs ground truth | every injected attack scenario is detected by its expected rule, and no rule raises an alert that was not injected (`test_every_injected_attack_is_detected`, `test_no_false_positives`) |
| Reproducibility | re-running detection creates no duplicate alerts; a report over unchanged data has the same SHA-256 fingerprint |
| Cross-check | dashboard, user, IP, error, performance and report numbers are recomputed from raw rows in the tests |

Caution: "detected / no false positives" is measured on *synthetic* data with known attacks. Real logs will be noisier; say so.

---
## 4. Viva questions and answers

**Why log analytics for ERP?** ERP holds financial and HR data; incidents there are costly, and logs are the only evidence. Manual review does not scale.

**Why FastAPI + PostgreSQL?** Typed validation, automatic OpenAPI docs, async-ready; PostgreSQL gives indexes on time / user / IP, reliable transactions and window functions. Tests also run on SQLite for speed.

**How do you stop users seeing what they should not?** Every route has `require_permission(...)`. A test iterates all routes and checks: no unguarded route, 401 without a token, 403 for each role lacking the permission.

**How do you know your detection works?** The generator injects attacks and writes a manifest. Tests check each injected attack raises the expected rule and that no unexpected alerts appear. Caveat: synthetic data.

**Why not only machine learning?** Rules are explainable, auditable and need no training data; ML finds unknown patterns. We use both and require ML results to carry a reason.

**Explain Isolation Forest simply.** It builds random trees; points that are isolated in few splits are unusual. We feed it per user-hour features (events, failures, deletes, distinct IPs, endpoints, response time).

**What is a robust z-score?** The modified z-score 0.6745 x (value - median) / MAD, where MAD is the median absolute deviation. Median and MAD are not distorted by the very outliers we want to find, unlike mean and standard deviation. We floor the MAD so a very flat series does not make tiny changes look huge.

**How do you avoid alert floods?** Sliding-window episodes merge a burst into one alert; a dedupe key makes re-runs idempotent; thresholds are tunable.

**Where does the AI get its answers? Can it hallucinate?** Answers come from the same analytics functions as the dashboards. An optional LLM may only rephrase them, and its reply is rejected if it contains any number not in the facts. It cannot act and has no tools.

**What about prompt injection through logs?** Logs are untrusted: they are passed only as delimited data, the model has no tools, output is shown as plain text, and tests cover an injected log line.

**How is password data protected?** bcrypt hashes, JWT with expiry, login rate limit, production start-up refuses a weak `JWT_SECRET`, public registration is off.

**How would it scale to millions of logs per day?** Partition `logs` by time, make detection incremental (watermark per hour), pre-aggregate metrics, move percentiles to the database, use Redis for rate limiting, queue ingestion with Kafka / a worker.

**What did you test and how?** 154 tests: unit (windowing, parsers), API integration, RBAC matrix, numbers vs independent computation, ground-truth detection, LLM safety with a mocked transport.

**What would you improve?** See section 5.

---
## 5. Honest limitations (say them before they ask)
- Evaluated on synthetic data; precision / recall on real ERP logs is unknown.
- Detection re-scans all logs each run (fine at demo scale, not at millions).
- Token stored in `sessionStorage`, no MFA / lock-out / password reset.
- In-memory rate limiter (single process).
- Docker images were not built in the authoring environment (no Docker daemon); compose file validated and the app was run directly against PostgreSQL 16.
- Percentiles are computed in Python after fetching rows.
