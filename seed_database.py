"""Seed the database with reference data, demo users and ~10,000 synthetic ERP logs.

Usage (from backend/):  python seed_database.py [--logs N] [--days D] [--seed S]   (--logs 0 skips logs)
Later phases extend this script with alerts, security events, etc. derived from those logs.
"""
import argparse
from collections import Counter

from sqlalchemy import select

from app.core.database import Base, SessionLocal, engine
import app.models  # noqa: F401
from app.core.security import hash_password
from app.models.auth import Role, User
from app.models.logs import Log
from app.anomaly.engine import run_anomaly_detection
from app.security.engine import run_rules
from app.services.bootstrap import bootstrap
from app.services.generator import generate_logs
from app.services.pipeline import ingest_dicts

DEMO_USERS = [
    ("admin", "Admin@12345", "ADMIN", "System Administrator"),
    ("analyst", "Analyst@12345", "SECURITY_ANALYST", "Sam Analyst"),
    ("manager", "Manager@12345", "MANAGER", "Maya Manager"),
    ("auditor", "Auditor@12345", "AUDITOR", "Alex Auditor"),
    ("viewer", "Viewer@12345", "VIEWER", "Vic Viewer"),
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logs", type=int, default=10000, help="synthetic logs to create (0 = none)")
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        bootstrap(db)
        for username, password, role_name, full_name in DEMO_USERS:
            if db.scalar(select(User).where(User.username == username)):
                continue
            role = db.scalar(select(Role).where(Role.name == role_name))
            db.add(User(username=username, email=f"{username}@erp-sentinel.example.com", full_name=full_name,
                        password_hash=hash_password(password), role_id=role.id))
        db.commit()
        if args.logs and db.query(Log).count() == 0:   # idempotent: never duplicates demo data
            gen = generate_logs(args.logs, args.days, args.seed)
            fr = ingest_dicts(db, gen.records, source_name="demo-generator", filename="seed")
            kinds = dict(Counter(m["scenario"] for m in gen.manifest))
            print(f"Imported {fr.imported} of {fr.total} generated logs; injected scenarios: {kinds}")
    with SessionLocal() as db:
        res = run_rules(db)
        print(f"Rule engine: {res['created']} new alert(s), {res['existing']} already known")
        an = run_anomaly_detection(db)
        print(f"Anomaly detection: {an['created']} anomalies ({an['by_kind']}), {an['alerts_created']} alert(s)")
    print("Seed complete. Demo logins:")
    for username, password, role_name, _ in DEMO_USERS:
        print(f"  {username:8s} / {password:14s} ({role_name})")


if __name__ == "__main__":
    main()
