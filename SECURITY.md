# ERP Sentinel - security notes

## Controls implemented
| Area | Control |
|---|---|
| Authentication | bcrypt password hashes, JWT access tokens with expiry, login rate limit per IP |
| Authorization | RBAC enforced **in the backend** on every API route (`require_permission`); the UI hides links but is never the gate. `tests/test_rbac_matrix.py` walks every route: each must be public-by-design or guarded, and every role lacking the permission must get 403 |
| Registration | public sign-up is **off** by default (`ALLOW_SELF_REGISTRATION=false`); users are created by an ADMIN. When enabled it is rate-limited and creates VIEWER only |
| Audit | logins, failures, permission denials (`ACCESS_DENIED`), alert changes, rule edits, exports, report generation and AI questions are written to `audit_logs` |
| Input | pydantic validation on all bodies / queries, bounded page sizes, SQLAlchemy parameter binding (no string-built SQL), LIKE wildcards escaped in searches |
| Uploads | file-size (25 MB) and file-count (10) limits, parser errors reported per row, nothing executed |
| Exports | spreadsheet formula-injection neutralised (cells starting `= + - @` get a leading apostrophe) |
| Errors | unexpected errors return a generic 500; details go to the server log only |
| Configuration | production start-up refuses a placeholder or short `JWT_SECRET`; secrets come from the environment; only `NEXT_PUBLIC_*` reaches the browser |
| Containers | non-root users, health checks, DB port bound to localhost, data volume mounted read-only |
| Frontend | no `dangerouslySetInnerHTML`; log text and AI answers are rendered as plain text |

## AI analyst threat model
Logs are attacker-influenced text (a user can put anything in a message). So:
1. The default analyst is deterministic: it has no model, nothing to inject into.
2. With an LLM, log-derived text is passed only inside a delimited `<FACTS>` block, the system prompt says to treat it as data, the model has **no tools** and cannot trigger any action.
3. The reply is rejected (and the deterministic answer used instead) if it contains a number that is not in the computed facts.
4. Each skill needs its own permission - asking the analyst is never a way around RBAC (tested for every role).
5. Per-user rate limit and an audit entry for every question.

## Not covered (be honest in the viva)
- Tokens live in `sessionStorage` (readable by XSS, but not sent automatically like cookies). An httpOnly-cookie design with CSRF protection would be stronger.
- No account lock-out / MFA / password-reset flow; there is a login rate limit only.
- No TLS termination in the compose file - put a reverse proxy (nginx / Caddy) in front for real use.
- Rate limiting is per process (in memory).
- The images could not be built in the authoring environment (no Docker daemon); the compose file validates with `docker compose config`, the app was run and tested against PostgreSQL 16 directly.
