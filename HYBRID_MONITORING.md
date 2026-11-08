# Hybrid Monitoring

ERP Sentinel accepts module-scoped monitoring events from independently operated agents. Events are normalized through the existing log pipeline, stored in PostgreSQL, deduplicated by `(agent_id, event_id)`, then evaluated by the existing rule and anomaly engines. A central correlator also creates deduplicated alerts when suspicious activity for the same user or IP spans multiple ERP modules in a ten-minute window.

## Provision an agent

An administrator provisions each agent once. The returned token is shown only in that response; store it in a secret manager or protected environment file and do not commit it.

```sh
curl -X POST http://localhost:8000/api/monitor/agents \
  -H 'Authorization: Bearer ADMIN_ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"finance-01","module":"FINANCE"}'
```

Supported modules are `HR`, `FINANCE`, `INVENTORY`, `AUTHENTICATION`, `WORKFLOW`, and `SYSTEM_OPERATIONS`. Agent registration and activation changes require the existing `admin:config` permission. Deactivate a credential with `PATCH /api/monitor/agents/{agent_id}` and `{"is_active":false}`. Agent event delivery and heartbeats use `X-Agent-Token`; only its SHA-256 hash is stored centrally. Agent transport requires HTTPS except for localhost development.

## Run an independent agent

Run one process and use one protected SQLite database per agent. Processes are independent: a disconnected agent keeps its own queue, while the other processes continue forwarding events.

```sh
cd backend
ERP_AGENT_ID=finance-01 \
ERP_AGENT_MODULE=FINANCE \
ERP_AGENT_TOKEN='TOKEN_FROM_REGISTRATION' \
ERP_SENTINEL_URL=https://sentinel.example.com \
ERP_AGENT_DB=/var/lib/erp-sentinel/finance-01.db \
python -m app.agents.runner
```

The runner currently provides a JSON-lines stdin adapter for ERP connector integration and local simulation. Each line is a JSON event object, for example `{"event_type":"PAYMENT","status":"FAILURE","username":"alice"}`. A real ERP deployment should adapt its supported log source (file, API, or message feed) to call `Agent.collect()`; no external ERP connector is claimed by this adapter.

Events are persisted before sending and carry a stable UUID unless the collector supplies `event_id`. The sender batches up to 100 events, retains them until centrally acknowledged, retries network failures with capped exponential backoff and jitter, and reports pending counts via heartbeat. Central idempotency makes resubmission safe. Permanently invalid events retain the central rejection reason in the local database and are held for operator inspection rather than retried or silently discarded; they remain counted as pending until re-queued or removed by an operator. Secure the local database with restrictive filesystem permissions and use a separate least-privilege service account per agent.

Local checks flag critical security events, repeated authentication failures, denied access, and selected module-specific failures. These are fast indicators, not a replacement for the central security rules or ML detectors.

## Observe

The existing Dashboard includes live hybrid status, agent health, per-module counts, synchronization backlog, severity totals, recent agent events, central anomalies, and cross-module incidents. Filters are backed by `/api/monitor/hybrid` and accept `module`, `agent_id`, `severity`, `event_type`, `status`, `start`, and `end`. Events are delivered at least once under retries; the API acknowledges idempotently, but delivery cannot be guaranteed while connectivity is unavailable. Agent status becomes offline after two minutes without a heartbeat.