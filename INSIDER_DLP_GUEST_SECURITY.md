# Insider, DLP, Audit and Guest Security

ERP Sentinel extends its existing FastAPI authentication, role permissions, audit API, alert engine, report exporters, hybrid agents and dashboard. New state is stored in the same PostgreSQL/SQLite database. Startup creates the new tables and additively adds the audit hash columns; existing logs and audit rows are preserved.

## Roles and separation of duties

Three operational roles are seeded alongside the existing roles:

- `ERP_SECURITY_ADMIN`: manages security policy, DLP, guest access and offboarding.
- `SECURITY_MONITOR`: monitors logs, security events, alerts and dashboards.
- `AUDIT_COMPLIANCE`: reads audit integrity, reports, finance activity and votes on sensitive approvals.

Sensitive approvals require the requester's recorded endorsement and one vote from a different authorized user. The requester cannot vote a second time. This is a two-person control, not a claim that the organization has exactly three accounts. Emergency guest revocation and employee session revocation remain immediate and are audited.

Two-person approval is required for DLP policy changes, security rule edits, anomaly detector configuration, audit retention changes, privileged account creation/role changes, restricted exports and monitoring-agent shutdown. Emergency account/guest revocation remains immediate; the resulting action is recorded for independent review.

## Insider monitoring and DLP

All report and audit exports pass the stored Public/Internal/Confidential/Restricted DLP policy. Evaluation considers role, classification, record volume, UTC access time, prior role-blocked exports and open high-severity alerts. A large export alone is not considered malicious. A high-risk request is held with HTTP 428 and a two-person approval request; retry the same export with the returned approval ID after a different authorized user votes.

DLP decisions are stored in `dlp_events`, appear in the dashboard and are chained into the audit trail. High-risk and role-blocked decisions raise deduplicated alerts. Guest reports are limited by invitation resource scopes and mask email and IP fields. The financial activity report is an aggregate of stored finance-related log events; this app does not have a ledger or reliable monetary amounts, so it does not invent totals.

DLP can gate server-generated ERP Sentinel exports. It cannot prevent copying already displayed information, screenshots, cameras, removable media or exfiltration by a compromised endpoint. Endpoint controls require a separately managed device agent/MDM/DLP integration.

## Guest lifecycle

An authorized administrator creates an invitation with a category, approved resource names and an expiry. In production, set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` and `SMTP_FROM`; invitation and email verification tokens are sent using TLS. With no SMTP configured in development only, one-time tokens are returned in API responses for testing. Do not expose that development mode publicly. Set a stable `GUEST_MFA_ENCRYPTION_KEY` in production and across local restarts so encrypted authenticator secrets remain decryptable if the JWT signing key rotates.

The guest registers a password, verifies the email, enrolls the returned TOTP secret in an authenticator app, and waits for an administrator other than the inviter to approve access. Guest login requires password plus a current six-digit TOTP code. Guest sessions last 15 minutes. Expiry and revocation immediately disable later API requests. Visitors have access only to `/api/security/guest-demo`, which returns isolated synthetic data; they cannot access production dashboards or logs.

After login, guest accounts land on the Guest Access portal, which shows only the invitation's approved resources and expiry. Visitors see the isolated synthetic sample in that portal.

Guest resources can scope the existing `AUDIT_TRAIL`, `FINANCIAL_ACTIVITY`, `EXECUTIVE_SUMMARY` and `OPERATIONS` reports using `audit_reports`, `financial_reports`, `business_reports`, `project_reports` and `vendor_reports`. This repository has no purchase-order, vendor master, project or guest-session domain models; corresponding connectors and record-level ABAC must be implemented when those ERP data sources are integrated. The system does not grant those guests direct production module access.

## Offboarding

`POST /api/security/offboarding` records an HR/security exit request with an effective time. A background watchdog processes due requests within approximately 30 seconds; authenticated requests also trigger a due check. Completion disables authentication, rotates the password to an unavailable random value, demotes the account to the least-privilege role, and records a report. Historical logs and audit entries are retained. The final active administrator cannot be offboarded.

## Audit integrity and backups

New audit events are append-only through the application ORM and include a SHA-256 chain link. Existing rows are chained on startup. `/api/security/audit/integrity` verifies the chain, and the watchdog raises a critical alert if it detects a broken link. Audit retention is indefinite by default with a configurable minimum; the minimum may only increase through two-person approval, and there is no audit deletion API.

Configure `AUDIT_BACKUP_DIR` to a protected mount on independently managed storage and `AUDIT_SIGNING_KEY` to a separate secret to enable signed JSON snapshots at `/api/security/audit/backups`. Dashboard backup status is `not_configured` until a snapshot exists. A directory on the same host and credentials as the database is not independent backup custody.

The chain detects record mutation/removal but is not a hardware-backed or database-owner-proof WORM store. A database owner can bypass ORM guards, and an operator controlling both the database and signing key can forge a local backup. For stronger assurance, ship signed backups to externally administered object-lock/WORM storage and keep the signing key in a separate KMS/HSM. Agent ingestion is authenticated with per-agent credentials; agents should use HTTPS and a protected local SQLite queue.

## APIs and dashboard

Key endpoints:

- `GET /api/security/controls/overview`: dashboard-safe DLP/guest/retention/integrity aggregates.
- `GET /api/security/dlp/policies`, `PATCH /api/security/dlp/policies/{classification}`.
- `POST /api/security/approvals`, `GET /api/security/approvals`, `POST /api/security/approvals/{id}/vote`.
- `POST /api/security/guests/invitations`, `/guests/register`, `/guests/verify`, `/{id}/approve`, `/{id}/revoke`.
- `POST` and `GET /api/security/offboarding`.
- `GET /api/security/audit/integrity`, `/audit/retention`, and `POST /api/security/audit/backups`.

The existing dashboard shows persisted export decisions, guest status/expiry (identities only for security roles), offboarding, approval backlog, retention, integrity and backup status. Detailed guest/DLP rows are withheld from dashboard-only roles.
